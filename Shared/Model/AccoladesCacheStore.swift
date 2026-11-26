import Foundation
import Combine
import ValorantAPI

/// Persistent cache of per-match accolades so Career and Accolades views render immediately
/// without waiting for raw match details to enter the in-memory LRU cache.
@MainActor
final class AccoladesCacheStore: ObservableObject {
	static let shared = AccoladesCacheStore()
	
	private static let filename = "AccoladesCache.v1.json"
	private static let maxEntriesPerUser = 200
	private static let chunkSize = 15
	private static let saveDebounceNanoseconds: UInt64 = 500_000_000
	
	private struct PersistedUserCache: Codable {
		var userID: User.ID
		var entries: [CachedMatchAccolades]
	}
	
	private struct ReportCacheKey: Hashable {
		var userID: User.ID
		var actID: Act.ID?
		var hasSeasons: Bool
		var revision: Int
	}
	
	@Published private(set) var revision: Int = 0
	
	private var byUser: [User.ID: [Match.ID: CachedMatchAccolades]] = [:]
	private var trackedUsers: Set<User.ID> = []
	private var reportCache: [ReportCacheKey: AccoladesReport] = [:]
	private var pendingSaveTask: Task<Void, Never>?
	private var inFlightMatchIDsByUser: [User.ID: Set<Match.ID>] = [:]
	private var hasLoadedFromDisk = false
	private var initialLoadTask: Task<Void, Never>?
	
