import Foundation
import ValorantAPI

enum FriendChangeKind: String, Codable, Sendable {
	case acceptedRequest
	case removedFriend
	case requestNoLongerPending
	case addedFriend
}

struct FriendListChangeEvent: Identifiable, Codable, Equatable, Sendable {
	var id: UUID = UUID()
	var jid: String
	var puuid: User.ID?
	var gameName: String
	var tagLine: String
	var kind: FriendChangeKind
	var timestamp: Date
	
	var displayName: String {
		if !gameName.isEmpty {
			return tagLine.isEmpty ? gameName : "\(gameName)#\(tagLine)"
		}
		return jid
	}
}

@MainActor
final class SocialManager: ObservableObject {
	enum ConnectionState: Equatable {
		case disconnected
		case connecting
		case connected
		case failed(String)
	}
	
	private struct CachedSocialAccount: Codable {
		var friendsByJID: [String: XMPPFriend] = [:]
		var snapshotSubscriptions: [String: String] = [:]
		var changeEvents: [FriendListChangeEvent] = []
		var lastSyncedAt: Date?
		var lastPresenceAt: Date?
	}
	
	private static let cacheFilename = "SocialCache.v2.json"
	private static let backgroundRefreshInterval: TimeInterval = 300
	private static let offlineDemoteInterval: TimeInterval = 1800
	
	@Published var connectionState: ConnectionState = .disconnected
	@Published var friendsByJID: [String: XMPPFriend] = [:]
	@Published var messagesByJID: [String: [XMPPChatMessage]] = [:]
	@Published var unreadByJID: [String: Int] = [:]
	@Published var changeEvents: [FriendListChangeEvent] = []
	@Published var activeChatJID: String?
	@Published var myJID: String = ""
	@Published var myPresence: XMPPPresenceUpdate?
	@Published var lastSyncedAt: Date?
	@Published var isRefreshing = false
	
	private let client = XMPPClient()
	private var connectedUserID: User.ID?
	private var loadedCacheUserID: User.ID?
	private var connectAttempt = 0
	private var snapshotSubscriptions: [String: String] = [:]
	private var locallyRemovedJIDs: Set<String> = []
	private var resourcesByJID: [String: [String: XMPPPresenceUpdate]] = [:]
	private var ownResources: [String: XMPPPresenceUpdate] = [:]
	private var lastPresenceAt: Date?
	private var deferredSaveTask: Task<Void, Never>?
	private var refreshResetTask: Task<Void, Never>?
	
	var friends: [XMPPFriend] {
		friendsByJID.values.sorted { lhs, rhs in
			if lhs.isIncomingRequest != rhs.isIncomingRequest {
				return lhs.isIncomingRequest
			}
			if lhs.status != rhs.status {
				return lhs.status < rhs.status
			}
			return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
		}
	}
	
	var onlineCount: Int {
		friendsByJID.values.filter {
			!$0.isIncomingRequest && !$0.isOutgoingRequest && $0.status != .offline
		}.count
	}
	
	var confirmedFriendCount: Int {
		friendsByJID.values.filter { !$0.isIncomingRequest && !$0.isOutgoingRequest }.count
	}
	
	var outgoingRequestCount: Int {
		friendsByJID.values.filter(\.isOutgoingRequest).count
	}
	
	var incomingRequestCount: Int {
		friendsByJID.values.filter(\.isIncomingRequest).count
	}
	
	func connectIfNeeded(using apiClient: ValorantClient?) async {
		guard let apiClient else {
			await disconnect()
			return
		}
		
		loadCacheIfNeeded(for: apiClient.userID)
		
		if connectedUserID == apiClient.userID {
			if connectionState == .connected {
				if isBackgroundRefreshDue {
					await refreshRosterInBackground()
				}
				return
			}
			if connectionState == .connecting {
				return
			}
		}
		
		await reconnect(using: apiClient, clearExisting: false)
	}
	
