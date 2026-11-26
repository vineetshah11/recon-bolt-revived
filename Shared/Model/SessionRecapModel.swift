import Foundation
import ValorantAPI

struct SessionMatchItem: Identifiable {
	var id: Match.ID { details.id }
	var details: MatchDetails
	var update: CompetitiveUpdate?
}

struct SessionHighlight: Identifiable, Hashable {
	var id: String { label }
	var label: String
	var count: Int
	var priority: Int
	
	var pillText: String {
		count > 1 ? "\(label) ×\(count)" : label
	}
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
	var totalDamage: Int
	var totalRounds: Int
	var headshots: Int
	var totalHits: Int
	var topAgentID: Agent.ID?
	var topAgentMatches: Int
	var topAgentWins: Int
	var topMapID: MapID?
	var topMapMatches: Int
	var topMapWins: Int
	var primaryQueueID: QueueID?
	var isMixedQueues: Bool
	var hasRankedMatches: Bool
	var highlights: [SessionHighlight]
	
	var averageACS: Int {
		totalRounds > 0 ? totalScore / totalRounds : 0
	}
	
	var averageADR: Int {
		totalRounds > 0 ? totalDamage / totalRounds : 0
	}
	
	var winRate: Double {
		let decided = wins + losses
		return decided > 0 ? Double(wins) * Double(100) / Double(decided) : Double(0)
	}
	
	var kdRatio: Double {
		totalDeaths > 0 ? Double(totalKills) / Double(totalDeaths) : Double(totalKills)
	}
	
	var headshotPercentage: Double {
		totalHits > 0 ? Double(headshots) * Double(100) / Double(totalHits) : Double(0)
	}
}

enum SessionRecapBuilder {
	struct LatestSessionPreview: Equatable {
		var startTime: Date
		var matchCount: Int
		var netRRDelta: Int
	}
	
	/// Lightweight preview for the MatchListView card without building full `MatchAnalytics`.
	static func latestSessionPreview(
		matches: [CompetitiveUpdate],
		detailsByID: [Match.ID: MatchDetails],
		maxGap: TimeInterval = 3 * 3600
	) -> LatestSessionPreview? {
		let resolved: [SessionMatchItem] = matches.compactMap { update in
			guard let details = detailsByID[update.id] else { return nil }
			return SessionMatchItem(details: details, update: update)
		}
		.sorted { $0.details.matchInfo.gameStart > $1.details.matchInfo.gameStart }
		
		guard let first = resolved.first else { return nil }
		var previousStart = first.details.matchInfo.gameStart
		var oldestStart = previousStart
		var count = 1
		var netRR = first.update?.ratingEarned ?? 0
		
		for item in resolved.dropFirst() {
			let currentStart = item.details.matchInfo.gameStart
			if previousStart.timeIntervalSince(currentStart) > maxGap {
				break
			}
			count += 1
			netRR += item.update?.ratingEarned ?? 0
			previousStart = currentStart
			oldestStart = currentStart
		}
		
		return LatestSessionPreview(startTime: oldestStart, matchCount: count, netRRDelta: netRR)
	}
	
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
			var hasRanked = false
			var kills = 0
			var deaths = 0
			var assists = 0
			var score = 0
			var damage = 0
			var rounds = 0
			var head = 0
			var hits = 0
			
			var agentCounts: [Agent.ID: Int] = [:]
			var agentWins: [Agent.ID: Int] = [:]
			var mapCounts: [MapID: Int] = [:]
			var mapWins: [MapID: Int] = [:]
			var queueCounts: [QueueID: Int] = [:]
			
			var aces = 0
			var quadras = 0
			var triples = 0
			var matchMVPs = 0
			var teamMVPs = 0
			var clutchesByEnemies: [Int: Int] = [:]
			
