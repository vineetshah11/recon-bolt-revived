import Foundation
import Combine
import ValorantAPI

struct CachedGroupParticipant: Codable, Equatable, Hashable, Identifiable {
	var id: User.ID
	var gameName: String
	var tagLine: String
	var cardID: PlayerCard.ID
	var competitiveTier: Int
	var agentID: Agent.ID?
	var teamID: Team.ID
	var partyID: Party.ID
	var kills: Int
	var deaths: Int
	var assists: Int
	var score: Int
	var roundsPlayed: Int
	var headshots: Int
	var totalHits: Int
	var sameTeam: Bool
	var sameParty: Bool
}

struct CachedGroupMatchSummary: Codable, Equatable, Hashable, Identifiable {
	var id: Match.ID { matchID }
	var matchID: Match.ID
	var gameStart: Date
	var gameLength: TimeInterval
	var mapID: MapID
	var queueID: QueueID?
	var modeID: GameMode.ID
	var seasonID: Season.ID
	var isRanked: Bool
	var isCompleted: Bool
	var won: Bool
	var tied: Bool
	var roundsWon: Int
	var roundsLost: Int
	var userAgentID: Agent.ID?
	var userKills: Int
	var userDeaths: Int
	var userAssists: Int
	var userScore: Int
	var userRoundsPlayed: Int
	var userDamage: Int
	var userHeadshots: Int
	var userBodyshots: Int
	var userLegshots: Int
	var participants: [CachedGroupParticipant]
}

enum GroupMatchSummaryExtractor {
	static func extract(userID: User.ID, match: MatchDetails) -> CachedGroupMatchSummary? {
		guard match.matchInfo.isCompleted,
			  let userPlayer = match.players.firstElement(withID: userID),
			  userPlayer.teamID != .neutral else {
			return nil
		}
		
		let myTeam = match.teams.firstElement(withID: userPlayer.teamID)
		let winner = match.teams.first(where: \.won)
		let won = (winner?.id == userPlayer.teamID) || (myTeam?.won == true)
		let tied = (winner == nil) && (myTeam?.won != true)
		
		let myRounds: Int = {
			guard let myTeam else { return 0 }
			return myTeam.roundsWon > 0 ? myTeam.roundsWon : myTeam.pointCount
		}()
		let enemyRounds: Int = match.teams
			.lazy
			.filter { $0.id != userPlayer.teamID }
			.map { $0.roundsWon > 0 ? $0.roundsWon : $0.pointCount }
			.max() ?? 0
		
		var userDamage = 0
		var userHeadshots = 0
		var userBodyshots = 0
		var userLegshots = 0
		var hitStatsByPlayer: [User.ID: (hs: Int, hits: Int)] = Dictionary(minimumCapacity: match.players.count)
		
		for round in match.roundResults {
			for playerStat in round.playerStats {
				var hs = 0
				var hits = 0
				var dmg = 0
				for deal in playerStat.damageDealt {
					hs += deal.headshots
					hits += deal.headshots + deal.bodyshots + deal.legshots
					if playerStat.subject == userID {
						dmg += deal.damage
						userBodyshots += deal.bodyshots
						userLegshots += deal.legshots
					}
				}
				if playerStat.subject == userID {
					userDamage += dmg
					userHeadshots += hs
				} else if hits > 0 {
					let current = hitStatsByPlayer[playerStat.subject] ?? (0, 0)
					hitStatsByPlayer[playerStat.subject] = (current.hs + hs, current.hits + hits)
				}
			}
		}
		
		let hasValidParty = !userPlayer.partyID.isPseudoNull
		let defaultRounds = match.roundResults.count
		var participants: [CachedGroupParticipant] = []
		participants.reserveCapacity(max(0, match.players.count - 1))
		
		for player in match.players where player.id != userID && player.teamID != .neutral {
			let sameTeam = (player.teamID == userPlayer.teamID)
			let sameParty = hasValidParty && sameTeam && (player.partyID == userPlayer.partyID)
			let hitStats = hitStatsByPlayer[player.id] ?? (0, 0)
			let pStats = player.stats
			
			participants.append(CachedGroupParticipant(
				id: player.id,
				gameName: player.gameName,
				tagLine: player.tagLine,
				cardID: player.playerCardID,
				competitiveTier: player.competitiveTier,
				agentID: player.agentID,
				teamID: player.teamID,
				partyID: player.partyID,
				kills: pStats?.kills ?? 0,
				deaths: pStats?.deaths ?? 0,
				assists: pStats?.assists ?? 0,
				score: pStats?.score ?? 0,
				roundsPlayed: pStats?.roundsPlayed ?? defaultRounds,
				headshots: hitStats.hs,
				totalHits: hitStats.hits,
				sameTeam: sameTeam,
				sameParty: sameParty
			))
		}
		
		let uStats = userPlayer.stats
		let resolvedQueueID: QueueID? = (match.matchInfo.provisioningFlowID == .customGame)
			? .custom
			: match.matchInfo.queueID
		return CachedGroupMatchSummary(
			matchID: match.id,
			gameStart: match.matchInfo.gameStart,
			gameLength: match.matchInfo.gameLength,
			mapID: match.matchInfo.mapID,
			queueID: resolvedQueueID,
			modeID: match.matchInfo.modeID,
			seasonID: match.matchInfo.seasonID,
			isRanked: match.matchInfo.isRanked,
			isCompleted: match.matchInfo.isCompleted,
			won: won,
			tied: tied,
			roundsWon: myRounds,
			roundsLost: enemyRounds,
			userAgentID: userPlayer.agentID,
			userKills: uStats?.kills ?? 0,
			userDeaths: uStats?.deaths ?? 0,
			userAssists: uStats?.assists ?? 0,
			userScore: uStats?.score ?? 0,
			userRoundsPlayed: uStats?.roundsPlayed ?? defaultRounds,
			userDamage: userDamage,
			userHeadshots: userHeadshots,
			userBodyshots: userBodyshots,
			userLegshots: userLegshots,
			participants: participants
		)
	}
}

