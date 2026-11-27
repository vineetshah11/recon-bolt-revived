import Foundation
import ArrayBuilder
import ValorantAPI

struct AssetCollection: Codable {
	let version: AssetVersion
	let language: String
	
	let maps: [MapID: MapInfo]
	let agents: [Agent.ID: AgentInfo]
	let missions: [Mission.ID: MissionInfo]
	let contracts: [Contract.ID: ContractInfo]
	let gameModes: [GameMode.ID: GameModeInfo]
	let queues: [QueueID: QueueInfo]
	let objectives: [Objective.ID: ObjectiveInfo]
	let playerCards: [PlayerCard.ID: PlayerCardInfo]
	let playerTitles: [PlayerTitle.ID: PlayerTitleInfo]
	let weapons: [Weapon.ID: WeaponInfo]
	let seasons: SeasonCollection
	let skinsByLevelID: [WeaponSkin.Level.ID: WeaponSkin.Level.Path]
	let sprays: [Spray.ID: SprayInfo]
	let buddies: [Weapon.Buddy.ID: BuddyInfo]
	let buddiesByLevelID: [Weapon.Buddy.Level.ID: Weapon.Buddy.ID]
	let currencies: [Currency.ID: CurrencyInfo]
	let bundles: [StoreBundle.Asset.ID: StoreBundleInfo]
	let contentTiers: [ContentTier.ID: ContentTier]
	let flex: [Totem.ID: FlexInfo]
	let levelBorders: [LevelBorder.ID: LevelBorderInfo]
	let gamePods: [String: String]
	
	private let mapsLowercased: [String: MapInfo]
	private let mapsByShortNameLowercased: [String: MapInfo]
	private let gameModesLowercased: [String: GameModeInfo]
	private let gamePodsLowercased: [String: String]
	let knownNonTacticalMapPathsLowercased: Set<String>
	let canonicalMapPathsByShortName: [String: String]
	let modeFoldersByShortName: [String: String]
	
	init(
		version: AssetVersion,
		language: String,
		maps: [MapID: MapInfo],
		agents: [Agent.ID: AgentInfo],
		missions: [Mission.ID: MissionInfo],
		contracts: [Contract.ID: ContractInfo],
		gameModes: [GameMode.ID: GameModeInfo],
		queues: [QueueID: QueueInfo],
		objectives: [Objective.ID: ObjectiveInfo],
		playerCards: [PlayerCard.ID: PlayerCardInfo],
		playerTitles: [PlayerTitle.ID: PlayerTitleInfo],
		weapons: [Weapon.ID: WeaponInfo],
		seasons: SeasonCollection,
		skinsByLevelID: [WeaponSkin.Level.ID: WeaponSkin.Level.Path],
		sprays: [Spray.ID: SprayInfo],
		buddies: [Weapon.Buddy.ID: BuddyInfo],
		buddiesByLevelID: [Weapon.Buddy.Level.ID: Weapon.Buddy.ID],
		currencies: [Currency.ID: CurrencyInfo],
		bundles: [StoreBundle.Asset.ID: StoreBundleInfo],
		contentTiers: [ContentTier.ID: ContentTier],
		flex: [Totem.ID: FlexInfo],
		levelBorders: [LevelBorder.ID: LevelBorderInfo],
		gamePods: [String: String]
	) {
		self.version = version
		self.language = language
		self.maps = maps
		self.agents = agents
		self.missions = missions
		self.contracts = contracts
		self.gameModes = gameModes
		self.queues = queues
		self.objectives = objectives
		self.playerCards = playerCards
		self.playerTitles = playerTitles
		self.weapons = weapons
		self.seasons = seasons
		self.skinsByLevelID = skinsByLevelID
		self.sprays = sprays
		self.buddies = buddies
		self.buddiesByLevelID = buddiesByLevelID
		self.currencies = currencies
		self.bundles = bundles
		self.contentTiers = contentTiers
		self.flex = flex
		self.levelBorders = levelBorders
		self.gamePods = gamePods
		self.mapsLowercased = Self.buildMapsLowercased(maps)
		self.mapsByShortNameLowercased = Self.buildMapsByShortNameLowercased(maps)
		self.gameModesLowercased = Self.buildGameModesLowercased(gameModes)
		self.gamePodsLowercased = Self.buildGamePodsLowercased(gamePods)
		self.knownNonTacticalMapPathsLowercased = Self.buildNonTacticalPaths(maps)
		self.canonicalMapPathsByShortName = Self.buildCanonicalMapPathsByShortName(maps)
		self.modeFoldersByShortName = Self.buildModeFoldersByShortName(gameModes)
	}
}

