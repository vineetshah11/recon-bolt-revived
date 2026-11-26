import Foundation
import ValorantAPI

struct AgentMasterySummary: Identifiable {
	var id: Agent.ID { agentID }
	var agentID: Agent.ID
	var displayName: String
	var roleName: String?
	var currentActLevel: Int
	var currentActMP: Int
	var xpInCurrentLevel: Int
	var nextLevelMPNeeded: Int
	var lastActLevel: Int
	var lifetimeLevel: Int
	var matchesPlayed: Int
	var wins: Int
	var kills: Int
	var deaths: Int
	var totalScore: Int
	var totalRounds: Int
	var isLiveRiotData: Bool
	
	var winRate: Double {
		matchesPlayed > 0 ? Double(wins) / Double(matchesPlayed) : 0
	}
	
	var averageACS: Int {
		totalRounds > 0 ? totalScore / totalRounds : 0
	}
	
	var kdRatio: Double {
		deaths > 0 ? Double(kills) / Double(deaths) : Double(kills)
	}
	
	var levelProgress: Double {
		guard nextLevelMPNeeded > 0 else { return 1 }
		return min(1, max(0, Double(xpInCurrentLevel) / Double(nextLevelMPNeeded)))
	}
	
	var hasMasteryActivity: Bool {
		currentActLevel > 0 || currentActMP > 0 || lastActLevel > 0 || lifetimeLevel > 0
	}
}

struct AgentMasteryPortraitMilestone: Identifiable {
	var id: Int { level }
	var level: Int
	var cumulativeMP: Int
}

struct AgentMasteryRewardItem: Identifiable {
	var id: String { "\(title)-\(costKC)-\(iconName)" }
	var title: String
	var costKC: Int
	var iconName: String
}

struct AgentMasteryRewardTier: Identifiable {
	var id: Int { level }
	var level: Int
	var items: [AgentMasteryRewardItem]
}

enum AgentMasteryCalculator {
	/// Cumulative Mastery Points required for Act Levels 0...10 (Patch 13.06).
	static let cumulativeLevelThresholds: [Int] = [
		0,       // Level 0
		2_000,   // Level 1 (+2,000)
		10_500,  // Level 2 (+8,500)
		19_800,  // Level 3 (+9,300)
		30_300,  // Level 4 (+10,500)
		42_300,  // Level 5 (+12,000)
		56_100,  // Level 6 (+13,800)
		71_900,  // Level 7 (+15,800)
		89_800,  // Level 8 (+17,900)
		109_900, // Level 9 (+20,100)
		132_400  // Level 10 (+22,500)
	]
	
	static let overlevelStepMP = 22_500
	
	static let portraitUpgradeMilestones: [AgentMasteryPortraitMilestone] = [
		.init(level: 1, cumulativeMP: 2_000),
		.init(level: 4, cumulativeMP: 30_300),
		.init(level: 7, cumulativeMP: 71_900),
		.init(level: 10, cumulativeMP: 132_400),
	]
	
