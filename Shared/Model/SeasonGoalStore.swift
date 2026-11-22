import Foundation
import ValorantAPI

struct SeasonGoal: Identifiable, Codable, Equatable {
	var id = UUID()
	var accountID: User.ID?
	var seasonID: Season.ID?
	var kind: Kind
	var createdAt = Date()
	
	enum Kind: Codable, Equatable, Hashable {
		case targetRank(tier: Int, rr: Int)
		case winRate(percent: Double)
		case matchesPlayed(count: Int)
		case kdRatio(target: Double)
		case headshotRate(percent: Double)
		
		var title: String {
			switch self {
			case .targetRank:
				return "Target Rank"
			case .winRate:
				return "Win Rate"
			case .matchesPlayed:
				return "Matches Played"
			case .kdRatio:
				return "K/D Ratio"
			case .headshotRate:
				return "Headshot %"
			}
		}
		
		var iconName: String {
			switch self {
			case .targetRank:
				return "shield.lefthalf.filled"
			case .winRate:
				return "trophy.fill"
			case .matchesPlayed:
				return "gamecontroller.fill"
			case .kdRatio:
				return "scope"
			case .headshotRate:
				return "target"
			}
		}
	}
}

struct SeasonGoalProgress {
	var currentValueText: String
	var targetValueText: String
	var progress: Double // 0...1
	var isCompleted: Bool
}

@MainActor
final class SeasonGoalStore: ObservableObject {
	@Published var goals: [SeasonGoal] = []
	
	private let filename = "SeasonGoals.v1.json"
	
	init() {
		goals = LocalJSONStore.load([SeasonGoal].self, from: filename) ?? []
	}
	
	func goals(for accountID: User.ID?, seasonID: Season.ID? = nil) -> [SeasonGoal] {
		goals.filter { goal in
			let matchAccount = goal.accountID == nil || accountID == nil || goal.accountID == accountID
			let matchSeason = seasonID == nil || goal.seasonID == nil || goal.seasonID == seasonID
			return matchAccount && matchSeason
		}
		.sorted { $0.createdAt > $1.createdAt }
	}
	
	func addGoal(accountID: User.ID?, seasonID: Season.ID?, kind: SeasonGoal.Kind) {
		let goal = SeasonGoal(accountID: accountID, seasonID: seasonID, kind: kind)
		goals.insert(goal, at: 0)
		persist()
	}
	
	func delete(id: UUID) {
		goals.removeAll { $0.id == id }
		persist()
	}
	
	private func persist() {
		LocalJSONStore.save(goals, to: filename)
	}
	
	static func evaluate(
		_ goal: SeasonGoal,
		userID: User.ID,
		summary: CareerSummary?,
		matches: [MatchDetails],
		assets: AssetCollection?,
		currentAct: Act?
	) -> SeasonGoalProgress {
		let seasonID = goal.seasonID ?? currentAct?.id
		let seasonInfo = seasonID.flatMap { summary?.competitiveInfo?.bySeason?[$0] }
		let filteredMatches: [MatchDetails] = {
			guard let act = seasonID.flatMap({ assets?.seasons.acts[$0] }) ?? currentAct else {
				return matches
			}
			return matches.filter { act.timeSpan.contains($0.matchInfo.gameStart) }
		}()
		
		switch goal.kind {
		case let .targetRank(targetTier, targetRR):
			let currentTier = seasonInfo?.competitiveTier ?? summary?.latestUpdate?.tierAfterUpdate ?? 0
			let currentRR = seasonInfo?.rankedRating ?? summary?.latestUpdate?.tierProgressAfterUpdate ?? 0
			let actForTiers = currentAct ?? assets?.seasons.actsInOrder.last
			let tiers = actForTiers.flatMap { assets?.seasons.competitiveTiers[$0.competitiveTiers] }
			let currentName = tiers?.tier(currentTier)?.name ?? "Unranked"
			let targetName = tiers?.tier(targetTier)?.name ?? "Tier \(targetTier)"
			
			let currentScore: Double = Double(currentTier * 100 + min(currentRR, 99))
			let targetScore: Double = Double(targetTier * 100 + targetRR)
			let ratio: Double = targetScore > 0 ? min(1, max(0, currentScore / targetScore)) : 0
			let done = currentTier > targetTier || (currentTier == targetTier && currentRR >= targetRR)
			
			return SeasonGoalProgress(
				currentValueText: "\(currentName) (\(currentRR) RR)",
				targetValueText: targetRR > 0 ? "\(targetName) (\(targetRR) RR)" : targetName,
				progress: done ? 1 : ratio,
				isCompleted: done
			)
			
		case let .winRate(percent):
			let wins = seasonInfo?.winCount ?? filteredMatches.filter { match in
				guard let player = match.players.firstElement(withID: userID) else { return false }
				return match.teams.first(where: { $0.id == player.teamID })?.won == true
			}.count
			let games = seasonInfo?.gameCount ?? filteredMatches.count
			let currentWR: Double = games > 0 ? Double(wins) * Double(100) / Double(games) : 0
			let ratio: Double = percent > 0 ? min(1, max(0, currentWR / percent)) : 0
			return SeasonGoalProgress(
				currentValueText: String(format: "%.1f%% (%d/%d)", currentWR, wins, games),
				targetValueText: String(format: "%.0f%%", percent),
				progress: ratio,
				isCompleted: currentWR >= percent && games > 0
			)
			
		case let .matchesPlayed(count):
			let played = max(seasonInfo?.gameCount ?? 0, filteredMatches.count)
			let ratio: Double = count > 0 ? min(1, Double(played) / Double(count)) : 0
			return SeasonGoalProgress(
				currentValueText: "\(played) matches",
				targetValueText: "\(count) matches",
				progress: ratio,
				isCompleted: played >= count
			)
			
		case let .kdRatio(target):
			var kills = 0
			var deaths = 0
			for match in filteredMatches {
				guard let stats = match.players.firstElement(withID: userID)?.stats else { continue }
				kills += stats.kills
				deaths += stats.deaths
			}
			let kd: Double = deaths > 0 ? Double(kills) / Double(deaths) : Double(kills)
			let ratio: Double = target > 0 ? min(1, max(0, kd / target)) : 0
			return SeasonGoalProgress(
				currentValueText: String(format: "%.2f K/D", kd),
				targetValueText: String(format: "%.2f K/D", target),
				progress: ratio,
				isCompleted: kd >= target && !filteredMatches.isEmpty
			)
			
		case let .headshotRate(percent):
			var head = 0
			var total = 0
			for match in filteredMatches {
				for round in match.roundResults {
					guard let stats = round.stats(for: userID) else { continue }
					for dmg in stats.damageDealt {
						head += dmg.headshots
						total += dmg.headshots + dmg.bodyshots + dmg.legshots
					}
				}
			}
			let hs: Double = total > 0 ? Double(head) * Double(100) / Double(total) : 0
			let ratio: Double = percent > 0 ? min(1, max(0, hs / percent)) : 0
			return SeasonGoalProgress(
				currentValueText: String(format: "%.1f%%", hs),
				targetValueText: String(format: "%.0f%%", percent),
				progress: ratio,
				isCompleted: hs >= percent && total > 0
			)
		}
	}
}