	func reconnect(using apiClient: ValorantClient, clearExisting: Bool = false) async {
		connectAttempt += 1
		let attempt = connectAttempt
		await client.disconnect() // cancels any stuck in-flight attempt
		loadCacheIfNeeded(for: apiClient.userID)
		connectedUserID = apiClient.userID
		connectionState = .connecting
		if clearExisting {
			friendsByJID = [:]
		}
		do {
			try await client.connect(client: apiClient) { [weak self] event in
				await self?.handle(event)
			}
		} catch {
			guard attempt == connectAttempt else { return } // superseded by a newer attempt
			await client.disconnect()
			connectionState = .failed(error.localizedDescription)
		}
	}
	
	func refreshNow(using apiClient: ValorantClient) async {
		if connectionState == .connected {
			isRefreshing = true
			refreshResetTask?.cancel()
			refreshResetTask = Task { [weak self] in
				try? await Task.sleep(for: .seconds(6))
				guard !Task.isCancelled else { return }
				self?.isRefreshing = false
			}
			do {
				try await client.requestRosterRefresh()
			} catch {
				refreshResetTask?.cancel()
				isRefreshing = false
				await reconnect(using: apiClient, clearExisting: false)
			}
		} else {
			await reconnect(using: apiClient, clearExisting: false)
		}
	}
	
	private var isBackgroundRefreshDue: Bool {
		guard let lastSyncedAt else { return true }
		return Date().timeIntervalSince(lastSyncedAt) >= Self.backgroundRefreshInterval
	}
	
	private func refreshRosterInBackground() async {
		guard connectionState == .connected else { return }
		try? await client.requestRosterRefresh()
	}
	
	func disconnect() async {
		refreshResetTask?.cancel()
		deferredSaveTask?.cancel()
		await client.disconnect()
		connectedUserID = nil
		loadedCacheUserID = nil
		connectionState = .disconnected
		friendsByJID = [:]
		snapshotSubscriptions = [:]
		locallyRemovedJIDs = []
		resourcesByJID = [:]
		ownResources = [:]
		changeEvents = []
		unreadByJID = [:]
		myJID = ""
		myPresence = nil
		lastSyncedAt = nil
		lastPresenceAt = nil
		isRefreshing = false
	}
	
	func sendMessage(to jid: String, body: String) async throws {
		let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		try await client.sendMessage(to: jid, body: trimmed)
		let message = XMPPChatMessage(
			id: UUID().uuidString,
			peerJID: jid,
			isOutgoing: true,
			body: trimmed,
			timestamp: Date()
		)
		appendMessage(message, for: jid)
	}
	
	func loadHistory(for jid: String) async {
		unreadByJID[jid] = 0
		try? await client.requestArchive(with: jid)
	}
	
	func addFriend(gameName: String, tagLine: String) async throws {
		try await client.addFriend(gameName: gameName, tagLine: tagLine)
	}
	
	func acceptFriend(_ friend: XMPPFriend) async throws {
		try await client.acceptFriend(jid: friend.jid)
		friendsByJID[friend.jid]?.subscription = "both"
		snapshotSubscriptions[friend.jid] = "both"
		scheduleCacheSave()
	}
	
	func removeFriend(_ friend: XMPPFriend) async throws {
		locallyRemovedJIDs.insert(friend.jid)
		try await client.removeFriend(jid: friend.jid)
		friendsByJID.removeValue(forKey: friend.jid)
		snapshotSubscriptions.removeValue(forKey: friend.jid)
		scheduleCacheSave()
	}
	
	func markRead(jid: String) {
		unreadByJID[jid] = 0
	}
	