	static let rewardTrackTiers: [AgentMasteryRewardTier] = [
		.init(level: 5, items: [
			.init(title: "Spray", costKC: 4_000, iconName: "paintbrush.pointed"),
			.init(title: "Player Title", costKC: 2_500, iconName: "textformat"),
			.init(title: "Player Card", costKC: 4_500, iconName: "person.text.rectangle"),
			.init(title: "Stat: K/D", costKC: 2_500, iconName: "number"),
			.init(title: "Quote", costKC: 5_000, iconName: "text.bubble"),
		]),
		.init(level: 10, items: [
			.init(title: "Stat: MVPs", costKC: 2_500, iconName: "number"),
			.init(title: "Frame II", costKC: 2_500, iconName: "photo"),
			.init(title: "Stat: Headshots", costKC: 2_500, iconName: "number"),
			.init(title: "Role Background", costKC: 6_000, iconName: "photo.on.rectangle"),
			.init(title: "Player Card", costKC: 4_500, iconName: "person.text.rectangle"),
		]),
		.init(level: 15, items: [
			.init(title: "Sidearm Skin", costKC: 8_000, iconName: "paintpalette"),
			.init(title: "Quote", costKC: 5_000, iconName: "text.bubble"),
			.init(title: "Spray", costKC: 4_000, iconName: "paintbrush.pointed"),
			.init(title: "Stat: First Bloods", costKC: 2_500, iconName: "number"),
		]),
		.init(level: 20, items: [
			.init(title: "Gun Buddy", costKC: 5_500, iconName: "teddybear"),
			.init(title: "Stat: Win Rate", costKC: 2_500, iconName: "number"),
			.init(title: "Player Title", costKC: 2_500, iconName: "textformat"),
			.init(title: "VALORANT Background", costKC: 6_000, iconName: "photo.on.rectangle"),
			.init(title: "Frame III", costKC: 5_000, iconName: "photo"),
		]),
		.init(level: 25, items: [
			.init(title: "Spray", costKC: 4_000, iconName: "paintbrush.pointed"),
			.init(title: "Stat: Clutches", costKC: 2_500, iconName: "number"),
			.init(title: "Lore Background", costKC: 6_000, iconName: "photo.on.rectangle"),
			.init(title: "Agent Pose", costKC: 7_500, iconName: "figure.stand"),
		]),
		.init(level: 30, items: [
			.init(title: "Player Title", costKC: 2_500, iconName: "textformat"),
			.init(title: "Quote", costKC: 5_000, iconName: "text.bubble"),
			.init(title: "Stat: Aces", costKC: 2_500, iconName: "number"),
			.init(title: "Animated Mastery Card", costKC: 7_500, iconName: "play.rectangle"),
			.init(title: "Frame IV", costKC: 7_500, iconName: "photo"),
		]),
	]
	
	static func cumulativeMP(forLevel level: Int) -> Int {
		guard level > 0 else { return 0 }
		if level < cumulativeLevelThresholds.count {
			return cumulativeLevelThresholds[level]
		}
		return cumulativeLevelThresholds.last! + (level - (cumulativeLevelThresholds.count - 1)) * overlevelStepMP
	}
	
	static func stepMP(fromLevel level: Int) -> Int {
		let next = cumulativeMP(forLevel: level + 1)
		let cur = cumulativeMP(forLevel: max(0, level))
		return max(1, next - cur)
	}
	
	static func actLevelAndProgress(for mp: Int) -> (level: Int, inLevel: Int, toNext: Int) {
		var level = 0
		for i in 1..<cumulativeLevelThresholds.count {
			if mp >= cumulativeLevelThresholds[i] {
				level = i
			} else {
				break
			}
		}
		if level >= cumulativeLevelThresholds.count - 1 {
			let overXP = mp - cumulativeLevelThresholds.last!
			let extraLevels = max(0, overXP / overlevelStepMP)
			let resolvedLevel = (cumulativeLevelThresholds.count - 1) + extraLevels
			let inLevel = overXP % overlevelStepMP
			return (resolvedLevel, inLevel, overlevelStepMP)
		}
		let currentFloor = cumulativeLevelThresholds[level]
		let nextFloor = cumulativeLevelThresholds[level + 1]
		return (level, max(0, mp - currentFloor), max(1, nextFloor - currentFloor))
	}
	
