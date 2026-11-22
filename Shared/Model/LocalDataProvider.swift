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
	
	var matchListManager = LocalDataManager<MatchList>(ageCausingAutoUpdate: .minutes(5))
	var careerSummaryManager = LocalDataManager<CareerSummary>(ageCausingAutoUpdate: .minutes(5))
	var userManager = LocalDataManager<User>(ageCausingAutoUpdate: .hours(1))
	var matchDetailsManager = LocalDataManager<MatchDetails>()
	var playerIdentityManager = LocalDataManager<Player.Identity>(ageCausingAutoUpdate: .minutes(5))
	
	private init() {}
	
	// MARK: -
	
	func store(_ matchList: MatchList) {
		Task { await matchListManager.store(matchList, asOf: .now) }
	}
	
	func store(_ identities: [Player.Identity], asOf updateTime: Date) {
		Task { await playerIdentityManager.store(identities, asOf: updateTime) }
	}
	
	// MARK: - updates from other sources
	
	// TODO: still not super happy with these tbh
	static func dataFetched(_ details: MatchDetails) {
		shared.store(details.players.map(\.identity), asOf: details.matchInfo.gameStart)
	}
	
	static func dataFetched(_ info: LivePregameInfo) {
		shared.store(info.team.players.map(\.identity), asOf: .now)
	}
	
	static func dataFetched(_ info: LiveGameInfo) {
		shared.store(info.players.map(\.identity), asOf: .now)
	}
	
	static func dataFetched(_ user: User) {
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
		}
	}
}

extension LocalDataManager where Object == MatchDetails {
	func unloadedMatches(in matchList: MatchList, maxCount: Int) async -> [Match.ID]? {
		let matches = matchList.matches.prefix(maxCount + 1) // need at least 1 more to know if it's been exceeded
		let cached = await cachedObjects(for: matches.lazy.map(\.id))
		let cachedIDs = Set(cached.lazy.map(\.id))
		let unloaded = matches.prefix { !cachedIDs.contains($0.id) }
		return unloaded.count > maxCount ? nil : unloaded.map(\.id)
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
			for matchID in matchIDs {
				group.addTask {
					try await self.fetchMatchDetails(for: matchID)
				}
			}
			for try await _ in group {} // TODO: might be able to remove this once the function stops being rethrows
		}
	}
}
