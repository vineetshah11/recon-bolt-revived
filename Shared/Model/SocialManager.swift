import Foundation
import Combine
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
		var messagesByJID: [String: [XMPPChatMessage]] = [:]
		var cachedCardByPUUID: [String: PlayerCard.ID] = [:]
		var lastSyncedAt: Date?
		var lastPresenceAt: Date?
		
		init(
			friendsByJID: [String: XMPPFriend] = [:],
			snapshotSubscriptions: [String: String] = [:],
			changeEvents: [FriendListChangeEvent] = [],
			messagesByJID: [String: [XMPPChatMessage]] = [:],
			cachedCardByPUUID: [String: PlayerCard.ID] = [:],
			lastSyncedAt: Date? = nil,
			lastPresenceAt: Date? = nil
		) {
			self.friendsByJID = friendsByJID
			self.snapshotSubscriptions = snapshotSubscriptions
			self.changeEvents = changeEvents
			self.messagesByJID = messagesByJID
			self.cachedCardByPUUID = cachedCardByPUUID
			self.lastSyncedAt = lastSyncedAt
			self.lastPresenceAt = lastPresenceAt
		}
		
		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			friendsByJID = try container.decodeIfPresent([String: XMPPFriend].self, forKey: .friendsByJID) ?? [:]
			snapshotSubscriptions = try container.decodeIfPresent([String: String].self, forKey: .snapshotSubscriptions) ?? [:]
			changeEvents = try container.decodeIfPresent([FriendListChangeEvent].self, forKey: .changeEvents) ?? []
			messagesByJID = try container.decodeIfPresent([String: [XMPPChatMessage]].self, forKey: .messagesByJID) ?? [:]
			cachedCardByPUUID = try container.decodeIfPresent([String: PlayerCard.ID].self, forKey: .cachedCardByPUUID) ?? [:]
			lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
			lastPresenceAt = try container.decodeIfPresent(Date.self, forKey: .lastPresenceAt)
		}
	}
	
	private static let cacheFilename = "SocialCache.v2.json"
	private static let backgroundRefreshInterval: TimeInterval = 300
	private static let offlineDemoteInterval: TimeInterval = 1800
	private static let maxCachedMessagesPerConversation = 300
	
	@Published var connectionState: ConnectionState = .disconnected
	@Published var friendsByJID: [String: XMPPFriend] = [:]
	@Published var messagesByJID: [String: [XMPPChatMessage]] = [:]
	@Published var unreadByJID: [String: Int] = [:]
	@Published var loadingHistoryJIDs: Set<String> = []
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
	private var cachedCardByPUUID: [String: PlayerCard.ID] = [:]
	private var cachedCardDateByPUUID: [String: Date] = [:]
	private var pendingHistoryJIDs: Set<String> = []
	private var lastPresenceAt: Date?
	private var deferredSaveTask: Task<Void, Never>?
	private var refreshResetTask: Task<Void, Never>?
	
	init() {
		LocalDataProvider.onIdentitiesStored = { [weak self] identities, updateTime in
			Task { @MainActor [weak self] in
				self?.cacheIdentities(identities, asOf: updateTime)
			}
		}
	}
	
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
		cachedCardByPUUID = [:]
		cachedCardDateByPUUID = [:]
		pendingHistoryJIDs = []
		loadingHistoryJIDs = []
		messagesByJID = [:]
		changeEvents = []
		unreadByJID = [:]
		myJID = ""
		myPresence = nil
		lastSyncedAt = nil
		lastPresenceAt = nil
		isRefreshing = false
	}
	
	func messages(for jid: String) -> [XMPPChatMessage] {
		messagesByJID[canonicalJID(for: jid)] ?? messagesByJID[jid] ?? []
	}
	
	func isLoadingHistory(for jid: String) -> Bool {
		loadingHistoryJIDs.contains(canonicalJID(for: jid)) || loadingHistoryJIDs.contains(jid)
	}
	
	func sendMessage(to jid: String, body: String) async throws {
		let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		let target = canonicalJID(for: jid)
		let sentID = try await client.sendMessage(to: target, body: trimmed)
		let message = XMPPChatMessage(
			id: sentID,
			peerJID: target,
			isOutgoing: true,
			body: trimmed,
			timestamp: Date()
		)
		appendMessage(message, for: target)
		saveCacheNow()
	}
	
	func loadHistory(for jid: String) async {
		let target = canonicalJID(for: jid)
		unreadByJID[target] = 0
		if target != jid { unreadByJID[jid] = 0 }
		
		guard connectionState == .connected else {
			pendingHistoryJIDs.insert(target)
			return
		}
		pendingHistoryJIDs.remove(target)
		loadingHistoryJIDs.insert(target)
		Task { [weak self] in
			try? await Task.sleep(for: .seconds(6))
			self?.loadingHistoryJIDs.remove(target)
		}
		do {
			try await client.requestArchive(with: target)
		} catch {
			loadingHistoryJIDs.remove(target)
		}
	}
	
	func cacheIdentity(_ identity: Player.Identity, competitiveTier: Int? = nil, asOf updateTime: Date = .now) {
		var tiers: [User.ID: Int] = [:]
		if let competitiveTier {
			tiers[identity.id] = competitiveTier
		}
		cacheIdentities([identity], competitiveTierByID: tiers, asOf: updateTime)
	}
	
	func cacheIdentities(
		_ identities: [Player.Identity],
		competitiveTierByID: [User.ID: Int] = [:],
		asOf updateTime: Date = .now
	) {
		var didUpdate = false
		for identity in identities {
			let key = identity.id.description.lowercased()
			if let previousDate = cachedCardDateByPUUID[key], updateTime < previousDate {
				continue
			}
			if !identity.cardID.isPseudoNull {
				cachedCardDateByPUUID[key] = updateTime
				if cachedCardByPUUID[key] != identity.cardID {
					cachedCardByPUUID[key] = identity.cardID
					didUpdate = true
				}
			}
			for jid in friendsByJID.keys {
				let matchesPUUID = friendsByJID[jid]?.puuid?.description.lowercased() == key
				let matchesNode = jid.split(separator: "@").first?.lowercased() == key
				guard matchesPUUID || matchesNode, var friend = friendsByJID[jid] else { continue }
				
				var changedFriend = false
				if !identity.cardID.isPseudoNull, friend.playerCardID != identity.cardID {
					friend.playerCardID = identity.cardID
					changedFriend = true
				}
				if identity.accountLevel > 0, (friend.accountLevel ?? 0) < identity.accountLevel {
					friend.accountLevel = identity.accountLevel
					changedFriend = true
				}
				if let tier = competitiveTierByID[identity.id], tier >= 3, friend.competitiveTier == nil {
					friend.competitiveTier = tier
					changedFriend = true
				}
				if changedFriend {
					friendsByJID[jid] = friend
					didUpdate = true
				}
			}
		}
		if didUpdate {
			scheduleCacheSave()
		}
	}
	
	private func hydrateFriendCardsFromLocalData() async {
		let targetIDs: [User.ID] = friendsByJID.values.compactMap { friend in
			guard friend.playerCardID == nil else { return nil }
			if let puuid = friend.puuid { return puuid }
			if let node = friend.jid.split(separator: "@").first {
				return User.ID(String(node))
			}
			return nil
		}
		guard !targetIDs.isEmpty else { return }
		let identities = await LocalDataProvider.shared.playerIdentityManager.cachedObjects(for: targetIDs)
		if !identities.isEmpty {
			cacheIdentities(identities, asOf: .distantPast)
		}
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
		let target = canonicalJID(for: jid)
		unreadByJID[target] = 0
		if target != jid { unreadByJID[jid] = 0 }
	}
	
	private func canonicalJID(for rawJID: String) -> String {
		let bare = rawJID.components(separatedBy: "/").first ?? rawJID
		if friendsByJID[bare] != nil {
			return bare
		}
		if let exact = friendsByJID.keys.first(where: { $0.caseInsensitiveCompare(bare) == .orderedSame }) {
			return exact
		}
		if let node = bare.split(separator: "@").first?.lowercased(),
		   let byPUUID = friendsByJID.keys.first(where: { $0.split(separator: "@").first?.lowercased() == node }) {
			return byPUUID
		}
		return bare
	}
	
	private func handle(_ event: XMPPEvent) {
		switch event {
		case .connected(let jid):
			self.myJID = jid
			self.resourcesByJID = [:]
			self.ownResources = [:]
			self.connectionState = .connected
			var toLoad = pendingHistoryJIDs
			if let active = activeChatJID {
				toLoad.insert(canonicalJID(for: active))
			}
			pendingHistoryJIDs.removeAll()
			for peer in toLoad {
				Task { await self.loadHistory(for: peer) }
			}
			
		case .disconnected(let error):
			self.isRefreshing = false
			self.loadingHistoryJIDs.removeAll()
			if let error {
				self.connectionState = .failed(error.localizedDescription)
			} else {
				self.connectionState = .disconnected
			}
			
		case let .rosterReceived(list, isFullSnapshot):
			let previousFriends = friendsByJID
			
			for var item in list {
				if item.subscription == "remove" {
					friendsByJID.removeValue(forKey: item.jid)
					resourcesByJID.removeValue(forKey: item.jid)
				} else if var existing = friendsByJID[item.jid] {
					if !item.gameName.isEmpty { existing.gameName = item.gameName }
					if !item.tagLine.isEmpty { existing.tagLine = item.tagLine }
					existing.subscription = item.subscription
					existing.puuid = existing.puuid ?? item.puuid
					if existing.playerCardID == nil,
					   let key = existing.puuid?.description.lowercased() ?? item.jid.split(separator: "@").first?.lowercased(),
					   let cachedCard = cachedCardByPUUID[key] {
						existing.playerCardID = cachedCard
					}
					if isFullSnapshot || item.note != nil {
						existing.note = item.note
					}
					existing.lastOnline = Self.newerDate(existing.lastOnline, item.lastOnline)
					friendsByJID[item.jid] = existing
				} else {
					if item.playerCardID == nil,
					   let key = item.puuid?.description.lowercased() ?? item.jid.split(separator: "@").first?.lowercased(),
					   let cachedCard = cachedCardByPUUID[key] {
						item.playerCardID = cachedCard
					}
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
				Task { await self.hydrateFriendCardsFromLocalData() }
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
				if !cardID.isPseudoNull,
				   let puuidKey = friend.puuid?.description.lowercased() ?? update.jid.split(separator: "@").first?.lowercased() {
					cachedCardByPUUID[puuidKey] = cardID
					cachedCardDateByPUUID[puuidKey] = Date()
				}
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
			let peer = canonicalJID(for: msg.peerJID)
			var normalized = msg
			normalized.peerJID = peer
			appendMessage(normalized, for: peer)
			if !msg.isOutgoing && canonicalJID(for: activeChatJID ?? "") != peer {
				unreadByJID[peer, default: 0] += 1
			}
			scheduleCacheSave()
			
		case let .archiveReceived(rawPeerJID, history):
			let peer = canonicalJID(for: rawPeerJID)
			loadingHistoryJIDs.remove(peer)
			loadingHistoryJIDs.remove(rawPeerJID)
			if !history.isEmpty {
				mergeArchive(history, for: peer)
				saveCacheNow()
			}
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
			messagesByJID = [:]
			cachedCardByPUUID = [:]
			lastSyncedAt = nil
			lastPresenceAt = nil
			return
		}
		
		cachedCardByPUUID = cached.cachedCardByPUUID
		var restoredFriends = cached.friendsByJID
		let stalePresence = cached.lastPresenceAt.map {
			Date().timeIntervalSince($0) >= Self.offlineDemoteInterval
		} ?? true
		for jid in restoredFriends.keys {
			if restoredFriends[jid]?.playerCardID == nil,
			   let key = restoredFriends[jid]?.puuid?.description.lowercased() ?? jid.split(separator: "@").first?.lowercased(),
			   let cachedCard = cachedCardByPUUID[key] {
				restoredFriends[jid]?.playerCardID = cachedCard
			}
			if stalePresence {
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
		messagesByJID = cached.messagesByJID
		lastSyncedAt = cached.lastSyncedAt
		lastPresenceAt = cached.lastPresenceAt
		Task { await self.hydrateFriendCardsFromLocalData() }
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
		let trimmedMessages = messagesByJID.mapValues { list in
			Array(list.suffix(Self.maxCachedMessagesPerConversation))
		}
		var allCaches = LocalJSONStore.load([String: CachedSocialAccount].self, from: Self.cacheFilename) ?? [:]
		allCaches[cacheKey(for: userID)] = CachedSocialAccount(
			friendsByJID: friendsByJID,
			snapshotSubscriptions: snapshotSubscriptions,
			changeEvents: changeEvents,
			messagesByJID: trimmedMessages,
			cachedCardByPUUID: cachedCardByPUUID,
			lastSyncedAt: lastSyncedAt,
			lastPresenceAt: lastPresenceAt
		)
		LocalJSONStore.save(allCaches, to: Self.cacheFilename)
	}
	
	private func isDuplicateMessage(_ lhs: XMPPChatMessage, _ rhs: XMPPChatMessage) -> Bool {
		lhs.id == rhs.id
		|| (lhs.isOutgoing == rhs.isOutgoing
			&& lhs.body == rhs.body
			&& abs(lhs.timestamp.timeIntervalSince(rhs.timestamp)) < 15)
	}
	
	private func appendMessage(_ msg: XMPPChatMessage, for jid: String) {
		mergeArchive([msg], for: jid)
	}
	
	private func mergeArchive(_ history: [XMPPChatMessage], for peerJID: String) {
		var merged = messagesByJID[peerJID] ?? []
		var didChange = false
		for item in history {
			var normalized = item
			normalized.peerJID = peerJID
			if !merged.contains(where: { isDuplicateMessage($0, normalized) }) {
				merged.append(normalized)
				didChange = true
			}
		}
		guard didChange else { return }
		merged.sort { $0.timestamp < $1.timestamp }
		if merged.count > Self.maxCachedMessagesPerConversation {
			merged = Array(merged.suffix(Self.maxCachedMessagesPerConversation))
		}
		messagesByJID[peerJID] = merged
	}
}