	static func buildFromRiot(
		_ mastery: AgentMastery?,
		userID: User.ID?,
		matches: [MatchDetails],
		assets: AssetCollection?,
		contractsDetails: ContractDetails?,
		currentAct: Act?,
		previousAct: Act?
	) -> [AgentMasterySummary] {
		let fallback = compute(
			userID: userID ?? User.ID(),
			matches: userID == nil ? [] : matches,
			assets: assets,
			contractsDetails: contractsDetails,
			currentAct: currentAct,
			previousAct: previousAct
		)
		guard let mastery, !mastery.bonsais.isEmpty else {
			return fallback
		}
		
		let fallbackByID = Dictionary(uniqueKeysWithValues: fallback.map { ($0.agentID, $0) })
		let entryByID = Dictionary(uniqueKeysWithValues: mastery.bonsais.map { ($0.id, $0) })
		
		let agentIDs: [Agent.ID] = {
			if let assets {
				return assets.agents.values
					.filter { $0.isPlayableCharacter && $0.id != .abilityDraftAgent }
					.map(\.id)
			}
			return mastery.bonsais.map(\.id)
		}()
		
		return agentIDs.compactMap { agentID -> AgentMasterySummary? in
			let agentInfo = assets?.agents[agentID]
			let stat = fallbackByID[agentID]
			let entry = entryByID[agentID]
			let flourish = entry?.flourish
			
			let actLevel = flourish?.shortLevel ?? 0
			let prevLevel = flourish?.previousShortLevel ?? 0
			let lifetime = max(
				flourish?.longLevel ?? 0,
				entry?.trackProgressList.first?.trackLevel ?? 0
			)
			let rawPoints = flourish?.points ?? 0
			let stepNeeded = stepMP(fromLevel: actLevel)
			let floorMP = cumulativeMP(forLevel: actLevel)
			
			let inLevel: Int
			let totalActMP: Int
			if actLevel > 0 {
				if rawPoints >= floorMP {
					inLevel = min(stepNeeded, rawPoints - floorMP)
					totalActMP = rawPoints
				} else if rawPoints > 0 {
					inLevel = min(stepNeeded, rawPoints)
					totalActMP = floorMP + inLevel
				} else {
					let estInLevel = max(0, (stat?.currentActMP ?? 0) - floorMP)
					inLevel = min(stepNeeded, estInLevel)
					totalActMP = floorMP + inLevel
				}
			} else {
				inLevel = min(stepNeeded, rawPoints > 0 ? rawPoints : (stat?.currentActMP ?? 0))
				totalActMP = inLevel
			}
			
			return AgentMasterySummary(
				agentID: agentID,
				displayName: agentInfo?.displayName ?? stat?.displayName ?? "Agent",
				roleName: agentInfo?.role?.displayName,
				currentActLevel: actLevel,
				currentActMP: totalActMP,
				xpInCurrentLevel: inLevel,
				nextLevelMPNeeded: stepNeeded,
				lastActLevel: prevLevel,
				lifetimeLevel: lifetime,
				matchesPlayed: stat?.matchesPlayed ?? 0,
				wins: stat?.wins ?? 0,
				kills: stat?.kills ?? 0,
				deaths: stat?.deaths ?? 0,
				totalScore: stat?.totalScore ?? 0,
				totalRounds: stat?.totalRounds ?? 0,
				isLiveRiotData: true
			)
		}
		.sorted(by: sortComparator)
	}
	
	static func masteryPoints(for player: Player, in match: MatchDetails, won: Bool) -> Int {
		guard let stats = player.stats else { return 0 }
		let rounds = max(1, stats.roundsPlayed)
		let acs = Double(stats.score) / Double(rounds)
		let basePerRound = won ? Double(115) : Double(65)
		let raw = Double(rounds) * basePerRound
			+ acs * Double(1.4)
			+ Double(stats.kills * 18 + stats.assists * 10)
			+ (won ? Double(350) : Double(0))
		
		let modeMultiplier: Double
		switch match.matchInfo.queueID {
		case .competitive:
			modeMultiplier = 1.05
		case .unrated:
			modeMultiplier = 1.0
		case .swiftplay, .spikeRush:
			modeMultiplier = 0.85
		case .deathmatch:
			modeMultiplier = 0.55
		default:
			modeMultiplier = 0.9
		}
		return max(120, Int((raw * modeMultiplier).rounded()))
	}
	
