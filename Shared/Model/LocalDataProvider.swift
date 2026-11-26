import Foundation
import Combine
import ValorantAPI
import HandyOperators

protocol LocalDataStored: Identifiable, Codable where ID: LosslessStringConvertible {
	static var managerPath: KeyPath<LocalDataProvider, LocalDataManager<Self>> { get }
}

protocol LocalDataAutoUpdatable: LocalDataStored {
	static func autoUpdate(for id: ID, using client: ValorantClient) async throws
}

extension MatchList: LocalDataAutoUpdatable {
	static let managerPath = \LocalDataProvider.matchListManager as KeyPath
	
	static func autoUpdate(for id: ID, using client: ValorantClient) async throws {
		try await client.autoUpdateMatchList(for: id)
	}
}

extension CareerSummary: LocalDataAutoUpdatable {
	static let managerPath = \LocalDataProvider.careerSummaryManager as KeyPath
	
	static func autoUpdate(for id: ID, using client: ValorantClient) async throws {
		try await client.fetchCareerSummary(for: id)
	}
}

extension User: LocalDataAutoUpdatable {
	static let managerPath = \LocalDataProvider.userManager as KeyPath
	
	static func autoUpdate(for id: ID, using client: ValorantClient) async throws {
		try await client.fetchUsers(for: [id])
	}
}

extension MatchDetails: LocalDataAutoUpdatable {
	static let managerPath = \LocalDataProvider.matchDetailsManager as KeyPath
	
	static func autoUpdate(for id: ID, using client: ValorantClient) async throws {
		try await client.fetchMatchDetails(for: id)
	}
}

extension Player.Identity: LocalDataAutoUpdatable {
	static let managerPath = \LocalDataProvider.playerIdentityManager as KeyPath
	
	static func autoUpdate(for id: ID, using client: ValorantClient) async throws {
		try await client.fetchIdentity(for: id)
	}
}

final class LocalDataProvider {
	static let shared = LocalDataProvider()
	
	static var onIdentitiesStored: (@Sendable ([Player.Identity], Date) -> Void)?
	static var onIdentityAndTierResolved: (@Sendable (Player.Identity, Int?, Date) -> Void)?
	
	var matchListManager = LocalDataManager<MatchList>(ageCausingAutoUpdate: .minutes(5))
	var careerSummaryManager = LocalDataManager<CareerSummary>(ageCausingAutoUpdate: .minutes(5))
	var userManager = LocalDataManager<User>(ageCausingAutoUpdate: .hours(1))
	var matchDetailsManager = LocalDataManager<MatchDetails>(maxInMemoryEntries: 60)
	var playerIdentityManager = LocalDataManager<Player.Identity>(ageCausingAutoUpdate: .minutes(5))
	
	private init() {}
	
	// MARK: -
	
	func store(_ matchList: MatchList) {
		Task { await matchListManager.store(matchList, asOf: .now) }
	}
	
	func store(_ identities: [Player.Identity], asOf updateTime: Date) {
		Task { await playerIdentityManager.store(identities, asOf: updateTime) }
		if !identities.isEmpty {
			Self.onIdentitiesStored?(identities, updateTime)
		}
	}
	
	// MARK: - updates from other sources
	
	// TODO: still not super happy with these tbh
	static func dataFetched(_ details: MatchDetails) {
		shared.store(details.players.map(\.identity), asOf: details.matchInfo.gameStart)
		UsernameHistoryStore.record(players: details.players)
		AccoladesCacheStore.recordIfTracked(details)
	}
	
	static func dataFetched(_ info: LivePregameInfo) {
		shared.store(info.team.players.map(\.identity), asOf: .now)
	}
	
	static func dataFetched(_ info: LiveGameInfo) {
		shared.store(info.players.map(\.identity), asOf: .now)
	}
	
	static func dataFetched(_ user: User) {
		UsernameHistoryStore.record(user)
		Task { await shared.userManager.store(user, asOf: .now) }
	}
	
	static func dataFetched(_ party: Party) {
		shared.store(party.members.map(\.identity), asOf: .now)
	}
	
	static func dataFetched(_ loadout: Loadout) {
		Task {
			let existing = await shared.playerIdentityManager.cachedObject(for: loadout.subject)
			let identity = Player.Identity(
				id: loadout.subject,
				cardID: loadout.identity.card,
				titleID: loadout.identity.title,
				accountLevel: existing?.accountLevel ?? 0,
				isIncognito: loadout.isIncognito
			)
			await shared.playerIdentityManager.store(identity, asOf: .now)
			onIdentitiesStored?([identity], .now)
		}
	}
}

extension LocalDataManager where Object == MatchDetails {
	func unloadedMatches(in matchList: MatchList, maxCount: Int) async -> [Match.ID]? {
		let matches = matchList.matches.prefix(maxCount + 1) // need at least 1 more to know if it's been exceeded
		var unloaded: [Match.ID] = []
		for match in matches {
			if await hasCachedFile(for: match.id) {
				break
			}
			unloaded.append(match.id)
			if unloaded.count > maxCount {
				return nil
			}
		}
		return unloaded
	}
}