extension AssetCollection {
	private enum CodingKeys: String, CodingKey {
		case version, language
		case maps, agents, missions, contracts, gameModes, queues, objectives
		case playerCards, playerTitles, weapons, seasons, skinsByLevelID
		case sprays, buddies, buddiesByLevelID, currencies, bundles
		case contentTiers, flex, levelBorders, gamePods
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.version = try container.decode(AssetVersion.self, forKey: .version)
		self.language = try container.decode(String.self, forKey: .language)
		let maps = try container.decode([MapID: MapInfo].self, forKey: .maps)
		self.maps = maps
		self.agents = try container.decode([Agent.ID: AgentInfo].self, forKey: .agents)
		self.missions = try container.decode([Mission.ID: MissionInfo].self, forKey: .missions)
		self.contracts = try container.decode([Contract.ID: ContractInfo].self, forKey: .contracts)
		let gameModes = try container.decode([GameMode.ID: GameModeInfo].self, forKey: .gameModes)
		self.gameModes = gameModes
		self.queues = try container.decode([QueueID: QueueInfo].self, forKey: .queues)
		self.objectives = try container.decode([Objective.ID: ObjectiveInfo].self, forKey: .objectives)
		self.playerCards = try container.decode([PlayerCard.ID: PlayerCardInfo].self, forKey: .playerCards)
		self.playerTitles = try container.decode([PlayerTitle.ID: PlayerTitleInfo].self, forKey: .playerTitles)
		self.weapons = try container.decode([Weapon.ID: WeaponInfo].self, forKey: .weapons)
		self.seasons = try container.decode(SeasonCollection.self, forKey: .seasons)
		self.skinsByLevelID = try container.decode([WeaponSkin.Level.ID: WeaponSkin.Level.Path].self, forKey: .skinsByLevelID)
		self.sprays = try container.decode([Spray.ID: SprayInfo].self, forKey: .sprays)
		self.buddies = try container.decode([Weapon.Buddy.ID: BuddyInfo].self, forKey: .buddies)
		self.buddiesByLevelID = try container.decode([Weapon.Buddy.Level.ID: Weapon.Buddy.ID].self, forKey: .buddiesByLevelID)
		self.currencies = try container.decode([Currency.ID: CurrencyInfo].self, forKey: .currencies)
		self.bundles = try container.decode([StoreBundle.Asset.ID: StoreBundleInfo].self, forKey: .bundles)
		self.contentTiers = try container.decode([ContentTier.ID: ContentTier].self, forKey: .contentTiers)
		self.flex = try container.decode([Totem.ID: FlexInfo].self, forKey: .flex)
		self.levelBorders = try container.decode([LevelBorder.ID: LevelBorderInfo].self, forKey: .levelBorders)
		let gamePods = try container.decodeIfPresent([String: String].self, forKey: .gamePods) ?? [:]
		self.gamePods = gamePods
		self.mapsLowercased = Self.buildMapsLowercased(maps)
		self.mapsByShortNameLowercased = Self.buildMapsByShortNameLowercased(maps)
		self.gameModesLowercased = Self.buildGameModesLowercased(gameModes)
		self.gamePodsLowercased = Self.buildGamePodsLowercased(gamePods)
		self.knownNonTacticalMapPathsLowercased = Self.buildNonTacticalPaths(maps)
		self.canonicalMapPathsByShortName = Self.buildCanonicalMapPathsByShortName(maps)
		self.modeFoldersByShortName = Self.buildModeFoldersByShortName(gameModes)
	}
	