/// Persistent lightweight cache of match rosters & per-player combat summaries so Group Performance
/// computes across hundreds of matches instantaneously without polluting `matchDetailsManager`'s LRU cache.
@MainActor
final class GroupPerformanceCacheStore: ObservableObject {
	static let shared = GroupPerformanceCacheStore()
	
	private static let filename = "GroupPerformanceCache.v1.json"
	private static let maxEntriesPerUser = 500
	private static let chunkSize = 20
	private static let saveDebounceNanoseconds: UInt64 = 500_000_000
	
	private struct PersistedUserCache: Codable {
		var userID: User.ID
		var entries: [CachedGroupMatchSummary]
	}
	
	@Published private(set) var revision: Int = 0
	@Published private(set) var isBackfilling = false
	
	private var byUser: [User.ID: [Match.ID: CachedGroupMatchSummary]] = [:]
	private var trackedUsers: Set<User.ID> = []
	private var inFlightMatchIDsByUser: [User.ID: Set<Match.ID>] = [:]
	private var unavailableDiskIDsByUser: [User.ID: Set<Match.ID>] = [:]
	private var activeBackfillCount = 0
	private var pendingSaveTask: Task<Void, Never>?
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
	
	func cachedEntriesSnapshot(for userID: User.ID) -> [CachedGroupMatchSummary] {
		Array((byUser[userID] ?? [:]).values)
	}
	
	func cachedMatchIDs(for userID: User.ID) -> Set<Match.ID> {
		Set((byUser[userID] ?? [:]).keys)
	}
	
	func hasCachedSummary(for userID: User.ID, matchID: Match.ID) -> Bool {
		byUser[userID]?[matchID] != nil
	}
	
	func cachedMatchCount(for userID: User.ID) -> Int {
		byUser[userID]?.count ?? 0
	}
	