	private init() {
		initialLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let persisted = await LocalJSONStore.loadAsync([PersistedUserCache].self, from: Self.filename) ?? []
			self.mergeDiskBuckets(persisted)
		}
	}
	
	func waitUntilLoaded() async {
		if let initialLoadTask, !hasLoadedFromDisk {
			await initialLoadTask.value
		}
	}
	
	private func mergeDiskBuckets(_ persisted: [PersistedUserCache]) {
		hasLoadedFromDisk = true
		guard !persisted.isEmpty else { return }
		var didMerge = false
		for bucket in persisted {
			trackedUsers.insert(bucket.userID)
			var map = Dictionary(
				bucket.entries.map { ($0.matchID, $0) },
				uniquingKeysWith: { _, latest in latest }
			)
			if let existing = byUser[bucket.userID] {
				for (id, entry) in existing {
					map[id] = entry
				}
			}
			Self.trim(&map, limit: Self.maxEntriesPerUser)
			if byUser[bucket.userID] != map {
				byUser[bucket.userID] = map
				didMerge = true
			}
		}
		if didMerge {
			bumpRevision()
		}
	}
	
	func report(
		for userID: User.ID,
		act: Act?,
		seasons: SeasonCollection.Accessor? = nil
	) -> AccoladesReport {
		let key = ReportCacheKey(
			userID: userID,
			actID: act?.id,
			hasSeasons: seasons != nil,
			revision: revision
		)
		if let cached = reportCache[key] {
			return cached
		}
		let entries = Array((byUser[userID] ?? [:]).values)
		let built = AccoladesCalculator.buildReport(from: entries, act: act, seasons: seasons)
		reportCache[key] = built
		return built
	}
	
	func cachedMatchCount(for userID: User.ID) -> Int {
		byUser[userID]?.count ?? 0
	}
	
	func cachedEntriesSnapshot(for userID: User.ID) -> [CachedMatchAccolades] {
		Array((byUser[userID] ?? [:]).values)
	}
	
	func ingestLoadedMatches(for userID: User.ID, matchIDs: [Match.ID]) {
		trackedUsers.insert(userID)
		let manager = LocalDataProvider.shared.matchDetailsManager
		let existing = byUser[userID] ?? [:]
		let pending = inFlightMatchIDsByUser[userID] ?? []
		var toExtract: [MatchDetails] = []
		var claimedIDs: [Match.ID] = []
		
		for id in matchIDs where existing[id] == nil && !pending.contains(id) {
			guard let details = manager.loadedObject(for: id) else { continue }
			toExtract.append(details)
			claimedIDs.append(id)
		}
		
		guard !toExtract.isEmpty else { return }
		inFlightMatchIDsByUser[userID, default: []].formUnion(claimedIDs)
		
		Task { @MainActor [weak self] in
			let extracted = await Task.detached(priority: .utility) {
				toExtract.map { AccoladesCalculator.extractCachedEntry(userID: userID, match: $0) }
			}.value
			guard let self else { return }
			self.inFlightMatchIDsByUser[userID]?.subtract(claimedIDs)
			self.insert(extracted, for: userID)
		}
	}
	
	/// Backfills cached accolades from disk-cached `MatchDetails` in small chunks without
	/// inserting them into or evicting from `matchDetailsManager`'s in-memory LRU cache.
	func syncMissingMatches(for userID: User.ID, matchIDs: [Match.ID]) async {
		trackedUsers.insert(userID)
		await waitUntilLoaded()
		
		// Extract any already-in-memory matches off-main first.
		let manager = LocalDataProvider.shared.matchDetailsManager
		let existingBefore = byUser[userID] ?? [:]
		let pendingBefore = inFlightMatchIDsByUser[userID] ?? []
		var inMemoryToExtract: [MatchDetails] = []
		var claimedMemoryIDs: [Match.ID] = []
		for id in matchIDs.prefix(Self.maxEntriesPerUser) where existingBefore[id] == nil && !pendingBefore.contains(id) {
			if let loaded = manager.loadedObject(for: id) {
				inMemoryToExtract.append(loaded)
				claimedMemoryIDs.append(id)
			}
		}
		if !inMemoryToExtract.isEmpty {
			inFlightMatchIDsByUser[userID, default: []].formUnion(claimedMemoryIDs)
			let extracted = await Task.detached(priority: .userInitiated) {
				inMemoryToExtract.map { AccoladesCalculator.extractCachedEntry(userID: userID, match: $0) }
			}.value
			inFlightMatchIDsByUser[userID]?.subtract(claimedMemoryIDs)
			insert(extracted, for: userID)
		}
		
		var seen: Set<Match.ID> = []
		let existing = byUser[userID] ?? [:]
		let inFlight = inFlightMatchIDsByUser[userID] ?? []
		let targetIDs = matchIDs
			.prefix(Self.maxEntriesPerUser)
			.filter { id in seen.insert(id).inserted && existing[id] == nil && !inFlight.contains(id) }
		
		guard !targetIDs.isEmpty else { return }
		inFlightMatchIDsByUser[userID, default: []].formUnion(targetIDs)
		defer { inFlightMatchIDsByUser[userID]?.subtract(targetIDs) }
		
		for start in stride(from: 0, to: targetIDs.count, by: Self.chunkSize) {
			guard !Task.isCancelled else { return }
			let end = min(start + Self.chunkSize, targetIDs.count)
			let currentExisting = byUser[userID] ?? [:]
			let chunk = targetIDs[start..<end].filter { currentExisting[$0] == nil }
			guard !chunk.isEmpty else { continue }
			
			let loaded = await manager.loadFromDiskOnly(for: chunk)
			guard !Task.isCancelled else { return }
			guard !loaded.isEmpty else { continue }
			
			let priority: TaskPriority = (start == 0) ? .userInitiated : .utility
			let extracted = await Task.detached(priority: priority) {
				loaded.map { AccoladesCalculator.extractCachedEntry(userID: userID, match: $0) }
			}.value
			
			guard !Task.isCancelled else { return }
			insert(extracted, for: userID)
			
			if end < targetIDs.count {
				await Task.yield()
			}
		}
	}
	
	nonisolated static func recordIfTracked(_ details: MatchDetails) {
		Task { @MainActor in
			await shared.ingestIfTracked(details)
		}
	}
	
	func remove(matchIDs: some Sequence<Match.ID>) {
		let removalSet = Set(matchIDs)
		guard !removalSet.isEmpty else { return }
		
		var didChange = false
		for userID in byUser.keys {
			guard var userMap = byUser[userID] else { continue }
			var userChanged = false
			for matchID in removalSet where userMap.removeValue(forKey: matchID) != nil {
				userChanged = true
			}
			if userChanged {
				byUser[userID] = userMap
				didChange = true
			}
		}
		
		guard didChange else { return }
		bumpRevision()
		saveImmediately()
	}
	
	func clearAll() {
		guard !byUser.isEmpty else { return }
		byUser.removeAll()
		bumpRevision()
		saveImmediately()
	}
	
	func refreshForImportedUsers(_ userIDs: Set<User.ID>) async {
		await waitUntilLoaded()
		let targets = Set(trackedUsers).union(userIDs)
		guard !targets.isEmpty else { return }
		let listManager = LocalDataProvider.shared.matchListManager
		for userID in targets {
			guard let matchList = await listManager.cachedObject(for: userID) else { continue }
			let matchIDs = matchList.matches.map(\.id)
			guard !matchIDs.isEmpty else { continue }
			await syncMissingMatches(for: userID, matchIDs: matchIDs)
		}
	}
	
	private func ingestIfTracked(_ details: MatchDetails) async {
		await waitUntilLoaded()
		let matchingUsers = trackedUsers.filter { userID in
			details.players.firstElement(withID: userID) != nil
		}
		guard !matchingUsers.isEmpty else { return }
		let extracted = await Task.detached(priority: .utility) {
			matchingUsers.map { ($0, AccoladesCalculator.extractCachedEntry(userID: $0, match: details)) }
		}.value
		for (userID, entry) in extracted {
			if byUser[userID]?[entry.matchID] != entry {
				insert([entry], for: userID)
			}
		}
	}
	
	private func insert(_ entries: [CachedMatchAccolades], for userID: User.ID) {
		guard !entries.isEmpty else { return }
		let previous = byUser[userID] ?? [:]
		var updated = previous
		for entry in entries {
			updated[entry.matchID] = entry
		}
		Self.trim(&updated, limit: Self.maxEntriesPerUser)
		guard updated != previous else { return }
		byUser[userID] = updated
		bumpRevision()
		scheduleSave()
	}
	
	private static func trim(_ map: inout [Match.ID: CachedMatchAccolades], limit: Int) {
		guard map.count > limit else { return }
		let kept = map.values
			.sorted { $0.gameStart > $1.gameStart }
			.prefix(limit)
		map = Dictionary(uniqueKeysWithValues: kept.map { ($0.matchID, $0) })
	}
	
	private func bumpRevision() {
		reportCache.removeAll(keepingCapacity: true)
		revision &+= 1
	}
	
	private func scheduleSave() {
		pendingSaveTask?.cancel()
		pendingSaveTask = Task { [weak self] in
			do {
				try await Task.sleep(nanoseconds: Self.saveDebounceNanoseconds)
			} catch {
				return
			}
			self?.persistToDisk()
		}
	}
	
	private func saveImmediately() {
		pendingSaveTask?.cancel()
		pendingSaveTask = nil
		persistToDisk()
	}
	
	private func persistToDisk() {
		let snapshot = byUser.compactMap { userID, map -> PersistedUserCache? in
			guard !map.isEmpty else { return nil }
			return PersistedUserCache(
				userID: userID,
				entries: map.values.sorted { $0.gameStart > $1.gameStart }
			)
		}
		if hasLoadedFromDisk {
			LocalJSONStore.save(snapshot, to: Self.filename)
		} else {
			Task { @MainActor [weak self] in
				await self?.waitUntilLoaded()
				guard let self else { return }
				let currentSnapshot = self.byUser.compactMap { userID, map -> PersistedUserCache? in
					guard !map.isEmpty else { return nil }
					return PersistedUserCache(
						userID: userID,
						entries: map.values.sorted { $0.gameStart > $1.gameStart }
					)
				}
				LocalJSONStore.save(currentSnapshot, to: Self.filename)
			}
		}
	}
}
