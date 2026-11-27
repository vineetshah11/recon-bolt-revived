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

struct SocialFriendsBackup: Codable {
	var friendsByJID: [String: XMPPFriend] = [:]
	var snapshotSubscriptions: [String: String] = [:]
	var changeEvents: [FriendListChangeEvent] = []
	var cachedCardByPUUID: [String: PlayerCard.ID] = [:]
	var pinnedFriendJIDs: Set<String> = []
	var lastSyncedAt: Date?
	var lastPresenceAt: Date?
	
	private enum CodingKeys: String, CodingKey {
		case friendsByJID
		case snapshotSubscriptions
		case changeEvents
		case cachedCardByPUUID
		case pinnedFriendJIDs
		case lastSyncedAt
		case lastPresenceAt
	}
	
	init(
		friendsByJID: [String: XMPPFriend] = [:],
		snapshotSubscriptions: [String: String] = [:],
		changeEvents: [FriendListChangeEvent] = [],
		cachedCardByPUUID: [String: PlayerCard.ID] = [:],
		pinnedFriendJIDs: Set<String> = [],
		lastSyncedAt: Date? = nil,
		lastPresenceAt: Date? = nil
	) {
		self.friendsByJID = friendsByJID
		self.snapshotSubscriptions = snapshotSubscriptions
		self.changeEvents = changeEvents
		self.cachedCardByPUUID = cachedCardByPUUID
		self.pinnedFriendJIDs = pinnedFriendJIDs
		self.lastSyncedAt = lastSyncedAt
		self.lastPresenceAt = lastPresenceAt
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		friendsByJID = try container.decodeIfPresent([String: XMPPFriend].self, forKey: .friendsByJID) ?? [:]
		snapshotSubscriptions = try container.decodeIfPresent([String: String].self, forKey: .snapshotSubscriptions) ?? [:]
		changeEvents = try container.decodeIfPresent([FriendListChangeEvent].self, forKey: .changeEvents) ?? []
		cachedCardByPUUID = try container.decodeIfPresent([String: PlayerCard.ID].self, forKey: .cachedCardByPUUID) ?? [:]
		pinnedFriendJIDs = try container.decodeIfPresent(Set<String>.self, forKey: .pinnedFriendJIDs) ?? []
		lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
		lastPresenceAt = try container.decodeIfPresent(Date.self, forKey: .lastPresenceAt)
	}
}

@MainActor
final class SocialOnlineCount: ObservableObject {
	@Published var count: Int = 0
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
		var pinnedFriendJIDs: Set<String> = []
		var lastSyncedAt: Date?
		var lastPresenceAt: Date?
		