	/// Backfills cached group summaries from disk-cached `MatchDetails` in small chunks without
	/// inserting them into or evicting from `matchDetailsManager`'s in-memory LRU cache.
	func syncMissingMatches(for userID: User.ID, matchIDs: [Match.ID]) async {
		trackedUsers.insert(userID)
		await waitUntilLoaded()
		
		activeBackfillCount += 1
		isBackfilling = true
		defer {
			activeBackfillCount = max(0, activeBackfillCount - 1)
			isBackfilling = (activeBackfillCount > 0)
		}
		
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
				inMemoryToExtract.compactMap { GroupMatchSummaryExtractor.extract(userID: userID, match: $0) }
			}.value
			inFlightMatchIDsByUser[userID]?.subtract(claimedMemoryIDs)
			unavailableDiskIDsByUser[userID]?.subtract(claimedMemoryIDs)
			insert(extracted, for: userID)
		}
		
		var seen: Set<Match.ID> = []
		let existing = byUser[userID] ?? [:]
		let inFlight = inFlightMatchIDsByUser[userID] ?? []
		let unavailable = unavailableDiskIDsByUser[userID] ?? []
		let targetIDs = matchIDs
			.prefix(Self.maxEntriesPerUser)
			.filter { id in
				seen.insert(id).inserted
				&& existing[id] == nil
				&& !inFlight.contains(id)
				&& !unavailable.contains(id)
			}
		
		guard !targetIDs.isEmpty else { return }
		inFlightMatchIDsByUser[userID, default: []].formUnion(targetIDs)
		defer { inFlightMatchIDsByUser[userID]?.subtract(targetIDs) }
		
		var pendingBatch: [CachedGroupMatchSummary] = []
		defer {
			if !pendingBatch.isEmpty {
				insert(pendingBatch, for: userID)
			}
		}
		
		for start in stride(from: 0, to: targetIDs.count, by: Self.chunkSize) {
			guard !Task.isCancelled else { return }
			let end = min(start + Self.chunkSize, targetIDs.count)
			let currentExisting = byUser[userID] ?? [:]
			let chunk = targetIDs[start..<end].filter { currentExisting[$0] == nil }
			guard !chunk.isEmpty else { continue }
			
			let loaded = await manager.loadFromDiskOnly(for: chunk)
			guard !Task.isCancelled else { return }
			
			let loadedIDs = Set(loaded.map(\.id))
			let missingFromDisk = chunk.filter { !loadedIDs.contains($0) }
			if !missingFromDisk.isEmpty {
				unavailableDiskIDsByUser[userID, default: []].formUnion(missingFromDisk)
			}
			guard !loaded.isEmpty else { continue }
			
			let priority: TaskPriority = (start == 0) ? .userInitiated : .utility
			let extracted = await Task.detached(priority: priority) {
				loaded.compactMap { GroupMatchSummaryExtractor.extract(userID: userID, match: $0) }
			}.value
			
			if start == 0 {
				guard !Task.isCancelled else { return }
				insert(extracted, for: userID)
			} else {
				pendingBatch.append(contentsOf: extracted)
				if pendingBatch.count >= 60 {
					insert(pendingBatch, for: userID)
					pendingBatch.removeAll(keepingCapacity: true)
				}
			}
			
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
		
		for userID in unavailableDiskIDsByUser.keys {
			unavailableDiskIDsByUser[userID]?.subtract(removalSet)
		}
		
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
		unavailableDiskIDsByUser.removeAll()
		guard !byUser.isEmpty else { return }
		byUser.removeAll()
		bumpRevision()
		saveImmediately()
	}
	
	func refreshForImportedUsers(_ userIDs: Set<User.ID>) async {
		await waitUntilLoaded()
		unavailableDiskIDsByUser.removeAll()
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
		for userID in unavailableDiskIDsByUser.keys {
			unavailableDiskIDsByUser[userID]?.remove(details.id)
		}
		let matchingUsers = trackedUsers.filter { userID in
			details.players.firstElement(withID: userID) != nil
		}
		guard !matchingUsers.isEmpty else { return }
		let extracted = await Task.detached(priority: .utility) {
			matchingUsers.compactMap { uid in
				GroupMatchSummaryExtractor.extract(userID: uid, match: details).map { (uid, $0) }
			}
		}.value
		for (userID, entry) in extracted {
			if byUser[userID]?[entry.matchID] != entry {
				insert([entry], for: userID)
			}
		}
	}
	
	private func insert(_ entries: [CachedGroupMatchSummary], for userID: User.ID) {
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
	
	private static func trim(_ map: inout [Match.ID: CachedGroupMatchSummary], limit: Int) {
		guard map.count > limit else { return }
		let kept = map.values
			.sorted { $0.gameStart > $1.gameStart }
			.prefix(limit)
		map = Dictionary(uniqueKeysWithValues: kept.map { ($0.matchID, $0) })
	}
	
	private func bumpRevision() {
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