extension LocalDataManager where Object == MatchList {
	@discardableResult
	func importMatchLists(_ entries: [Entry], replaceAll: Bool) async throws -> Int {
		var byUser: [User.ID: Entry] = [:]
		for incoming in entries {
			if let existing = byUser[incoming.id] {
				byUser[incoming.id] = Self.mergeMatchListEntries(existing, incoming)
			} else {
				byUser[incoming.id] = Self.normalizeMatchListEntry(incoming)
			}
		}
		
		if replaceAll {
			try await clearOut()
			return try await persistImportedEntries(Array(byUser.values), forceChangeNotification: true)
		}
		
		let existingByID = await existingEntriesByID(for: Array(byUser.keys))
		var toSave: [Entry] = []
		for (userID, incoming) in byUser {
			if let existing = existingByID[userID] {
				let merged = Self.mergeMatchListEntries(existing, incoming)
				let existingIDs = Set(existing.object.matches.map(\.id))
				let mergedIDs = Set(merged.object.matches.map(\.id))
				if mergedIDs != existingIDs
					|| merged.object.matches.count != existing.object.matches.count
					|| merged.object.highestLoadedIndex != existing.object.highestLoadedIndex
					|| merged.lastUpdate > existing.lastUpdate {
					toSave.append(merged)
				}
			} else {
				toSave.append(incoming)
			}
		}
		
		return try await persistImportedEntries(toSave, forceChangeNotification: false)
	}
	
	private static func normalizeMatchListEntry(_ entry: Entry) -> Entry {
		var byMatchID: [Match.ID: CompetitiveUpdate] = [:]
		for match in entry.object.matches {
			if byMatchID[match.id] == nil {
				byMatchID[match.id] = match
			}
		}
		let sorted = byMatchID.values.sorted { $0.startTime > $1.startTime }
		var copy = entry
		copy.object.matches = sorted
		return copy
	}
	
	private static func mergeMatchListEntries(_ lhs: Entry, _ rhs: Entry) -> Entry {
		let older = lhs.lastUpdate <= rhs.lastUpdate ? lhs : rhs
		let newer = lhs.lastUpdate <= rhs.lastUpdate ? rhs : lhs
		
		var byMatchID: [Match.ID: CompetitiveUpdate] = [:]
		for match in older.object.matches {
			byMatchID[match.id] = match
		}
		for match in newer.object.matches {
			byMatchID[match.id] = match
		}
		let sorted = byMatchID.values.sorted { $0.startTime > $1.startTime }
		let mergedList = MatchList(
			userID: newer.object.userID,
			matches: sorted,
			highestLoadedIndex: max(older.object.highestLoadedIndex, newer.object.highestLoadedIndex)
		)
		return Entry(lastUpdate: max(older.lastUpdate, newer.lastUpdate), object: mergedList)
	}
}

extension ValorantClient {
	func autoUpdateMatchList(for userID: User.ID) async throws {
		let manager = LocalDataProvider.shared.matchListManager
		try await manager.autoUpdateObject(for: userID) { existing in
			let list = existing ?? MatchList(userID: userID)
			// never update match history for people on the denylist, but allow the first time
			guard list.matches.isEmpty || userID == self.userID || Denylist.allows(userID) else { return list }
			return try await list <- loadMatches <- autoFetchMatchListDetails
		}
	}
	
	func autoFetchMatchListDetails(for matchList: MatchList) {
		if let autoDownload = UserDefaults.standard.object(forKey: "MatchList.autoDownload") as? Bool, !autoDownload {
			return
		}
		Task.detached { [self] in
			guard let newestMatch = matchList.matches.first else { return }
			
			let manager = LocalDataProvider.shared.matchDetailsManager
			let maxAutoFetchedMatches = 10
			if let unloadedMatches = await manager.unloadedMatches(
				in: matchList,
				maxCount: maxAutoFetchedMatches
			) {
				// the last loaded match is close enough to catch up with reasonably few requests—let's do it!
				try? await fetchMatchDetails(for: unloadedMatches)
			} else {
				// too many unloaded matches—just fetch the most recent one
				try? await fetchMatchDetails(for: newestMatch.id)
			}
		}
	}
	
	func updateMatchList(for userID: User.ID, update: @escaping (inout MatchList) async throws -> Void) async throws {
		let manager = LocalDataProvider.shared.matchListManager
		guard let matchList = await manager.cachedObject(for: userID) else { return }
		
		// never update match history for people on the denylist, but allow the first time
		guard matchList.matches.isEmpty || userID == self.userID || Denylist.allows(userID) else { return }
		
		LocalDataProvider.shared.store(try await matchList <- update <- autoFetchMatchListDetails)
	}
	