	private static func buildMapsLowercased(_ maps: [MapID: MapInfo]) -> [String: MapInfo] {
		Dictionary(maps.values.map { ($0.id.rawValue.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
	}
	
	private static func buildMapsByShortNameLowercased(_ maps: [MapID: MapInfo]) -> [String: MapInfo] {
		Dictionary(
			maps.values.compactMap { info in
				let short = CustomGameConfigs.mapShortName(from: info.id.rawValue).lowercased()
				return short.isEmpty ? nil : (short, info)
			},
			uniquingKeysWith: { first, _ in first }
		)
	}
	
	private static func buildCanonicalMapPathsByShortName(_ maps: [MapID: MapInfo]) -> [String: String] {
		Dictionary(
			maps.values.compactMap { info in
				let raw = info.id.rawValue
				let short = CustomGameConfigs.mapShortName(from: raw).lowercased()
				guard !short.isEmpty, raw.lowercased().hasPrefix("/game/") else { return nil }
				return (short, raw)
			},
			uniquingKeysWith: { first, _ in first }
		)
	}
	
	private static func buildGameModesLowercased(_ gameModes: [GameMode.ID: GameModeInfo]) -> [String: GameModeInfo] {
		Dictionary(gameModes.map { ($0.key.rawValue.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
	}
	
	private static func buildModeFoldersByShortName(_ gameModes: [GameMode.ID: GameModeInfo]) -> [String: String] {
		var result: [String: String] = [:]
		for (modeID, info) in gameModes {
			let folder = modeID.rawValue
			let assetShort = CustomGameConfigs.modeShortName(from: info.assetPath)
			var candidates = [assetShort]
			for suffix in ["_PrimaryAsset", "PrimaryAsset", "_DataAsset_Desktop", "_DataAsset"] {
				if assetShort.lowercased().hasSuffix(suffix.lowercased()) {
					let stripped = String(assetShort.dropLast(suffix.count))
					if !stripped.isEmpty {
						candidates.append(stripped)
						if !stripped.lowercased().contains("gamemode") {
							candidates.append("\(stripped)GameMode")
						}
					}
				}
			}
			for candidate in candidates where !candidate.isEmpty {
				let lower = candidate.lowercased()
				if result[lower] == nil {
					result[lower] = folder
				}
			}
		}
		return result
	}
	
	private static func buildGamePodsLowercased(_ gamePods: [String: String]) -> [String: String] {
		Dictionary(gamePods.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
	}
	
	private static func buildNonTacticalPaths(_ maps: [MapID: MapInfo]) -> Set<String> {
		guard maps.values.contains(where: { $0.tacticalDescription != nil }) else {
			return []
		}
		return Set(maps.values.lazy.filter { $0.tacticalDescription == nil }.map { $0.id.rawValue.lowercased() })
	}
	
	func mapInfo(for path: String) -> MapInfo? {
		guard !path.isEmpty else { return nil }
		if let exact = maps[MapID(path)] ?? mapsLowercased[path.lowercased()] {
			return exact
		}
		let shortLower = CustomGameConfigs.mapShortName(from: path).lowercased()
		return shortLower.isEmpty ? nil : mapsByShortNameLowercased[shortLower]
	}
	
	func customModeDisplayName(for path: String) -> String {
		guard !path.isEmpty else { return String(localized: "Standard") }
		
		let canonicalPath = CustomGameConfigs.canonicalModePath(
			for: path,
			knownModeFoldersByShortName: modeFoldersByShortName
		)
		let lower = canonicalPath.lowercased()
		if let prefixRange = lower.range(of: "/game/gamemodes/") {
			let tail = canonicalPath[prefixRange.upperBound...]
			if let lastSlash = tail.lastIndex(of: "/") {
				let modeKey = String(tail[..<lastSlash])
				if let info = gameModes[GameMode.ID(modeKey)] ?? gameModesLowercased[modeKey.lowercased()] {
					return info.displayName
				}
			}
		}
		
		return Self.fallbackCustomModeDisplayName(for: canonicalPath)
	}
	
	static func fallbackCustomModeDisplayName(for path: String) -> String {
		guard !path.isEmpty else { return String(localized: "Standard") }
		let lower = path.lowercased()
		if lower.contains("quickbomb") { return String(localized: "Spike Rush") }
		if lower.contains("swiftplay") { return String(localized: "Swiftplay") }
		if lower.contains("deathmatch") { return String(localized: "Deathmatch") }
		if lower.contains("gungame") { return String(localized: "Escalation") }
		if lower.contains("oneforall") { return String(localized: "Replication") }
		if lower.contains("hurm") { return String(localized: "Team Deathmatch") }
		if lower.contains("snowball") { return String(localized: "Snowball Fight") }
		if lower.contains("shootingrange") { return String(localized: "Practice Range") }
		if lower.contains("skirmishascension") { return "Skirmish: Ascension" }
		if lower.contains("skirmish") { return "Skirmish" }
		if lower.contains("abilitydraft") || lower.contains("gauntlet") { return "Gauntlet" }
		if lower.contains("aros") { return "All Random One Site" }
		if lower.contains("dodgeball") { return "Knockout" }
		if lower.contains("fortcollins") { return "Retake" }
		if lower.contains("bomb") { return String(localized: "Standard") }
		return path.split(separator: "/").dropFirst(3).first.map(String.init) ?? path
	}
	
	func serverDisplayName(for gamePodID: String) -> String {
		if let exact = gamePods[gamePodID] {
			return exact
		}
		if let matched = gamePodsLowercased[gamePodID.lowercased()] {
			return matched
		}
		if let parsed = MatchAnalytics.parseServerName(from: gamePodID) {
			return parsed
		}
		if let gpRange = gamePodID.range(of: "-gp-") {
			let tail = String(gamePodID[gpRange.upperBound...])
			var tokens = tail.split(separator: "-").map(String.init)
			if tokens.count > 1, Int(tokens.last ?? "") != nil {
				tokens.removeLast()
			}
			if !tokens.isEmpty {
				return tokens.map(\.capitalized).joined(separator: " ")
			}
		}
		return gamePodID
	}
}

/// just a marker at this point, but still handy for expressivity
protocol AssetItem {}

extension Locale {
	static let valorantLanguages: [String] = [
		"ar-AE", // arabic
		"de-DE", // german
		"en-US", // english
		"es-ES", // spanish (european)
		"es-MX", // spanish (latin american)
		"fr-FR", // french
		"id-ID", // indonesian
		"it-IT", // italian
		"ja-JP", // japanese
		"ko-KR", // korean
		"pl-PL", // polish
		"pt-BR", // portuguese (brasilian)
		"ru-RU", // russian
		"th-TH", // thai
		"tr-TR", // turkish
		"vi-VN", // vietnamese
		"zh-CN", // chinese (simplified)
		"zh-TW", // chinese (traditional)
	]
}
