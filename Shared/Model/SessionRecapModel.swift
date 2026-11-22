import Foundation
import ValorantAPI

struct SessionMatchItem: Identifiable {
	var id: Match.ID { details.id }
	var details: MatchDetails
	var update: CompetitiveUpdate?
}

struct PlaySession: Identifiable {
	var id: Date { startTime }
	var startTime: Date
	var endTime: Date
	var items: [SessionMatchItem]
	var wins: Int
	var losses: Int
	var draws: Int
	var netRRDelta: Int
	var totalKills: Int
	var totalDeaths: Int
	var totalAssists: Int
	var totalScore: Int
	var totalRounds: Int
	var headshots: Int
	var totalHits: Int
	var topAgentID: Agent.ID?
	
	var averageACS: Int {
		totalRounds > 0 ? totalScore / totalRounds : 0
	}
	
	var kdRatio: Double {
		totalDeaths > 0 ? Double(totalKills) / Double(totalDeaths) : Double(totalKills)
	}
	
	var headshotPercentage: Double {
		totalHits > 0 ? Double(headshots) * Double(100) / Double(totalHits) : 0
	}
}

enum SessionRecapBuilder {
	/// Groups matches separated by <= 3 hours into coherent play sessions.
	static func buildSessions(
		userID: User.ID,
		matches: [CompetitiveUpdate],
		detailsByID: [Match.ID: MatchDetails],
		maxGap: TimeInterval = 3 * 3600
	) -> [PlaySession] {
		let resolved: [SessionMatchItem] = matches.compactMap { update in
			guard let details = detailsByID[update.id] else { return nil }
			return SessionMatchItem(details: details, update: update)
		}
		.sorted { $0.details.matchInfo.gameStart > $1.details.matchInfo.gameStart }
		
		guard !resolved.isEmpty else { return [] }
		
		var groups: [[SessionMatchItem]] = []
		var currentGroup: [SessionMatchItem] = []
		
		for item in resolved {
			if let previous = currentGroup.last {
				let gap = previous.details.matchInfo.gameStart.timeIntervalSince(item.details.matchInfo.gameStart)
				if gap > maxGap {
					groups.append(currentGroup)
					currentGroup = [item]
				} else {
					currentGroup.append(item)
				}
			} else {
				currentGroup = [item]
			}
		}
		if !currentGroup.isEmpty {
			groups.append(currentGroup)
		}
		
		return groups.map { group in
			var wins = 0
			var losses = 0
			var draws = 0
			var netRR = 0
			var kills = 0
			var deaths = 0
			var assists = 0
			var score = 0
			var rounds = 0
			var head = 0
			var hits = 0
			var agentCounts: [Agent.ID: Int] = [:]
			
			for item in group {
				let match = item.details
				if let player = match.players.firstElement(withID: userID) {
					if let agentID = player.agentID {
						agentCounts[agentID, default: 0] += 1
					}
					if let winner = match.teams.first(where: \.won) {
						if winner.id == player.teamID {
							wins += 1
						} else {
							losses += 1
						}
					} else {
						draws += 1
					}
					if let s = player.stats {
						kills += s.kills
						deaths += s.deaths
						assists += s.assists
						score += s.score
						rounds += s.roundsPlayed
					}
				}
				if let upd = item.update {
					netRR += upd.ratingEarned
				}
				for round in match.roundResults {
					guard let ps = round.stats(for: userID) else { continue }
					for d in ps.damageDealt {
						head += d.headshots
						hits += d.headshots + d.bodyshots + d.legshots
					}
				}
			}
			
			let start = group.last!.details.matchInfo.gameStart
			let firstEnd = group.first!.details.matchInfo.gameStart.addingTimeInterval(group.first!.details.matchInfo.gameLength)
			let topAgent = agentCounts.max { $0.value < $1.value }?.key
			
			return PlaySession(
				startTime: start,
				endTime: firstEnd,
				items: group,
				wins: wins,
				losses: losses,
				draws: draws,
				netRRDelta: netRR,
				totalKills: kills,
				totalDeaths: deaths,
				totalAssists: assists,
				totalScore: score,
				totalRounds: rounds,
				headshots: head,
				totalHits: hits,
				topAgentID: topAgent
			)
		}
	}
}