		init(
			friendsByJID: [String: XMPPFriend] = [:],
			snapshotSubscriptions: [String: String] = [:],
			changeEvents: [FriendListChangeEvent] = [],
			messagesByJID: [String: [XMPPChatMessage]] = [:],
			cachedCardByPUUID: [String: PlayerCard.ID] = [:],
			pinnedFriendJIDs: Set<String> = [],
			lastSyncedAt: Date? = nil,
			lastPresenceAt: Date? = nil
		) {
			self.friendsByJID = friendsByJID
			self.snapshotSubscriptions = snapshotSubscriptions
			self.changeEvents = changeEvents
			self.messagesByJID = messagesByJID
			self.cachedCardByPUUID = cachedCardByPUUID
			self.pinnedFriendJIDs = pinnedFriendJIDs
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
			pinnedFriendJIDs = try container.decodeIfPresent(Set<String>.self, forKey: .pinnedFriendJIDs) ?? []
			lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
			lastPresenceAt = try container.decodeIfPresent(Date.self, forKey: .lastPresenceAt)
		}
	}
	
	private static let cacheFilename = "SocialCache.v2.json"
	private static let backgroundRefreshInterval: TimeInterval = 300
	private static let offlineDemoteInterval: TimeInterval = 1800
	private static let maxCachedMessagesPerConversation = 300
	static let maxFriendNoteLength = 256
	
	@Published var connectionState: ConnectionState = .disconnected
	@Published var friendsByJID: [String: XMPPFriend] = [:]
	@Published var messagesByJID: [String: [XMPPChatMessage]] = [:]
	@Published var unreadByJID: [String: Int] = [:]
	@Published var loadingHistoryJIDs: Set<String> = []
	@Published var changeEvents: [FriendListChangeEvent] = []
	@Published var pinnedFriendJIDs: Set<String> = []
	@Published var activeChatJID: String?
	@Published var myJID: String = ""
	@Published var myPresence: XMPPPresenceUpdate?
	@Published var lastSyncedAt: Date?
	@Published var isRefreshing = false
	
	let onlineCountModel = SocialOnlineCount()
	
	private let client = XMPPClient()
	private var connectedUserID: User.ID?
	private var loadedCacheUserID: User.ID?
	private var cachedAccountsByKey: [String: CachedSocialAccount]?
	private var loadAllCachesTask: Task<[String: CachedSocialAccount], Never>?
	private var activeClient: ValorantClient?
	private var connectAttempt = 0
	private var connectTask: Task<Void, Never>?
	private var autoReconnectTask: Task<Void, Never>?
	private var autoReconnectAttempt = 0
	private var isInBackground = false
	private var didBackgroundWhileConnected = false
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
	private var pendingPresenceUpdates: [XMPPPresenceUpdate] = []
	private var presenceFlushTask: Task<Void, Never>?
	private var hydrateCardsTask: Task<Void, Never>?
	private var historyTimeoutTasks: [String: Task<Void, Never>] = [:]
	
	private(set) var friends: [XMPPFriend] = []
	private(set) var friendsRevision: Int = 0
	private(set) var onlineCount: Int = 0
	private(set) var confirmedFriendCount: Int = 0
	private(set) var outgoingRequestCount: Int = 0
	private(set) var incomingRequestCount: Int = 0
	private var puuidToJID: [String: String] = [:]
	private var lowercaseJIDToCanonical: [String: String] = [:]
	
	init() {
		LocalDataProvider.onIdentitiesStored = { [weak self] identities, updateTime in
			Task { @MainActor [weak self] in
				self?.cacheIdentities(identities, asOf: updateTime)
			}
		}
		LocalDataProvider.onIdentityAndTierResolved = { [weak self] identity, tier, updateTime in
			Task { @MainActor [weak self] in
				self?.cacheIdentity(identity, competitiveTier: tier, asOf: updateTime)
			}
		}
	}
	
	private func commitFriends(_ updated: [String: XMPPFriend]) {
		let sorted = updated.values.sorted { lhs, rhs in
			if lhs.isIncomingRequest != rhs.isIncomingRequest {
				return lhs.isIncomingRequest
			}
			if lhs.status != rhs.status {
				return lhs.status < rhs.status
			}
			return XMPPFriend.compareNames(lhs, rhs)
		}
		var online = 0
		var confirmed = 0
		var outgoing = 0
		var incoming = 0
		var index: [String: String] = Dictionary(minimumCapacity: updated.count)
		var lowercaseToCanonical: [String: String] = Dictionary(minimumCapacity: updated.count * 2)
		for friend in sorted {
			if friend.isIncomingRequest {
				incoming += 1
			} else if friend.isOutgoingRequest {
				outgoing += 1
			} else {
				confirmed += 1
				if friend.status != .offline {
					online += 1
				}
			}
			lowercaseToCanonical[friend.jid.lowercased()] = friend.jid
			let bare = Self.bareJID(friend.jid)
			if bare.count != friend.jid.count {
				let bareLower = bare.lowercased()
				if lowercaseToCanonical[bareLower] == nil {
					lowercaseToCanonical[bareLower] = friend.jid
				}
			}
			if let puuidKey = friend.resolvedUserID?.description.lowercased() {
				index[puuidKey] = friend.jid
			}
			if let atIndex = friend.jid.firstIndex(of: "@") {
				let node = friend.jid[..<atIndex].lowercased()
				if index[node] == nil {
					index[node] = friend.jid
				}
			}
		}
		self.friends = sorted
		self.friendsRevision &+= 1
		self.onlineCount = online
		self.confirmedFriendCount = confirmed
		self.outgoingRequestCount = outgoing
		self.incomingRequestCount = incoming
		self.puuidToJID = index
		self.lowercaseJIDToCanonical = lowercaseToCanonical
		self.friendsByJID = updated
		if onlineCountModel.count != online {
			onlineCountModel.count = online
		}
	}
	
	func connectIfNeeded(using apiClient: ValorantClient?) async {
		guard let apiClient else {
			await disconnect()
			return
		}
		
		activeClient = apiClient
		await loadCacheIfNeeded(for: apiClient.userID)
		
		if connectedUserID == apiClient.userID {
			if connectionState == .connected {
				if isBackgroundRefreshDue {
					await refreshRosterInBackground()
				}
				return
			}
			if connectionState == .connecting, connectTask != nil {
				return
			}
		}
		
		await reconnect(using: apiClient, clearExisting: false, isAutoRetry: false)
	}
	
	func reconnect(
		using apiClient: ValorantClient,
		clearExisting: Bool = false,
		isAutoRetry: Bool = false
	) async {
		autoReconnectTask?.cancel()
		autoReconnectTask = nil
		if !isAutoRetry {
			autoReconnectAttempt = 0
		}
		connectTask?.cancel()
		connectAttempt += 1
		let attempt = connectAttempt
		activeClient = apiClient
		connectedUserID = apiClient.userID
		connectionState = .connecting
		if clearExisting {
			commitFriends([:])
		}
		
		let task = Task { @MainActor [weak self] in
			guard let self else { return }
			defer {
				if self.connectAttempt == attempt {
					self.connectTask = nil
				}
			}
			PerfMonitor.log("XMPP", "reconnect start attempt=\(attempt) user=\(apiClient.userID)")
			await self.client.disconnect()
			guard attempt == self.connectAttempt, !Task.isCancelled else { return }
			await self.loadCacheIfNeeded(for: apiClient.userID)
			guard attempt == self.connectAttempt, !Task.isCancelled else { return }
			do {
				try await self.client.connect(client: apiClient) { [weak self] event in
					await self?.handle(event, attempt: attempt)
				}
				guard attempt == self.connectAttempt else { return }
				self.autoReconnectAttempt = 0
				PerfMonitor.log("XMPP", "reconnect finished attempt=\(attempt)")
			} catch {
				guard attempt == self.connectAttempt else { return }
				if Self.isCancellation(error) {
					PerfMonitor.log("XMPP", "reconnect cancelled attempt=\(attempt)")
					await self.client.disconnect()
					guard attempt == self.connectAttempt else { return }
					if self.connectionState == .connecting {
						self.connectionState = .disconnected
					}
					return
				}
				PerfMonitor.log("XMPP", "reconnect failed attempt=\(attempt) error=\(error.localizedDescription)")
				await self.client.disconnect()
				guard attempt == self.connectAttempt else { return }
				
				if self.isInBackground {
					self.connectionState = .disconnected
					return
				}
				
				if case XMPPError.authenticationFailed = error, !isAutoRetry {
					self.scheduleAutoReconnect(using: apiClient, immediate: true, delayOverride: 0.25)
					return
				}
				
				if isAutoRetry, !Self.isUnrecoverableAuthError(error), self.autoReconnectAttempt < 3 {
					let delay = Self.retryDelaySeconds(for: error, attemptIndex: self.autoReconnectAttempt)
					let currentRetry = self.autoReconnectAttempt
					self.autoReconnectAttempt += 1
					if currentRetry > 0 {
						self.connectionState = .failed(error.localizedDescription)
					}
					self.scheduleAutoReconnect(using: apiClient, immediate: false, delayOverride: delay)
					return
				}
				
				self.connectionState = .failed(error.localizedDescription)
			}
		}
		connectTask = task
		await task.value
	}
	
	private func scheduleAutoReconnect(
		using apiClient: ValorantClient,
		immediate: Bool,
		delayOverride: TimeInterval
	) {
		autoReconnectTask?.cancel()
		let delay = immediate ? 0.25 : delayOverride
		let expectedAttempt = connectAttempt
		autoReconnectTask = Task { @MainActor [weak self] in
			guard let self else { return }
			if delay > 0 {
				try? await Task.sleep(for: .seconds(delay))
			}
			guard !Task.isCancelled, !self.isInBackground, self.connectAttempt == expectedAttempt else { return }
			await self.reconnect(using: apiClient, clearExisting: false, isAutoRetry: true)
		}
	}
	
	private static func isCancellation(_ error: Error) -> Bool {
		error is CancellationError || (error as? URLError)?.code == .cancelled
	}
	
	private static func isUnrecoverableAuthError(_ error: Error) -> Bool {
		if let apiError = error as? APIError {
			return apiError.recommendsReauthentication
		}
		if case XMPPError.authenticationFailed = error {
			return true
		}
		return false
	}
	
	private static func retryDelaySeconds(for error: Error, attemptIndex: Int) -> TimeInterval {
		if case APIError.rateLimited(let retryAfter) = error {
			return TimeInterval(max(retryAfter ?? 2, 2))
		}
		switch attemptIndex {
		case 0: return 2
		case 1: return 5
		default: return 12
		}
	}
	
	func handleDidEnterBackground() {
		isInBackground = true
		didBackgroundWhileConnected = (connectionState == .connected)
		autoReconnectTask?.cancel()
		autoReconnectTask = nil
	}
	
	func handleSceneActivation(using apiClient: ValorantClient?) async {
		isInBackground = false
		guard let apiClient else { return }
		activeClient = apiClient
		await loadCacheIfNeeded(for: apiClient.userID)
		
		switch connectionState {
		case .disconnected, .failed:
			await reconnect(using: apiClient, clearExisting: false, isAutoRetry: true)
		case .connecting:
			if connectTask == nil {
				await reconnect(using: apiClient, clearExisting: false, isAutoRetry: true)
			}
		case .connected:
			let alive = await client.ping()
			if !alive {
				await reconnect(using: apiClient, clearExisting: false, isAutoRetry: true)
			} else if didBackgroundWhileConnected || isBackgroundRefreshDue {
				didBackgroundWhileConnected = false
				await refreshRosterInBackground()
			}
		}
	}
	
	func refreshNow(using apiClient: ValorantClient) async {
		activeClient = apiClient
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
				await reconnect(using: apiClient, clearExisting: false, isAutoRetry: false)
			}
		} else {
			await reconnect(using: apiClient, clearExisting: false, isAutoRetry: false)
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
		connectAttempt += 1
		connectTask?.cancel()
		connectTask = nil
		autoReconnectTask?.cancel()
		autoReconnectTask = nil
		autoReconnectAttempt = 0
		didBackgroundWhileConnected = false
		activeClient = nil
		presenceFlushTask?.cancel()
		presenceFlushTask = nil
		pendingPresenceUpdates.removeAll()
		hydrateCardsTask?.cancel()
		hydrateCardsTask = nil
		for task in historyTimeoutTasks.values {
			task.cancel()
		}
		historyTimeoutTasks.removeAll()
		refreshResetTask?.cancel()
		refreshResetTask = nil
		deferredSaveTask?.cancel()
		deferredSaveTask = nil
		await client.disconnect()
		connectedUserID = nil
		loadedCacheUserID = nil
		connectionState = .disconnected
		commitFriends([:])
		snapshotSubscriptions = [:]
		locallyRemovedJIDs = []
		resourcesByJID = [:]
		ownResources = [:]
		cachedCardByPUUID = [:]
		cachedCardDateByPUUID = [:]
		pinnedFriendJIDs = []
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
		historyTimeoutTasks[target]?.cancel()
		historyTimeoutTasks[target] = Task { [weak self] in
			try? await Task.sleep(for: .seconds(6))
			guard !Task.isCancelled else { return }
			self?.loadingHistoryJIDs.remove(target)
			self?.historyTimeoutTasks.removeValue(forKey: target)
		}
		do {
			try await client.requestArchive(with: target)
		} catch {
			historyTimeoutTasks[target]?.cancel()
			historyTimeoutTasks.removeValue(forKey: target)
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
		var updatedFriends: [String: XMPPFriend]?
		for identity in identities {
			let key = identity.id.description.lowercased()
			guard let jid = puuidToJID[key],
			      var friend = updatedFriends?[jid] ?? friendsByJID[jid] else { continue }
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
				if updatedFriends == nil { updatedFriends = friendsByJID }
				updatedFriends?[jid] = friend
				didUpdate = true
			}
		}
		if let updatedFriends {
			commitFriends(updatedFriends)
		}
		if didUpdate {
			scheduleCacheSave()
		}
	}
	
	private func scheduleHydrateFriendCards() {
		hydrateCardsTask?.cancel()
		hydrateCardsTask = Task { @MainActor [weak self] in
			await self?.hydrateFriendCardsFromLocalData()
			self?.hydrateCardsTask = nil
		}
	}

	private func hydrateFriendCardsFromLocalData() async {
		let targetIDs: [User.ID] = friendsByJID.values.compactMap { friend in
			guard friend.playerCardID == nil else { return nil }
			return friend.resolvedUserID
		}
		guard !targetIDs.isEmpty, !Task.isCancelled else { return }
		let identities = await LocalDataProvider.shared.playerIdentityManager.cachedObjects(for: targetIDs)
		guard !Task.isCancelled else { return }
		if !identities.isEmpty {
			cacheIdentities(identities, asOf: .distantPast)
		}
	}
	
	func addFriend(gameName: String, tagLine: String) async throws {
		try await client.addFriend(gameName: gameName, tagLine: tagLine)
	}
	
	func acceptFriend(_ friend: XMPPFriend) async throws {
		let targetJID = canonicalJID(for: friend.jid)
		let current = friendsByJID[targetJID] ?? friend
		try await client.acceptFriend(
			jid: current.jid,
			puuid: current.resolvedUserID,
			gameName: current.gameName,
			tagLine: current.tagLine
		)
		if friendsByJID[targetJID]?.subscription != "both" {
			var updated = friendsByJID
			if updated[targetJID] != nil {
				updated[targetJID]?.subscription = "both"
			} else {
				var copy = current
				copy.subscription = "both"
				updated[targetJID] = copy
			}
			commitFriends(updated)
		}
		snapshotSubscriptions[targetJID] = "both"
		saveCacheNow()
	}
	
	func removeFriend(_ friend: XMPPFriend) async throws {
		let targetJID = canonicalJID(for: friend.jid)
		let current = friendsByJID[targetJID] ?? friend
		let trackedKeys = Set([targetJID, friend.jid, current.jid])
		locallyRemovedJIDs.formUnion(trackedKeys)
		do {
			try await client.removeFriend(jid: current.jid)
		} catch {
			locallyRemovedJIDs.subtract(trackedKeys)
			throw error
		}
		var updated = friendsByJID
		let removedCanonical = updated.removeValue(forKey: targetJID)
		let removedRaw = (friend.jid != targetJID) ? updated.removeValue(forKey: friend.jid) : nil
		if removedCanonical != nil || removedRaw != nil {
			commitFriends(updated)
		}
		for key in trackedKeys {
			resourcesByJID.removeValue(forKey: key)
			snapshotSubscriptions.removeValue(forKey: key)
			pinnedFriendJIDs.remove(Self.normalizedPinnedJID(key))
		}
		saveCacheNow()
	}
	
	func updateFriendNote(_ friend: XMPPFriend, note: String?) async throws {
		let targetJID = canonicalJID(for: friend.jid)
		let current = friendsByJID[targetJID] ?? friend
		let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let normalized: String? = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxFriendNoteLength))
		
		try await client.setFriendNote(
			jid: current.jid,
			puuid: current.resolvedUserID,
			gameName: current.gameName,
			tagLine: current.tagLine,
			note: normalized,
			subscription: current.subscription,
			groupName: current.groupName,
			groupPriority: current.groupPriority
		)
		
		var updated = friendsByJID
		if updated[targetJID] != nil {
			updated[targetJID]?.note = normalized
			commitFriends(updated)
		} else {
			var copy = current
			copy.note = normalized
			updated[targetJID] = copy
			commitFriends(updated)
		}
		saveCacheNow()
	}
	
	func isPinned(_ friend: XMPPFriend) -> Bool {
		isPinned(jid: friend.jid)
	}
	
	func isPinned(jid: String) -> Bool {
		let canonical = canonicalJID(for: jid)
		return pinnedFriendJIDs.contains(Self.normalizedPinnedJID(canonical))
			|| pinnedFriendJIDs.contains(Self.normalizedPinnedJID(jid))
	}
	
	func togglePinned(jid: String) {
		let canonical = canonicalJID(for: jid)
		let normalizedCanonical = Self.normalizedPinnedJID(canonical)
		let normalizedRaw = Self.normalizedPinnedJID(jid)
		if pinnedFriendJIDs.contains(normalizedCanonical) || pinnedFriendJIDs.contains(normalizedRaw) {
			pinnedFriendJIDs.remove(normalizedCanonical)
			pinnedFriendJIDs.remove(normalizedRaw)
		} else {
			pinnedFriendJIDs.insert(normalizedCanonical)
		}
		saveCacheNow()
	}
	
	func markRead(jid: String) {
		let target = canonicalJID(for: jid)
		unreadByJID[target] = 0
		if target != jid { unreadByJID[jid] = 0 }
	}
	
	private static func bareJID(_ rawJID: String) -> String {
		let prefix = rawJID.prefix { $0 != "/" }
		return prefix.count == rawJID.count ? rawJID : String(prefix)
	}
	
	private static func normalizedPinnedJID(_ rawJID: String) -> String {
		bareJID(rawJID).lowercased()
	}
	
	private func canonicalJID(for rawJID: String) -> String {
		let bare = Self.bareJID(rawJID)
		if friendsByJID[bare] != nil {
			return bare
		}
		if let exact = lowercaseJIDToCanonical[bare.lowercased()] {
			return exact
		}
		if let atIndex = bare.firstIndex(of: "@") {
			let node = bare[..<atIndex].lowercased()
			if let byPUUID = puuidToJID[node] {
				return byPUUID
			}
		}
		return bare
	}
	
	private func handle(_ event: XMPPEvent, attempt: Int) {
		guard attempt == connectAttempt else { return }
		
		switch event {
		case .connected(let jid):
			PerfMonitor.log("XMPP", "connected jid=\(jid)")
			self.autoReconnectAttempt = 0
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
			PerfMonitor.log("XMPP", "disconnected error=\(error?.localizedDescription ?? "none")")
			self.isRefreshing = false
			self.loadingHistoryJIDs.removeAll()
			if self.isInBackground {
				self.connectionState = .disconnected
			} else if let apiClient = self.activeClient, let error, !Self.isUnrecoverableAuthError(error) {
				self.connectionState = .connecting
				self.autoReconnectAttempt = 0
				self.scheduleAutoReconnect(using: apiClient, immediate: false, delayOverride: 1.5)
			} else if let error {
				self.connectionState = .failed(error.localizedDescription)
			} else {
				self.connectionState = .disconnected
			}
			
		case let .rosterReceived(list, isFullSnapshot, isServerPush):
			flushPendingPresenceUpdates()
			let previousFriends = friendsByJID
			var updated = friendsByJID
			
			for var item in list {
				if item.subscription == "remove" {
					updated.removeValue(forKey: item.jid)
					resourcesByJID.removeValue(forKey: item.jid)
				} else if var existing = updated[item.jid] {
					if !item.gameName.isEmpty { existing.gameName = item.gameName }
					if !item.tagLine.isEmpty { existing.tagLine = item.tagLine }
					existing.subscription = item.subscription
					existing.puuid = existing.puuid ?? item.puuid
					if existing.playerCardID == nil,
					   let key = existing.puuid?.description.lowercased() ?? item.jid.split(separator: "@").first?.lowercased(),
					   let cachedCard = cachedCardByPUUID[key] {
						existing.playerCardID = cachedCard
					}
					if isFullSnapshot || isServerPush || item.note != nil {
						existing.note = item.note
					}
					if isFullSnapshot || isServerPush || item.groupName != nil {
						existing.groupName = item.groupName
						existing.groupPriority = item.groupPriority
					}
					existing.lastOnline = Self.newerDate(existing.lastOnline, item.lastOnline)
					updated[item.jid] = existing
				} else {
					if item.playerCardID == nil,
					   let key = item.puuid?.description.lowercased() ?? item.jid.split(separator: "@").first?.lowercased(),
					   let cachedCard = cachedCardByPUUID[key] {
						item.playerCardID = cachedCard
					}
					updated[item.jid] = item
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
						newSubs: newSubs,
						newFriends: updated
					)
				}
				
				for jid in Array(updated.keys) where !activeJIDs.contains(jid) {
					updated.removeValue(forKey: jid)
					resourcesByJID.removeValue(forKey: jid)
				}
				
				if updated != previousFriends || friends.isEmpty {
					commitFriends(updated)
				}
				for cachedKey in cachedCardByPUUID.keys where puuidToJID[cachedKey] == nil {
					cachedCardByPUUID.removeValue(forKey: cachedKey)
					cachedCardDateByPUUID.removeValue(forKey: cachedKey)
				}
				snapshotSubscriptions = newSubs
				locallyRemovedJIDs.removeAll()
				lastSyncedAt = Date()
				refreshResetTask?.cancel()
				isRefreshing = false
				saveCacheNow()
				scheduleHydrateFriendCards()
			} else {
				if updated != previousFriends || friends.isEmpty {
					commitFriends(updated)
				}
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
			
			pendingPresenceUpdates.append(update)
			if presenceFlushTask == nil {
				presenceFlushTask = Task { @MainActor [weak self] in
					try? await Task.sleep(for: .milliseconds(120))
					guard !Task.isCancelled else { return }
					self?.flushPendingPresenceUpdates()
				}
			}
			
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
			historyTimeoutTasks[peer]?.cancel()
			historyTimeoutTasks.removeValue(forKey: peer)
			historyTimeoutTasks[rawPeerJID]?.cancel()
			historyTimeoutTasks.removeValue(forKey: rawPeerJID)
			loadingHistoryJIDs.remove(peer)
			loadingHistoryJIDs.remove(rawPeerJID)
			if !history.isEmpty {
				mergeArchive(history, for: peer)
				saveCacheNow()
			}
		}
	}
	
	private func flushPendingPresenceUpdates() {
		presenceFlushTask?.cancel()
		presenceFlushTask = nil
		guard !pendingPresenceUpdates.isEmpty else { return }
		
		let batch = pendingPresenceUpdates
		pendingPresenceUpdates.removeAll(keepingCapacity: true)
		
		var updated = friendsByJID
		var didChange = false
		let now = Date()
		
		for update in batch {
			if applyPresenceUpdate(update, into: &updated, now: now) {
				didChange = true
			}
		}
		
		lastPresenceAt = now
		if didChange {
			commitFriends(updated)
			scheduleCacheSave()
		}
	}
	
	private func applyPresenceUpdate(
		_ update: XMPPPresenceUpdate,
		into friends: inout [String: XMPPFriend],
		now: Date
	) -> Bool {
		let original = friends[update.jid]
		var friend = original ?? XMPPFriend(
			jid: update.jid,
			puuid: update.jid.components(separatedBy: "@").first.flatMap { User.ID($0.lowercased()) },
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
				cachedCardDateByPUUID[puuidKey] = now
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
				friend.lastOnline = update.lastOnline ?? now
			}
		}
		
		guard friend != original else { return false }
		friends[update.jid] = friend
		return true
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
		newSubs: [String: String],
		newFriends: [String: XMPPFriend]
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
				let current = newFriends[jid]
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
			let current = newFriends[jid]
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
	
	private func ensureAllCachesLoaded() async -> [String: CachedSocialAccount] {
		if let cachedAccountsByKey {
			return cachedAccountsByKey
		}
		if let loadAllCachesTask {
			return await loadAllCachesTask.value
		}
		let task = Task {
			await LocalJSONStore.loadAsync([String: CachedSocialAccount].self, from: Self.cacheFilename) ?? [:]
		}
		loadAllCachesTask = task
		let loaded = await task.value
		if cachedAccountsByKey == nil {
			cachedAccountsByKey = loaded
		}
		loadAllCachesTask = nil
		return cachedAccountsByKey ?? loaded
	}
	
	private func loadCacheIfNeeded(for userID: User.ID) async {
		guard loadedCacheUserID != userID else { return }
		loadedCacheUserID = userID
		presenceFlushTask?.cancel()
		presenceFlushTask = nil
		pendingPresenceUpdates.removeAll()
		hydrateCardsTask?.cancel()
		hydrateCardsTask = nil
		for task in historyTimeoutTasks.values {
			task.cancel()
		}
		historyTimeoutTasks.removeAll()
		myPresence = nil
		locallyRemovedJIDs = []
		resourcesByJID = [:]
		ownResources = [:]
		
		let allCaches: [String: CachedSocialAccount]
		if let cachedAccountsByKey {
			allCaches = cachedAccountsByKey
		} else {
			allCaches = await ensureAllCachesLoaded()
			guard loadedCacheUserID == userID, lastSyncedAt == nil else { return }
		}
		
		guard let cached = allCaches[cacheKey(for: userID)] else {
			commitFriends([:])
			snapshotSubscriptions = [:]
			changeEvents = []
			messagesByJID = [:]
			cachedCardByPUUID = [:]
			pinnedFriendJIDs = []
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
		
		commitFriends(restoredFriends)
		snapshotSubscriptions = cached.snapshotSubscriptions
		changeEvents = cached.changeEvents
		messagesByJID = cached.messagesByJID
		pinnedFriendJIDs = Set(cached.pinnedFriendJIDs.map(Self.normalizedPinnedJID))
		lastSyncedAt = cached.lastSyncedAt
		lastPresenceAt = cached.lastPresenceAt
		scheduleHydrateFriendCards()
	}
	
	private func scheduleCacheSave() {
		deferredSaveTask?.cancel()
		deferredSaveTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(2))
			guard !Task.isCancelled else { return }
			self?.saveCacheNow()
		}
	}
	
	private static func cappedMessages(in messagesByJID: [String: [XMPPChatMessage]]) -> [String: [XMPPChatMessage]] {
		guard messagesByJID.values.contains(where: { $0.count > maxCachedMessagesPerConversation }) else {
			return messagesByJID
		}
		return messagesByJID.mapValues { list in
			list.count > maxCachedMessagesPerConversation ? Array(list.suffix(maxCachedMessagesPerConversation)) : list
		}
	}
	
	private func saveCacheNow() {
		guard let userID = connectedUserID ?? loadedCacheUserID else { return }
		let key = cacheKey(for: userID)
		let snapshot = currentAccountSnapshot()
		if var allCaches = cachedAccountsByKey {
			allCaches[key] = snapshot
			cachedAccountsByKey = allCaches
			LocalJSONStore.save(allCaches, to: Self.cacheFilename)
		} else {
			Task { @MainActor [weak self] in
				guard let self else { return }
				var allCaches = await self.ensureAllCachesLoaded()
				allCaches[key] = snapshot
				self.cachedAccountsByKey = allCaches
				LocalJSONStore.save(allCaches, to: Self.cacheFilename)
			}
		}
	}
	
	private struct MessageSignature: Hashable {
		let isOutgoing: Bool
		let body: String
	}
	
	@discardableResult
	private static func mergeMessages(
		_ incoming: [XMPPChatMessage],
		into existing: inout [XMPPChatMessage],
		for peerJID: String
	) -> Int {
		guard !incoming.isEmpty else { return 0 }
		var seenIDs = Set<String>(minimumCapacity: existing.count + incoming.count)
		var timestampsBySig: [MessageSignature: [Date]] = Dictionary(minimumCapacity: existing.count)
		for message in existing {
			seenIDs.insert(message.id)
			let sig = MessageSignature(isOutgoing: message.isOutgoing, body: message.body)
			timestampsBySig[sig, default: []].append(message.timestamp)
		}
		var addedCount = 0
		for item in incoming {
			guard seenIDs.insert(item.id).inserted else { continue }
			let sig = MessageSignature(isOutgoing: item.isOutgoing, body: item.body)
			if timestampsBySig[sig]?.contains(where: { abs($0.timeIntervalSince(item.timestamp)) < 15 }) == true {
				continue
			}
			var normalized = item
			normalized.peerJID = peerJID
			existing.append(normalized)
			timestampsBySig[sig, default: []].append(item.timestamp)
			addedCount += 1
		}
		guard addedCount > 0 else { return 0 }
		existing.sort { $0.timestamp < $1.timestamp }
		if existing.count > maxCachedMessagesPerConversation {
			existing = Array(existing.suffix(maxCachedMessagesPerConversation))
		}
		return addedCount
	}
	
	private func appendMessage(_ msg: XMPPChatMessage, for jid: String) {
		mergeArchive([msg], for: jid)
	}
	
	private func mergeArchive(_ history: [XMPPChatMessage], for peerJID: String) {
		var merged = messagesByJID[peerJID] ?? []
		guard Self.mergeMessages(history, into: &merged, for: peerJID) > 0 else { return }
		messagesByJID[peerJID] = merged
	}
	
	// MARK: - Backup Export / Import
	
	private func currentAccountSnapshot() -> CachedSocialAccount {
		CachedSocialAccount(
			friendsByJID: friendsByJID,
			snapshotSubscriptions: snapshotSubscriptions,
			changeEvents: changeEvents,
			messagesByJID: Self.cappedMessages(in: messagesByJID),
			cachedCardByPUUID: cachedCardByPUUID,
			pinnedFriendJIDs: Set(pinnedFriendJIDs.map(Self.normalizedPinnedJID)),
			lastSyncedAt: lastSyncedAt,
			lastPresenceAt: lastPresenceAt
		)
	}
	
	private func flushCurrentAccountCacheIfNeeded() async {
		deferredSaveTask?.cancel()
		deferredSaveTask = nil
		guard let userID = connectedUserID ?? loadedCacheUserID else { return }
		let key = cacheKey(for: userID)
		let snapshot = currentAccountSnapshot()
		var allCaches = await ensureAllCachesLoaded()
		allCaches[key] = snapshot
		cachedAccountsByKey = allCaches
		await LocalJSONStore.saveAndWait(allCaches, to: Self.cacheFilename)
	}
	
	func exportSocialData(
		for playerIDs: Set<User.ID>?
	) async -> (friends: [String: SocialFriendsBackup], messages: [String: [String: [XMPPChatMessage]]]) {
		var allCaches = await ensureAllCachesLoaded()
		if let userID = connectedUserID ?? loadedCacheUserID {
			allCaches[cacheKey(for: userID)] = currentAccountSnapshot()
		}
		let allowedKeys = playerIDs.map { Set($0.map { $0.description.lowercased() }) }
		
		var friendsBackup: [String: SocialFriendsBackup] = [:]
		var messagesBackup: [String: [String: [XMPPChatMessage]]] = [:]
		
		for (rawKey, account) in allCaches {
			let key = rawKey.lowercased()
			if let allowedKeys, !allowedKeys.contains(key) { continue }
			
			if !account.friendsByJID.isEmpty
				|| !account.changeEvents.isEmpty
				|| !account.snapshotSubscriptions.isEmpty
				|| !account.cachedCardByPUUID.isEmpty
				|| !account.pinnedFriendJIDs.isEmpty {
				friendsBackup[key] = SocialFriendsBackup(
					friendsByJID: account.friendsByJID,
					snapshotSubscriptions: account.snapshotSubscriptions,
					changeEvents: account.changeEvents,
					cachedCardByPUUID: account.cachedCardByPUUID,
					pinnedFriendJIDs: account.pinnedFriendJIDs,
					lastSyncedAt: account.lastSyncedAt,
					lastPresenceAt: account.lastPresenceAt
				)
			}
			
			let nonEmptyConversations = account.messagesByJID.filter { !$0.value.isEmpty }
			if !nonEmptyConversations.isEmpty {
				messagesBackup[key] = nonEmptyConversations
			}
		}
		
		return (friendsBackup, messagesBackup)
	}
	
	@discardableResult
	func importSocialFriends(_ incoming: [String: SocialFriendsBackup], replaceAll: Bool) async -> Int {
		await flushCurrentAccountCacheIfNeeded()
		var allCaches = await ensureAllCachesLoaded()
		
		if replaceAll {
			for key in Array(allCaches.keys) {
				var account = allCaches[key]!
				account.friendsByJID = [:]
				account.snapshotSubscriptions = [:]
				account.changeEvents = []
				account.cachedCardByPUUID = [:]
				account.pinnedFriendJIDs = []
				account.lastSyncedAt = nil
				account.lastPresenceAt = nil
				if account.messagesByJID.isEmpty {
					allCaches.removeValue(forKey: key)
				} else {
					allCaches[key] = account
				}
			}
		}
		
		var changedAccounts = 0
		for (rawKey, backup) in incoming {
			let key = rawKey.lowercased()
			var account = allCaches[key] ?? CachedSocialAccount()
			var accountChanged = false
			
			for (jid, friend) in backup.friendsByJID {
				if let existing = account.friendsByJID[jid] {
					if existing.gameName.isEmpty && !friend.gameName.isEmpty
						|| (existing.lastOnline ?? .distantPast) < (friend.lastOnline ?? .distantPast)
						|| (existing.playerCardID == nil && friend.playerCardID != nil) {
						account.friendsByJID[jid] = friend
						accountChanged = true
					}
				} else {
					account.friendsByJID[jid] = friend
					accountChanged = true
				}
			}
			
			for (jid, sub) in backup.snapshotSubscriptions where account.snapshotSubscriptions[jid] == nil {
				account.snapshotSubscriptions[jid] = sub
				accountChanged = true
			}
			
			let existingEventIDs = Set(account.changeEvents.map(\.id))
			let newEvents = backup.changeEvents.filter { !existingEventIDs.contains($0.id) }
			if !newEvents.isEmpty {
				account.changeEvents = (account.changeEvents + newEvents)
					.sorted { $0.timestamp > $1.timestamp }
				if account.changeEvents.count > 200 {
					account.changeEvents = Array(account.changeEvents.prefix(200))
				}
				accountChanged = true
			}
			
			for (puuid, cardID) in backup.cachedCardByPUUID where account.cachedCardByPUUID[puuid] == nil {
				account.cachedCardByPUUID[puuid] = cardID
				accountChanged = true
			}
			
			let normalizedExistingPinned = Set(account.pinnedFriendJIDs.map(Self.normalizedPinnedJID))
			if normalizedExistingPinned != account.pinnedFriendJIDs {
				account.pinnedFriendJIDs = normalizedExistingPinned
			}
			let normalizedIncomingPinned = Set(backup.pinnedFriendJIDs.map(Self.normalizedPinnedJID))
			let newPinned = normalizedIncomingPinned.subtracting(account.pinnedFriendJIDs)
			if !newPinned.isEmpty {
				account.pinnedFriendJIDs.formUnion(newPinned)
				accountChanged = true
			}
			
			if let synced = backup.lastSyncedAt, (account.lastSyncedAt ?? .distantPast) < synced {
				account.lastSyncedAt = synced
			}
			if let presence = backup.lastPresenceAt, (account.lastPresenceAt ?? .distantPast) < presence {
				account.lastPresenceAt = presence
			}
			
			if replaceAll || accountChanged {
				allCaches[key] = account
				changedAccounts += 1
			}
		}
		
		cachedAccountsByKey = allCaches
		await LocalJSONStore.saveAndWait(allCaches, to: Self.cacheFilename)
		
		if let activeUser = connectedUserID ?? loadedCacheUserID {
			let activeKey = cacheKey(for: activeUser)
			let updated = allCaches[activeKey]
			var restored = updated?.friendsByJID ?? [:]
			for jid in restored.keys where connectionState != .connected {
				restored[jid]?.status = .offline
			}
			commitFriends(restored)
			snapshotSubscriptions = updated?.snapshotSubscriptions ?? [:]
			changeEvents = updated?.changeEvents ?? []
			cachedCardByPUUID = updated?.cachedCardByPUUID ?? [:]
			pinnedFriendJIDs = Set((updated?.pinnedFriendJIDs ?? []).map(Self.normalizedPinnedJID))
			lastSyncedAt = updated?.lastSyncedAt
			lastPresenceAt = updated?.lastPresenceAt
		}
		
		return changedAccounts
	}
	
	@discardableResult
	func importSocialMessages(
		_ incoming: [String: [String: [XMPPChatMessage]]],
		replaceAll: Bool
	) async -> Int {
		await flushCurrentAccountCacheIfNeeded()
		var allCaches = await ensureAllCachesLoaded()
		
		if replaceAll {
			for key in Array(allCaches.keys) {
				var account = allCaches[key]!
				account.messagesByJID = [:]
				if account.friendsByJID.isEmpty && account.changeEvents.isEmpty {
					allCaches.removeValue(forKey: key)
				} else {
					allCaches[key] = account
				}
			}
		}
		
		var importedMessageCount = 0
		for (rawKey, conversations) in incoming {
			let key = rawKey.lowercased()
			var account = allCaches[key] ?? CachedSocialAccount()
			var accountChanged = false
			
			for (peerJID, messages) in conversations {
				var merged = account.messagesByJID[peerJID] ?? []
				let addedCount = Self.mergeMessages(messages, into: &merged, for: peerJID)
				if addedCount > 0 {
					account.messagesByJID[peerJID] = merged
					importedMessageCount += addedCount
					accountChanged = true
				}
			}
			
			if replaceAll || accountChanged {
				allCaches[key] = account
			}
		}
		
		cachedAccountsByKey = allCaches
		await LocalJSONStore.saveAndWait(allCaches, to: Self.cacheFilename)
		
		if let activeUser = connectedUserID ?? loadedCacheUserID {
			let activeKey = cacheKey(for: activeUser)
			messagesByJID = allCaches[activeKey]?.messagesByJID ?? [:]
		}
		
		return importedMessageCount
	}
}
