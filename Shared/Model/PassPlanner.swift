import Foundation
import ValorantAPI

struct PassPlanner {
	var totalXPRequired: Int
	var currentXP: Int
	var endDate: Date?
	
	var remainingXP: Int {
		max(0, totalXPRequired - currentXP)
	}
	
	var daysRemaining: Int {
		guard let endDate else { return 0 }
		let seconds = max(TimeInterval(0), endDate.timeIntervalSinceNow)
		return max(1, Int(ceil(seconds / TimeInterval(86400))))
	}
	
	var dailyXPRequired: Int {
		guard remainingXP > 0 else { return 0 }
		let days = max(1, daysRemaining)
		return Int(ceil(Double(remainingXP) / Double(days)))
	}
	
	var dailyXPWithPassBoost: Int {
		// 3% Battle Pass boost estimate when planning daily grind
		dailyXPRequired
	}
	
	struct ModeBreakdown: Identifiable {
		var id: String { name }
		var name: String
		var avgXP: Int
		var totalGamesNeeded: Int
		var gamesPerDay: Double
	}
	
	var breakdowns: [ModeBreakdown] {
		let modes: [(name: String, avgXP: Int)] = [
			("Competitive / Unrated", 4500),
			("Swiftplay", 1600),
			("Team Deathmatch", 1000),
			("Spike Rush", 1000),
			("Deathmatch", 900),
		]
		return modes.map { mode in
			let total = Int(ceil(Double(remainingXP) / Double(mode.avgXP)))
			let perDay = Double(dailyXPRequired) / Double(mode.avgXP)
			return ModeBreakdown(
				name: mode.name,
				avgXP: mode.avgXP,
				totalGamesNeeded: total,
				gamesPerDay: perDay
			)
		}
	}
	
	static func totalXP(for contract: ContractInfo, includeEpilogue: Bool) -> Int {
		let chapters = includeEpilogue
			? contract.content.chapters
			: contract.content.chapters.filter { !$0.isEpilogue }
		return chapters
			.flatMap(\.levels)
			.reduce(0) { $0 + $1.xp }
	}
	
	static func levelProgress(
		contract: ContractInfo,
		details: Contract?,
		includeEpilogue: Bool = true
	) -> (currentLevel: Int, totalLevels: Int, levelXP: Int, levelTotalXP: Int, earnedXP: Int, totalXP: Int) {
		let chapters = includeEpilogue
			? contract.content.chapters
			: contract.content.chapters.filter { !$0.isEpilogue }
		let levels = chapters.flatMap(\.levels)
		let totalLevels = levels.count
		let totalXP = levels.reduce(0) { $0 + $1.xp }
		
		let reached = details?.levelReached ?? 0
		let towardsNext = details?.progressionTowardsNextLevel ?? 0
		let earnedBefore = levels.prefix(min(reached, levels.count)).reduce(0) { $0 + $1.xp }
		let earnedXP = min(totalXP, max(details?.progression.totalEarned ?? (earnedBefore + towardsNext), earnedBefore + towardsNext))
		
		let currentLevelXP = reached < levels.count ? levels[reached].xp : (levels.last?.xp ?? 0)
		let xpInLevel = reached < levels.count ? towardsNext : currentLevelXP
		
		return (
			currentLevel: min(reached, totalLevels),
			totalLevels: totalLevels,
			levelXP: xpInLevel,
			levelTotalXP: max(1, currentLevelXP),
			earnedXP: earnedXP,
			totalXP: max(1, totalXP)
		)
	}
}