	func fetchCareerSummary(for userID: User.ID, forceFetch: Bool = false) async throws {
		let manager = LocalDataProvider.shared.careerSummaryManager
		
		// never update career summary for people on the denylist
		if userID != self.userID, !Denylist.allows(userID) {
			// but allow the first time
			let existing = await manager.cachedObject(for: userID)
			guard existing == nil else { return }
		}
		
		if forceFetch {
			try await manager.store(getCareerSummary(userID: userID), asOf: .now)
		} else {
			try await manager.fetchIfNecessary(for: userID, fetch: getCareerSummary)
		}
	}
	
	func fetchUsers(for ids: [User.ID]) async throws {
		let manager = LocalDataProvider.shared.userManager
		try await manager.fetchIfNecessary(ids, fetch: getUsers)
	}
	
	func fetchIdentity(for userID: User.ID, forceFetch: Bool = false) async throws {
		guard userID == self.userID else { return }
		let manager = LocalDataProvider.shared.playerIdentityManager
		let fetch: (User.ID) async throws -> Player.Identity = { [self] id in
			async let loadout = getLoadout()
			async let level = getAccountLevel()
			let cached = await manager.cachedObject(for: id)
			let resolvedLoadout = try await loadout
			return Player.Identity(
				id: id,
				cardID: resolvedLoadout.identity.card,
				titleID: resolvedLoadout.identity.title,
				accountLevel: (try? await level) ?? cached?.accountLevel ?? 0,
				isIncognito: resolvedLoadout.isIncognito
			)
		}
		if forceFetch {
			try await manager.store(fetch(userID), asOf: .now)
		} else {
			try await manager.fetchIfNecessary(for: userID, fetch: fetch)
		}
	}
	
	func fetchMatchDetails(for matchID: Match.ID) async throws {
		let manager = LocalDataProvider.shared.matchDetailsManager
		try await manager.fetchIfNecessary(for: matchID) {
			let details = try await getMatchDetails(matchID: $0)
				<- LocalDataProvider.dataFetched
			let missingUserIDs = details.players.filter(\.gameName.isEmpty).map(\.id)
			if !missingUserIDs.isEmpty {
				try? await fetchUsers(for: missingUserIDs)
			}
			return details
		}
	}
	
	func fetchMatchDetails(for matchIDs: [Match.ID]) async throws {
		try await withThrowingTaskGroup(of: Void.self) { group in
			var iterator = matchIDs.makeIterator()
			for _ in 0..<4 {
				guard let nextID = iterator.next() else { break }
				group.addTask {
					try await self.fetchMatchDetails(for: nextID)
				}
			}
			while try await group.next() != nil {
				if let nextID = iterator.next() {
					group.addTask {
						try await self.fetchMatchDetails(for: nextID)
					}
				}
			}
		}
	}
	
	func prefetchPlayerPreview(for user: User, latestMatchID: Match.ID?) async -> Player.Identity? {
		UsernameHistoryStore.record(user)
		await LocalDataProvider.shared.userManager.store(user, asOf: .now)
		
		async let summaryTask: Void = {
			try? await self.fetchCareerSummary(for: user.id)
		}()
		async let identityTask: Player.Identity? = self.resolvePlayerIdentity(
			for: user.id,
			latestMatchID: latestMatchID
		)
		
		let (_, identity) = await (summaryTask, identityTask)
		return identity
	}
	
	private func resolvePlayerIdentity(for userID: User.ID, latestMatchID: Match.ID?) async -> Player.Identity? {
		if userID == self.userID {
			try? await fetchIdentity(for: userID)
			return await LocalDataProvider.shared.playerIdentityManager.cachedObject(for: userID)
		}
		
		if let latestMatchID {
			try? await fetchMatchDetails(for: latestMatchID)
			if let details = await LocalDataProvider.shared.matchDetailsManager.cachedObject(for: latestMatchID),
			   let player = details.players.first(where: { $0.id == userID }) {
				let identity = player.identity
				await LocalDataProvider.shared.playerIdentityManager.store(
					identity,
					asOf: details.matchInfo.gameStart
				)
				return await LocalDataProvider.shared.playerIdentityManager.cachedObject(for: userID) ?? identity
			}
		}
		
		return await LocalDataProvider.shared.playerIdentityManager.cachedObject(for: userID)
	}
	
	func backfillMissingIdentities(for entries: [(userID: User.ID, location: Location)]) async {
		for (userID, location) in entries {
			guard !Task.isCancelled else { return }
			guard await LocalDataProvider.shared.playerIdentityManager.cachedObject(for: userID) == nil else {
				continue
			}
			let scoped = self.in(location)
			if userID == self.userID {
				try? await scoped.fetchIdentity(for: userID)
			} else if let latestMatchID = try? await scoped.getMatchHistory(userID: userID).first?.matchID {
				_ = await scoped.resolvePlayerIdentity(for: userID, latestMatchID: latestMatchID)
			}
		}
	}
}