			for item in group {
				let match = item.details
				let analytics = MatchAnalytics(details: match)
				let pStats = analytics.byPlayer[userID]
				let mapID = match.matchInfo.mapID
				mapCounts[mapID, default: 0] += 1
				
				if let q = match.matchInfo.queueID {
					queueCounts[q, default: 0] += 1
				}
				if match.matchInfo.isRanked == true || item.update?.isRanked == true {
					hasRanked = true
				}
				if let upd = item.update {
					netRR += upd.ratingEarned
				}
				
				var wonMatch = false
				if let player = match.players.firstElement(withID: userID) {
					if let winner = match.teams.first(where: \.won) {
						if winner.id == player.teamID {
							wins += 1
							wonMatch = true
							mapWins[mapID, default: 0] += 1
						} else {
							losses += 1
						}
					} else {
						draws += 1
					}
					
					if let agentID = player.agentID {
						agentCounts[agentID, default: 0] += 1
						if wonMatch {
							agentWins[agentID, default: 0] += 1
						}
					}
					
					if let s = player.stats {
						kills += s.kills
						deaths += s.deaths
						assists += s.assists
						score += s.score
						rounds += s.roundsPlayed
					}
					
					if analytics.matchMVPID == userID {
						matchMVPs += 1
					} else if analytics.teamMVPByTeam[player.teamID] == userID {
						teamMVPs += 1
					}
				}
				
				if let pStats {
					damage += pStats.totalDamage
					head += pStats.headshots
					hits += pStats.headshots + pStats.bodyshots + pStats.legshots
					aces += pStats.multiKills[5, default: 0]
					quadras += pStats.multiKills[4, default: 0]
					triples += pStats.multiKills[3, default: 0]
					for (enemyCount, c) in pStats.clutchWonSizes {
						clutchesByEnemies[enemyCount, default: 0] += c
					}
				} else {
					for round in match.roundResults {
						guard let ps = round.stats(for: userID) else { continue }
						for d in ps.damageDealt {
							damage += d.damage
							head += d.headshots
							hits += d.headshots + d.bodyshots + d.legshots
						}
					}
				}
			}
			
			let start = group.last!.details.matchInfo.gameStart
			let firstEnd = group.first!.details.matchInfo.gameStart.addingTimeInterval(group.first!.details.matchInfo.gameLength)
			
			let topAgent = agentCounts.max { lhs, rhs in
				if lhs.value != rhs.value { return lhs.value < rhs.value }
				return agentWins[lhs.key, default: 0] < agentWins[rhs.key, default: 0]
			}
			let topMap = mapCounts.max { lhs, rhs in
				if lhs.value != rhs.value { return lhs.value < rhs.value }
				return mapWins[lhs.key, default: 0] < mapWins[rhs.key, default: 0]
			}
			
			let distinctQueues = queueCounts.keys
			let primaryQueue = queueCounts.max(by: { $0.value < $1.value })?.key
			let isMixed = distinctQueues.count > 1
			
			var highlights: [SessionHighlight] = []
			if aces > 0 {
				highlights.append(SessionHighlight(label: "ACE", count: aces, priority: 100))
			}
			for (enemyCount, count) in clutchesByEnemies where count > 0 {
				highlights.append(SessionHighlight(
					label: "1V\(enemyCount) CLUTCH",
					count: count,
					priority: 90 + enemyCount
				))
			}
			if quadras > 0 {
				highlights.append(SessionHighlight(label: "4K", count: quadras, priority: 80))
			}
			if matchMVPs > 0 {
				highlights.append(SessionHighlight(label: "MATCH MVP", count: matchMVPs, priority: 70))
			}
			if triples > 0 {
				highlights.append(SessionHighlight(label: "3K", count: triples, priority: 60))
			}
			if teamMVPs > 0 {
				highlights.append(SessionHighlight(label: "TEAM MVP", count: teamMVPs, priority: 50))
			}
			highlights.sort { $0.priority > $1.priority }
			
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
				totalDamage: damage,
				totalRounds: rounds,
				headshots: head,
				totalHits: hits,
				topAgentID: topAgent?.key,
				topAgentMatches: topAgent?.value ?? 0,
				topAgentWins: topAgent.map { agentWins[$0.key, default: 0] } ?? 0,
				topMapID: topMap?.key,
				topMapMatches: topMap?.value ?? 0,
				topMapWins: topMap.map { mapWins[$0.key, default: 0] } ?? 0,
				primaryQueueID: primaryQueue,
				isMixedQueues: isMixed,
				hasRankedMatches: hasRanked,
				highlights: Array(highlights.prefix(6))
			)
		}
	}
}
