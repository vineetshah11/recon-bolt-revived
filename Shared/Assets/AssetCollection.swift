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
		self.maps = try container.decode([MapID: MapInfo].self, forKey: .maps)
		self.agents = try container.decode([Agent.ID: AgentInfo].self, forKey: .agents)
		self.missions = try container.decode([Mission.ID: MissionInfo].self, forKey: .missions)
		self.contracts = try container.decode([Contract.ID: ContractInfo].self, forKey: .contracts)
		self.gameModes = try container.decode([GameMode.ID: GameModeInfo].self, forKey: .gameModes)
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
		self.gamePods = try container.decodeIfPresent([String: String].self, forKey: .gamePods) ?? [:]
	}
	
	func serverDisplayName(for gamePodID: String) -> String {
		if let exact = gamePods[gamePodID] {
			return exact
		}
		if let matched = gamePods.first(where: { $0.key.caseInsensitiveCompare(gamePodID) == .orderedSame })?.value {
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