	private func handle(_ event: XMPPEvent) {
		switch event {
		case .connected(let jid):
			self.myJID = jid
			self.resourcesByJID = [:]
			self.ownResources = [:]
			self.connectionState = .connected
			
		case .disconnected(let error):
			self.isRefreshing = false
			if let error {
				self.connectionState = .failed(error.localizedDescription)
			} else {
				self.connectionState = .disconnected
			}
			
		case let .rosterReceived(list, isFullSnapshot):
			let previousFriends = friendsByJID
			
			for item in list {
				if item.subscription == "remove" {
					friendsByJID.removeValue(forKey: item.jid)
					resourcesByJID.removeValue(forKey: item.jid)
				} else if var existing = friendsByJID[item.jid] {
					if !item.gameName.isEmpty { existing.gameName = item.gameName }
					if !item.tagLine.isEmpty { existing.tagLine = item.tagLine }
					existing.subscription = item.subscription
					existing.puuid = existing.puuid ?? item.puuid
					if isFullSnapshot || item.note != nil {
						existing.note = item.note
					}
					existing.lastOnline = Self.newerDate(existing.lastOnline, item.lastOnline)
					friendsByJID[item.jid] = existing
				} else {
					friendsByJID[item.jid] = item
				}
			}
			
			if isFullSnapshot {
				let activeItems = list.filter { $0.subscription != "remove" }
				let activeJIDs = Set(activeItems.map(\.jid))
				let newSubs = Dictionary(
					activeItems.map { ($0.jid, $0.subscription) },
					uniquingKeysWith: { _, latest in latest }
				)
				
				if !snapshotSubscriptions.isEmpty {
					diffRosterForChanges(
						oldSubs: snapshotSubscriptions,
						oldFriends: previousFriends,
						newSubs: newSubs
					)
				}
				
				for jid in Array(friendsByJID.keys) where !activeJIDs.contains(jid) {
					friendsByJID.removeValue(forKey: jid)
					resourcesByJID.removeValue(forKey: jid)
				}
				
				snapshotSubscriptions = newSubs
				locallyRemovedJIDs.removeAll()
				lastSyncedAt = Date()
				refreshResetTask?.cancel()
				isRefreshing = false
				saveCacheNow()
			} else {
				scheduleCacheSave()
			}
			
		case .presenceUpdated(let update):
			if isOwnPresenceJID(update.jid) {
				if update.status == .offline {
					if update.resource.isEmpty {
						ownResources.removeAll()
					} else {
						ownResources.removeValue(forKey: update.resource)
					}
				} else {
					ownResources[update.resource] = update
				}
				self.myPresence = Self.pickBestPresence(from: ownResources.values) ?? update
				return
			}
			
			var friend = friendsByJID[update.jid] ?? XMPPFriend(
				jid: update.jid,
				puuid: update.jid.components(separatedBy: "@").first.flatMap(User.ID.init),
				gameName: "",
				tagLine: "",
				subscription: "both"
			)
			let wasOnline = friend.status != .offline
			
			if let cardID = update.playerCardID {
				friend.playerCardID = cardID
			}
			if let tier = update.competitiveTier {
				friend.competitiveTier = tier
			}
			if let level = update.accountLevel {
				friend.accountLevel = level
			}
			friend.lastOnline = Self.newerDate(friend.lastOnline, update.lastOnline)
			
			if update.status == .offline {
				if update.resource.isEmpty {
					resourcesByJID[update.jid] = [:]
				} else {
					resourcesByJID[update.jid]?[update.resource] = nil
				}
			} else {
				resourcesByJID[update.jid, default: [:]][update.resource] = update
			}
			
			if let best = Self.pickBestPresence(from: resourcesByJID[update.jid]?.values ?? Dictionary<String, XMPPPresenceUpdate>().values) {
				friend.status = best.status
				friend.gameTitle = best.gameTitle
				friend.statusText = best.statusText
				friend.mapPath = best.mapPath
				friend.queueID = best.queueID
				friend.provisioningFlow = best.provisioningFlow
				friend.allyScore = best.allyScore
				friend.enemyScore = best.enemyScore
				friend.partyID = best.partyID
				friend.partySize = best.partySize
				friend.maxPartySize = best.maxPartySize
				friend.isPartyOwner = best.isPartyOwner
				if let tier = best.competitiveTier { friend.competitiveTier = tier }
				if let level = best.accountLevel { friend.accountLevel = level }
				if let card = best.playerCardID { friend.playerCardID = card }
			} else {
				friend.status = .offline
				friend.gameTitle = nil
				friend.statusText = nil
				friend.mapPath = nil
				friend.queueID = nil
				friend.provisioningFlow = nil
				friend.allyScore = nil
				friend.enemyScore = nil
				friend.partyID = nil
				friend.partySize = nil
				friend.maxPartySize = nil
				friend.isPartyOwner = false
				if friend.lastOnline == nil && (wasOnline || update.lastOnline != nil) {
					friend.lastOnline = update.lastOnline ?? Date()
				}
			}
			
			friendsByJID[update.jid] = friend
			lastPresenceAt = Date()
			scheduleCacheSave()
			
		case .messageReceived(let msg):
			appendMessage(msg, for: msg.peerJID)
			if !msg.isOutgoing && activeChatJID != msg.peerJID {
				unreadByJID[msg.peerJID, default: 0] += 1
			}
			
		case let .archiveReceived(peerJID, history):
			let existing = messagesByJID[peerJID] ?? []
			let seenIDs = Set(existing.map(\.id))
			let merged = (existing + history.filter { !seenIDs.contains($0.id) })
				.sorted { $0.timestamp < $1.timestamp }
			messagesByJID[peerJID] = merged
		}
	}
	
