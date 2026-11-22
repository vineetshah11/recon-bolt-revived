import SwiftUI
import ValorantAPI

enum AccoladeType: String, CaseIterable, Identifiable {
	case kills
	case damage
	case mvp
	case firstBlood
	case clutches
	case assists
	case ace
	case multiKill
	case sharpshooter
	case utility
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .kills: return "Kills"
		case .damage: return "Damage"
		case .mvp: return "MVP"
		case .firstBlood: return "First Blood"
		case .clutches: return "Clutch"
		case .assists: return "Assists"
		case .ace: return "Ace"
		case .multiKill: return "Multi-Kill"
		case .sharpshooter: return "Sharpshooter"
		case .utility: return "Utility"
		}
	}
	
	var subtitle: String {
		switch self {
		case .kills: return "Highest kills in match or 20+ kills"
		case .damage: return "Highest damage per round in match or 165+ ADR"
		case .mvp: return "Top combat score across the entire lobby"
		case .firstBlood: return "Most first kills in match or 3+ opening picks"
		case .clutches: return "Won a round as the last player standing"
		case .assists: return "Highest assists in match or 10+ assists"
		case .ace: return "Eliminated 5 opponents in a single round"
		case .multiKill: return "Secured a 4K round"
		case .sharpshooter: return "35%+ headshot accuracy in a match"
		case .utility: return "25+ ability casts supporting the team"
		}
	}
	
	var iconName: String {
		switch self {
		case .kills: return "scope"
		case .damage: return "flame.fill"
		case .mvp: return "star.circle.fill"
		case .firstBlood: return "bolt.fill"
		case .clutches: return "shield.checkered"
		case .assists: return "hands.sparkles.fill"
		case .ace: return "crown.fill"
		case .multiKill: return "sparkles"
		case .sharpshooter: return "target"
		case .utility: return "wand.and.stars"
		}
	}
	
	var badgeColor: Color {
		switch self {
		case .ace: return Color(red: 0.95, green: 0.65, blue: 0.15)
		case .clutches: return Color(red: 0.2, green: 0.78, blue: 0.62)
		default: return .accentColor
		}
	}
}

struct AccoladeSummary: Identifiable {
	var id: AccoladeType { type }
	var type: AccoladeType
	var count: Int
	var matchIDs: [Match.ID]
}

struct AccoladesReport {
	var totalEarned: Int
	var items: [AccoladeSummary]
}

enum AccoladesCalculator {
	static func compute(
		userID: User.ID,
		matches: [MatchDetails],
		act: Act?
	) -> AccoladesReport {
		let scoped = act.map { a in matches.filter { a.timeSpan.contains($0.matchInfo.gameStart) } } ?? matches
		var counts: [AccoladeType: [Match.ID]] = [:]
		
		for match in scoped {
			guard let player = match.players.firstElement(withID: userID),
				  let stats = player.stats else { continue }
			
			let roundsPlayed = max(1, stats.roundsPlayed)
			let acs = Double(stats.score) / Double(roundsPlayed)
			
			// Match MVP: highest ACS across non-neutral players
			let maxACS = match.players.compactMap { p -> Double? in
				guard let s = p.stats, s.roundsPlayed > 0 else { return nil }
				return Double(s.score) / Double(s.roundsPlayed)
			}.max() ?? 0
			if acs > 0, acs >= maxACS - 0.01 {
				counts[.mvp, default: []].append(match.id)
			}
			
			// Kills
			let maxKills = match.players.compactMap(\.stats?.kills).max() ?? 0
			if stats.kills >= 20 || (stats.kills > 0 && stats.kills == maxKills) {
				counts[.kills, default: []].append(match.id)
			}
			
			// Assists
			let maxAssists = match.players.compactMap(\.stats?.assists).max() ?? 0
			if stats.assists >= 10 || (stats.assists >= 4 && stats.assists == maxAssists) {
				counts[.assists, default: []].append(match.id)
			}
			
			// Damage & Headshots & Clutches / Multi-kills / First Bloods
			var playerDamageByPlayer: [Player.ID: Int] = [:]
			var firstKills: [Player.ID: Int] = [:]
			var headshots = 0
			var totalHits = 0
			var gotAce = false
			var gotFourK = false
			var gotClutch = false
			
			for round in match.roundResults {
				if round.winningTeam == player.teamID,
				   round.ceremony.lowercased().contains("clutch") {
					// Check if user survived / got last kill in clutch round
					let userDied = round.playerStats.contains { ps in
						ps.kills.contains { $0.victim == userID }
					}
					if !userDied {
						gotClutch = true
					}
				}
				
				let allKills = round.playerStats.flatMap(\.kills).sorted { $0.roundTimeMillis < $1.roundTimeMillis }
				if let first = allKills.first, let killer = first.killer {
					firstKills[killer, default: 0] += 1
				}
				
				let userRoundKills = allKills.filter { $0.killer == userID }.count
				if userRoundKills >= 5 {
					gotAce = true
				} else if userRoundKills == 4 {
					gotFourK = true
				}
				
				for ps in round.playerStats {
					let roundDmg = ps.damageDealt.reduce(0) { $0 + $1.damage }
					playerDamageByPlayer[ps.subject, default: 0] += roundDmg
					if ps.subject == userID {
						for d in ps.damageDealt {
							headshots += d.headshots
							totalHits += d.headshots + d.bodyshots + d.legshots
						}
					}
				}
			}
			
			let myDmg = playerDamageByPlayer[userID, default: 0]
			let myADR = Double(myDmg) / Double(roundsPlayed)
			let maxDmg = playerDamageByPlayer.values.max() ?? 0
			if myADR >= 165 || (myDmg > 0 && myDmg == maxDmg) {
				counts[.damage, default: []].append(match.id)
			}
			
			let myFK = firstKills[userID, default: 0]
			let maxFK = firstKills.values.max() ?? 0
			if myFK >= 3 || (myFK >= 2 && myFK == maxFK) {
				counts[.firstBlood, default: []].append(match.id)
			}
			
			if gotClutch { counts[.clutches, default: []].append(match.id) }
			if gotAce { counts[.ace, default: []].append(match.id) }
			if gotFourK { counts[.multiKill, default: []].append(match.id) }
			
			if totalHits >= 12 {
				let hsRate = Double(headshots) / Double(totalHits)
				if hsRate >= 0.35 {
					counts[.sharpshooter, default: []].append(match.id)
				}
			}
			
			if let casts = stats.abilityCasts {
				let totalCasts = casts.first + casts.second + casts.signature + casts.ultimate
				if totalCasts >= 25 {
					counts[.utility, default: []].append(match.id)
				}
			}
		}
		
		let items = AccoladeType.allCases.compactMap { type -> AccoladeSummary? in
			let ids = counts[type] ?? []
			guard !ids.isEmpty else { return nil }
			return AccoladeSummary(type: type, count: ids.count, matchIDs: ids)
		}
		.sorted {
			if $0.count != $1.count { return $0.count > $1.count }
			return $0.type.title < $1.type.title
		}
		
		return AccoladesReport(
			totalEarned: items.reduce(0) { $0 + $1.count },
			items: items
		)
	}
}
