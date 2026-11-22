import Foundation
import ValorantAPI

struct AgentMasterySummary: Identifiable {
	var id: Agent.ID { agentID }
	var agentID: Agent.ID
	var displayName: String
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
}

enum AgentMasteryCalculator {
	/// Cumulative MP thresholds for Act Mastery Levels 1...10 (matches Patch 13.06: L1 = 2,000 MP, L2 = +8,500 MP).
	static let cumulativeLevelThresholds: [Int] = [
		0,      // Level 0
		2_000,  // Level 1 (initial unlock)
		10_500, // Level 2 (+8,500 MP)
		20_500, // Level 3 (+10,000 MP)
		32_500, // Level 4 (+12,000 MP)
		46_500, // Level 5 (+14,000 MP)
		62_500, // Level 6 (+16,000 MP)
		80_500, // Level 7 (+18,000 MP)
		100_500,// Level 8 (+20,000 MP)
		122_500,// Level 9 (+22,000 MP)
		147_500 // Level 10 (+25,000 MP)
	]
	
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
			let step = cumulativeLevelThresholds.last! - cumulativeLevelThresholds[cumulativeLevelThresholds.count - 2]
			return (level, step, step)
		}
		let currentFloor = cumulativeLevelThresholds[level]
		let nextFloor = cumulativeLevelThresholds[level + 1]
		return (level, mp - currentFloor, nextFloor - currentFloor)
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
		
		// Legacy agent contract level baseline contributes to Lifetime Laurel when match history isn't full
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
		
		let allAgentIDs = Set(assets?.agents.keys.map { $0 } ?? [])
			.union(totalMatches.keys)
			.union(contractLaurelBaseline.keys)
		
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
				totalRounds: totalRounds[agentID, default: 0]
			)
		}
		
		return summaries.sorted { lhs, rhs in
			if lhs.currentActLevel != rhs.currentActLevel {
				return lhs.currentActLevel > rhs.currentActLevel
			}
			if lhs.currentActMP != rhs.currentActMP {
				return lhs.currentActMP > rhs.currentActMP
			}
			if lhs.lastActLevel != rhs.lastActLevel {
				return lhs.lastActLevel > rhs.lastActLevel
			}
			if lhs.lifetimeLevel != rhs.lifetimeLevel {
				return lhs.lifetimeLevel > rhs.lifetimeLevel
			}
			return lhs.displayName < rhs.displayName
		}
	}
}