	private static func newerDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
		switch (lhs, rhs) {
		case let (.some(l), .some(r)): return max(l, r)
		case let (.some(l), .none): return l
		case let (.none, .some(r)): return r
		case (.none, .none): return nil
		}
	}
	
	private static func gamePriority(for title: String?) -> Int {
		switch title {
		case "VALORANT": return 0
		case "League of Legends", "Teamfight Tactics", "Legends of Runeterra": return 1
		case "Riot Client": return 2
		default: return 3
		}
	}
	
	private static func pickBestPresence<S: Sequence>(from updates: S) -> XMPPPresenceUpdate? where S.Element == XMPPPresenceUpdate {
		updates
			.filter { $0.status != .offline }
			.min { lhs, rhs in
				let lp = gamePriority(for: lhs.gameTitle)
				let rp = gamePriority(for: rhs.gameTitle)
				if lp != rp { return lp < rp }
				if lhs.status != rhs.status { return lhs.status < rhs.status }
				return lhs.resource < rhs.resource
			}
	}
	
	private func isOwnPresenceJID(_ jid: String) -> Bool {
		if !myJID.isEmpty && jid.caseInsensitiveCompare(myJID) == .orderedSame {
			return true
		}
		if let uid = connectedUserID?.description,
		   let node = jid.components(separatedBy: "@").first,
		   node.caseInsensitiveCompare(uid) == .orderedSame {
			return true
		}
		return false
	}
	
	private func diffRosterForChanges(
		oldSubs: [String: String],
		oldFriends: [String: XMPPFriend],
		newSubs: [String: String]
	) {
		let now = Date()
		var appended: [FriendListChangeEvent] = []
		
		for (jid, oldSub) in oldSubs {
			if locallyRemovedJIDs.contains(jid) { continue }
			let oldFriend = oldFriends[jid]
			let name = oldFriend?.gameName ?? ""
			let tag = oldFriend?.tagLine ?? ""
			let puuid = oldFriend?.puuid
			let newSub = newSubs[jid]
			
			if oldSub == "both" && newSub == nil {
				appended.append(FriendListChangeEvent(
					jid: jid, puuid: puuid, gameName: name, tagLine: tag,
					kind: .removedFriend, timestamp: now
				))
			} else if oldSub == "pending_out" && newSub == "both" {
				let current = friendsByJID[jid]
				appended.append(FriendListChangeEvent(
					jid: jid,
					puuid: current?.puuid ?? puuid,
					gameName: (current?.gameName.isEmpty == false ? current?.gameName : nil) ?? name,
					tagLine: (current?.tagLine.isEmpty == false ? current?.tagLine : nil) ?? tag,
					kind: .acceptedRequest,
					timestamp: now
				))
			} else if oldSub == "pending_out" && newSub == nil {
				appended.append(FriendListChangeEvent(
					jid: jid, puuid: puuid, gameName: name, tagLine: tag,
					kind: .requestNoLongerPending, timestamp: now
				))
			}
		}
		
		for (jid, newSub) in newSubs where oldSubs[jid] == nil && newSub == "both" {
			let current = friendsByJID[jid]
			appended.append(FriendListChangeEvent(
				jid: jid,
				puuid: current?.puuid,
				gameName: current?.gameName ?? "",
				tagLine: current?.tagLine ?? "",
				kind: .addedFriend,
				timestamp: now
			))
		}
		
		guard !appended.isEmpty else { return }
		changeEvents.insert(contentsOf: appended, at: 0)
		if changeEvents.count > 200 {
			changeEvents = Array(changeEvents.prefix(200))
		}
	}
	
	private func cacheKey(for userID: User.ID) -> String {
		userID.description.lowercased()
	}
	
	private func loadCacheIfNeeded(for userID: User.ID) {
		guard loadedCacheUserID != userID else { return }
		loadedCacheUserID = userID
		myPresence = nil
		locallyRemovedJIDs = []
		resourcesByJID = [:]
		ownResources = [:]
		
		let allCaches = LocalJSONStore.load([String: CachedSocialAccount].self, from: Self.cacheFilename) ?? [:]
		guard let cached = allCaches[cacheKey(for: userID)] else {
			friendsByJID = [:]
			snapshotSubscriptions = [:]
			changeEvents = []
			lastSyncedAt = nil
			lastPresenceAt = nil
			return
		}
		
		var restoredFriends = cached.friendsByJID
		let stalePresence = cached.lastPresenceAt.map {
			Date().timeIntervalSince($0) >= Self.offlineDemoteInterval
		} ?? true
		if stalePresence {
			for jid in restoredFriends.keys {
				restoredFriends[jid]?.status = .offline
				restoredFriends[jid]?.gameTitle = nil
				restoredFriends[jid]?.mapPath = nil
				restoredFriends[jid]?.queueID = nil
				restoredFriends[jid]?.provisioningFlow = nil
				restoredFriends[jid]?.allyScore = nil
				restoredFriends[jid]?.enemyScore = nil
				restoredFriends[jid]?.partyID = nil
				restoredFriends[jid]?.partySize = nil
				restoredFriends[jid]?.maxPartySize = nil
				restoredFriends[jid]?.isPartyOwner = false
			}
		}
		
		friendsByJID = restoredFriends
		snapshotSubscriptions = cached.snapshotSubscriptions
		changeEvents = cached.changeEvents
		lastSyncedAt = cached.lastSyncedAt
		lastPresenceAt = cached.lastPresenceAt
	}
	
	private func scheduleCacheSave() {
		deferredSaveTask?.cancel()
		deferredSaveTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(2))
			guard !Task.isCancelled else { return }
			self?.saveCacheNow()
		}
	}
	
	private func saveCacheNow() {
		guard let userID = connectedUserID ?? loadedCacheUserID else { return }
		var allCaches = LocalJSONStore.load([String: CachedSocialAccount].self, from: Self.cacheFilename) ?? [:]
		allCaches[cacheKey(for: userID)] = CachedSocialAccount(
			friendsByJID: friendsByJID,
			snapshotSubscriptions: snapshotSubscriptions,
			changeEvents: changeEvents,
			lastSyncedAt: lastSyncedAt,
			lastPresenceAt: lastPresenceAt
		)
		LocalJSONStore.save(allCaches, to: Self.cacheFilename)
	}
	
	private func appendMessage(_ msg: XMPPChatMessage, for jid: String) {
		var list = messagesByJID[jid] ?? []
		if !list.contains(where: { $0.id == msg.id }) {
			list.append(msg)
			list.sort { $0.timestamp < $1.timestamp }
			messagesByJID[jid] = list
		}
	}
}