	static func compute(
		userID: User.ID,
		matches: [MatchDetails],
		assets: AssetCollection?,
		contractsDetails: ContractDetails?,
		currentAct: Act?,
		previousAct: Act?
	) -> [AgentMasterySummary] {
		var currentActMP: [Agent.ID: Int] = [:]
		var lastActMP: [Agent.ID: Int] = [:]
		var historicalActsMP: [Season.ID: [Agent.ID: Int]] = [:]
		var totalMatches: [Agent.ID: Int] = [:]
		var totalWins: [Agent.ID: Int] = [:]
		var totalKills: [Agent.ID: Int] = [:]
		var totalDeaths: [Agent.ID: Int] = [:]
		var totalScore: [Agent.ID: Int] = [:]
		var totalRounds: [Agent.ID: Int] = [:]
		
		let fallbackAct = currentAct ?? assets?.seasons.actsInOrder.last
		let prevAct = previousAct ?? assets?.seasons.actBefore(fallbackAct)
		
		for match in matches {
			guard
				let player = match.players.firstElement(withID: userID),
				let agentID = player.agentID,
				agentID != .abilityDraftAgent
			else { continue }
			
			let won = match.teams.first(where: { $0.id == player.teamID })?.won == true
			let mp = masteryPoints(for: player, in: match, won: won)
			let start = match.matchInfo.gameStart
			
			totalMatches[agentID, default: 0] += 1
			if won { totalWins[agentID, default: 0] += 1 }
			if let stats = player.stats {
				totalKills[agentID, default: 0] += stats.kills
				totalDeaths[agentID, default: 0] += stats.deaths
				totalScore[agentID, default: 0] += stats.score
				totalRounds[agentID, default: 0] += stats.roundsPlayed
			}
			
			if let fallbackAct, fallbackAct.timeSpan.contains(start) {
				currentActMP[agentID, default: 0] += mp
			} else if let prevAct, prevAct.timeSpan.contains(start) {
				lastActMP[agentID, default: 0] += mp
			} else {
				let seasonID = match.matchInfo.seasonID
				historicalActsMP[seasonID, default: [:]][agentID, default: 0] += mp
			}
		}
		
		var contractLaurelBaseline: [Agent.ID: Int] = [:]
		if let contractsDetails, let assets {
			for contract in contractsDetails.contracts {
				guard let info = assets.contracts[contract.id], let agentID = info.content.agentID else { continue }
				let levels = max(0, contract.levelReached)
				if levels > 0 {
					contractLaurelBaseline[agentID] = min(3, max(1, levels / 4))
				}
			}
		}
		
		let allAgentIDs: Set<Agent.ID> = {
			let playable = assets?.agents.values.filter { $0.isPlayableCharacter && $0.id != .abilityDraftAgent }.map(\.id) ?? []
			return Set(playable).union(totalMatches.keys).union(contractLaurelBaseline.keys)
		}()
		
		let summaries: [AgentMasterySummary] = allAgentIDs.compactMap { agentID in
			guard let agentInfo = assets?.agents[agentID] else { return nil }
			let curMP = currentActMP[agentID, default: 0]
			let cur = actLevelAndProgress(for: curMP)
			let prev = actLevelAndProgress(for: lastActMP[agentID, default: 0]).level
			
			var otherActsSum = 0
			for (_, map) in historicalActsMP {
				otherActsSum += actLevelAndProgress(for: map[agentID, default: 0]).level
			}
			let actLevelsSum = cur.level + prev + otherActsSum
			let lifetime = max(actLevelsSum, contractLaurelBaseline[agentID, default: 0])
			
			return AgentMasterySummary(
				agentID: agentID,
				displayName: agentInfo.displayName,
				roleName: agentInfo.role?.displayName,
				currentActLevel: cur.level,
				currentActMP: curMP,
				xpInCurrentLevel: cur.inLevel,
				nextLevelMPNeeded: cur.toNext,
				lastActLevel: prev,
				lifetimeLevel: lifetime,
				matchesPlayed: totalMatches[agentID, default: 0],
				wins: totalWins[agentID, default: 0],
				kills: totalKills[agentID, default: 0],
				deaths: totalDeaths[agentID, default: 0],
				totalScore: totalScore[agentID, default: 0],
				totalRounds: totalRounds[agentID, default: 0],
				isLiveRiotData: false
			)
		}
		
		return summaries.sorted(by: sortComparator)
	}
	
	private static func sortComparator(_ lhs: AgentMasterySummary, _ rhs: AgentMasterySummary) -> Bool {
		if lhs.lifetimeLevel != rhs.lifetimeLevel {
			return lhs.lifetimeLevel > rhs.lifetimeLevel
		}
		if lhs.currentActLevel != rhs.currentActLevel {
			return lhs.currentActLevel > rhs.currentActLevel
		}
		if lhs.currentActMP != rhs.currentActMP {
			return lhs.currentActMP > rhs.currentActMP
		}
		if lhs.lastActLevel != rhs.lastActLevel {
			return lhs.lastActLevel > rhs.lastActLevel
		}
		return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
	}
}
