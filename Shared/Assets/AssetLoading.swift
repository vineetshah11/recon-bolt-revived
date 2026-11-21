import Foundation

extension AssetClient {
	func collectAssets(for version: AssetVersion) async throws -> AssetCollection {
		print("loading assets for version \(version) in language \(language)")
		
		// Core assets: a failure here is fatal because the app can't present much without them.
		async let maps = getMapInfo()
		async let agents = getAgentInfo()
		async let gameModes = getGameModeInfo()
		async let playerCards = getPlayerCardInfo()
		async let weapons = getWeaponInfo()
		async let seasons = getSeasons()
		
		// Secondary assets: a 404 or decode error on any one of these must not abort the whole collection.
		let objectives = await safeSecondary { try await getObjectiveInfo() } ?? []
		let missions = await safeSecondary { try await getMissionInfo() } ?? []
		let contracts = await safeSecondary { try await getContractInfo() } ?? []
		let playerTitles = await safeSecondary { try await getPlayerTitleInfo() } ?? []
		let sprays = await safeSecondary { try await getSprayInfo() } ?? []
		let buddies = await safeSecondary { try await getBuddyInfo() } ?? []
		let currencies = await safeSecondary { try await getCurrencyInfo() } ?? []
		let bundles = await safeSecondary { try await getBundleInfo() } ?? []
		let contentTiers = await safeSecondary { try await getContentTiers() } ?? []
		let totems = await safeSecondary { try await getTotemInfo() } ?? []
		let queues = await safeSecondary { try await getQueues() } ?? []
		
		// this seems to be what skins are actually referred to by…
		let skinsByLevelID = await Dictionary(
			uniqueKeysWithValues: weapons.lazy.flatMap { weapon in
				weapon.skins.enumerated().lazy.flatMap { skinIndex, skin in
					skin.levels.enumerated().map { levelIndex, level in
						(level.id, WeaponSkin.Level.Path(weapon: weapon.id, skinIndex: skinIndex, levelIndex: levelIndex))
					}
				}
			}
		)
		
		let buddiesByLevelID = Dictionary(
			uniqueKeysWithValues: buddies.lazy.flatMap { buddy in
				buddy.levels.map { ($0.id, buddy.id) }
			}
		)
		
		return try await AssetCollection(
			version: version,
			language: language,
			maps: .init(values: maps),
			agents: .init(values: agents),
			missions: .init(values: missions),
			contracts: .init(values: contracts),
			// riot doesn't exactly seem to know the word "consistency":
			gameModes: .init(values: gameModes, keyedBy: { $0.gameID() }),
			queues: .init(values: queues),
			objectives: .init(values: objectives),
			playerCards: .init(values: playerCards),
			playerTitles: .init(values: playerTitles),
			weapons: .init(values: weapons),
			seasons: seasons,
			skinsByLevelID: skinsByLevelID,
			sprays: .init(values: sprays),
			totems: .init(values: totems),
			buddies: .init(values: buddies),
			buddiesByLevelID: buddiesByLevelID,
			currencies: .init(values: currencies),
			bundles: .init(values: bundles),
			contentTiers: .init(values: contentTiers)
		)
	}
	
	private func safeSecondary<T>(_ fetch: @escaping () async throws -> T) async -> T? {
		do {
			return try await fetch()
		} catch {
			print("⚠️ Failed to fetch a secondary asset (non-fatal):", error)
			return nil
		}
	}
}
