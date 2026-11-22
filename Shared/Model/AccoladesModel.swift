import SwiftUI
import ValorantAPI

/// The 12 match accolades tracked across Cached Match Details.
enum AccoladeType: String, CaseIterable, Identifiable {
	case mvp
	case topFrag
	case masterful
	case kills
	case damage
	case headshots
	case firstBloods
	case aces
	case clutches
	case trades
	case assists
	case spikePlants
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .mvp: return "MVP"
		case .topFrag: return "Top Frag"
		case .masterful: return "Masterful"
		case .kills: return "Kills"
		case .damage: return "Damage"
		case .headshots: return "Headshots"
		case .firstBloods: return "First Bloods"
		case .aces: return "Aces"
		case .clutches: return "Clutches"
		case .trades: return "Trades"
		case .assists: return "Assists"
		case .spikePlants: return "Spike Plants"
		}
	}
	
	var howToEarn: String {
		switch self {
		case .mvp: return "Get the highest Performance Score in a match"
		case .topFrag: return "Get the most kills in a match"
		case .masterful: return "Reach a Performance Score of 400 or higher in a match"
		case .kills: return "Get 20 or more kills in a match"
		case .damage: return "Deal the highest damage per round or 165+ ADR"
		case .headshots: return "Achieve 35% or higher headshot accuracy (10+ hits)"
		case .firstBloods: return "Get the most first bloods or 3+ opening picks"
		case .aces: return "Eliminate all 5 opponents in a single round"
		case .clutches: return "Win a round as the last player standing"
		case .trades: return "Eliminate an enemy within 5s of them killing a teammate (3+ times)"
		case .assists: return "Get 10+ assists or lead the lobby with 5+ assists"
		case .spikePlants: return "Plant or defuse the Spike 3 or more times in a match"
		}
	}
	
	var unitLabel: String {
		switch self {
		case .mvp, .masterful: return "Performance Score"
		case .topFrag, .kills: return "Kills"
		case .damage: return "ADR"
		case .headshots: return "Headshot %"
		case .firstBloods: return "First Bloods"
		case .aces: return "Aces"
		case .clutches: return "Clutches"
		case .trades: return "Trades"
		case .assists: return "Assists"
		case .spikePlants: return "Plants & Defuses"
		}
	}
	
	var iconName: String {
		switch self {
		case .mvp: return "star.circle.fill"
		case .topFrag: return "burst.fill"
		case .masterful: return "diamond.fill"
		case .kills: return "scope"
		case .damage: return "flame.fill"
		case .headshots: return "target"
		case .firstBloods: return "bolt.fill"
		case .aces: return "crown.fill"
		case .clutches: return "shield.checkered"
		case .trades: return "arrow.left.arrow.right"
		case .assists: return "hands.sparkles.fill"
		case .spikePlants: return "exclamationmark.triangle.fill"
		}
	}
	
	func formattedValue(_ value: Int) -> String {
		self == .headshots ? "\(value)%" : "\(value)"
	}
}

struct AccoladeMatchRecord: Identifiable, Hashable {
	var id: Match.ID { matchID }
	var matchID: Match.ID
	var mapID: MapID
	var seasonID: Season.ID
	var gameStart: Date
	var value: Int
	var isNewBest: Bool
}

struct AccoladeActBreakdown: Identifiable, Hashable {
	var id: Season.ID
	var actName: String
	var count: Int
	var bestValue: Int
	var sortDate: Date
}

struct AccoladeSummary: Identifiable {
	var id: AccoladeType { type }
	var type: AccoladeType
	var count: Int
	var bestValue: Int?
	var records: [AccoladeMatchRecord]
	var thisActCount: Int
	var thisActBest: Int?
	var thisActRecords: [AccoladeMatchRecord]
	var allTimeCount: Int
	var allTimeBest: Int?
	var allTimeRecords: [AccoladeMatchRecord]
	var byAct: [AccoladeActBreakdown]
}

struct AccoladesReport {
	var totalEarned: Int
	var earnedTypesCount: Int
	var totalTypesCount: Int
	var scannedMatchesCount: Int
	/// All 12 accolades in canonical order (earned and unearned).
	var allItems: [AccoladeSummary]
	/// Subset of accolades earned at least once in this scope, sorted by count descending.
	var earnedItems: [AccoladeSummary]
}

private struct RawMatchAccoladeHit {
	var matchID: Match.ID
	var mapID: MapID
	var seasonID: Season.ID
	var gameStart: Date
	var value: Int
}

enum AccoladesCalculator {
	static func compute(
		userID: User.ID,
		matches: [MatchDetails],
		act: Act?,
		seasons: SeasonCollection.Accessor? = nil
	) -> AccoladesReport {
		let allHits = collectHits(userID: userID, matches: matches)
		
		let thisActID = act?.id
		let thisActTimeSpan = act?.timeSpan
		func belongsToThisAct(_ hit: RawMatchAccoladeHit) -> Bool {
			if let thisActID, hit.seasonID == thisActID { return true }
			if let thisActTimeSpan, thisActTimeSpan.contains(hit.gameStart) { return true }
			return false
		}
		
		let allScopedMatchesCount: Int = {
			guard act != nil else { return matches.count }
			return matches.filter { m in
				(thisActID != nil && m.matchInfo.seasonID == thisActID)
					|| (thisActTimeSpan?.contains(m.matchInfo.gameStart) == true)
			}.count
		}()
		
		let allSummaries = AccoladeType.allCases.map { type -> AccoladeSummary in
			let rawAll = allHits[type] ?? []
			let allRecords = buildRecords(from: rawAll)
			
			let rawThisAct = rawAll.filter(belongsToThisAct)
			let thisActRecords = buildRecords(from: rawThisAct)
			
			let activeRecords = (act != nil) ? thisActRecords : allRecords
			let activeBest = activeRecords.map(\.value).max()
			let thisActBest = thisActRecords.map(\.value).max()
			let allTimeBest = allRecords.map(\.value).max()
			let byAct = buildActBreakdowns(from: rawAll, seasons: seasons)
			
			return AccoladeSummary(
				type: type,
				count: activeRecords.count,
				bestValue: activeBest,
				records: activeRecords,
				thisActCount: thisActRecords.count,
				thisActBest: thisActBest,
				thisActRecords: thisActRecords,
				allTimeCount: allRecords.count,
				allTimeBest: allTimeBest,
				allTimeRecords: allRecords,
				byAct: byAct
			)
		}
		
		let earned = allSummaries
			.filter { $0.count > 0 }
			.sorted {
				if $0.count != $1.count { return $0.count > $1.count }
				return ($0.bestValue ?? 0) > ($1.bestValue ?? 0)
			}
		
		return AccoladesReport(
			totalEarned: allSummaries.reduce(0) { $0 + $1.count },
			earnedTypesCount: earned.count,
			totalTypesCount: AccoladeType.allCases.count,
			scannedMatchesCount: allScopedMatchesCount,
			allItems: allSummaries,
			earnedItems: earned
		)
	}
	
	private static func buildRecords(from raw: [RawMatchAccoladeHit]) -> [AccoladeMatchRecord] {
		// Walk chronologically oldest -> newest to mark every strict personal-best breakthrough.
		let chronological = raw.sorted { $0.gameStart < $1.gameStart }
		var runningBest = Int.min
		var marked: [AccoladeMatchRecord] = []
		marked.reserveCapacity(chronological.count)
		
		for hit in chronological {
			let isNewBest = hit.value > runningBest
			if isNewBest { runningBest = hit.value }
			marked.append(AccoladeMatchRecord(
				matchID: hit.matchID,
				mapID: hit.mapID,
				seasonID: hit.seasonID,
				gameStart: hit.gameStart,
				value: hit.value,
				isNewBest: isNewBest
			))
		}
		return marked.reversed()
	}
	
	private static func buildActBreakdowns(
		from raw: [RawMatchAccoladeHit],
		seasons: SeasonCollection.Accessor?
	) -> [AccoladeActBreakdown] {
		let grouped = Dictionary(grouping: raw, by: \.seasonID)
		return grouped.map { seasonID, hits in
			let resolvedAct = seasons?.act(seasonID)
			let label = resolvedAct?.shortDisplayLabel ?? "Previous Act"
			let best = hits.map(\.value).max() ?? 0
			let sortDate = resolvedAct?.timeSpan.start ?? hits.map(\.gameStart).max() ?? Date.distantPast
			return AccoladeActBreakdown(
				id: seasonID,
				actName: label,
				count: hits.count,
				bestValue: best,
				sortDate: sortDate
			)
		}
		.sorted { $0.sortDate > $1.sortDate }
	}
	
	private static func collectHits(
		userID: User.ID,
		matches: [MatchDetails]
	) -> [AccoladeType: [RawMatchAccoladeHit]] {
		var result: [AccoladeType: [RawMatchAccoladeHit]] = [:]
		func record(_ type: AccoladeType, _ match: MatchDetails, value: Int) {
			result[type, default: []].append(RawMatchAccoladeHit(
				matchID: match.id,
				mapID: match.matchInfo.mapID,
				seasonID: match.matchInfo.seasonID,
				gameStart: match.matchInfo.gameStart,
				value: value
			))
		}
		
		for match in matches {
			guard let player = match.players.firstElement(withID: userID),
				  let stats = player.stats else { continue }
			
			let roundsPlayed = max(1, stats.roundsPlayed)
			let teamByPlayer = Dictionary(uniqueKeysWithValues: match.players.map { ($0.id, $0.teamID) })
			
			var damageByPlayer: [Player.ID: Int] = [:]
			var firstKillsByPlayer: [Player.ID: Int] = [:]
			var tradesByPlayer: [Player.ID: Int] = [:]
			var clutchesByPlayer: [Player.ID: Int] = [:]
			var acesByPlayer: [Player.ID: Int] = [:]
			var headshots = 0
			var totalHits = 0
			var userSpikeActions = 0
			
			for round in match.roundResults {
				if round.plant?.actor == userID { userSpikeActions += 1 }
				if round.defusal?.actor == userID { userSpikeActions += 1 }
				
				let roundKills = round.playerStats
					.flatMap(\.kills)
					.sorted { $0.roundTimeMillis < $1.roundTimeMillis }
				
				if let opener = roundKills.first?.killer {
					firstKillsByPlayer[opener, default: 0] += 1
				}
				
				var killsInRound: [Player.ID: Int] = [:]
				for kill in roundKills {
					if let killer = kill.killer {
						killsInRound[killer, default: 0] += 1
					}
				}
				for (killerID, count) in killsInRound where count >= 5 {
					acesByPlayer[killerID, default: 0] += 1
				}
				
				// A trade is a kill within 5000ms against an opponent who just killed a teammate.
				var lastVictimKillTimeByKiller: [Player.ID: (victimTeam: Team.ID, time: Int)] = [:]
				for kill in roundKills {
					guard let killer = kill.killer else { continue }
					let victim = kill.victim
					if let killerTeam = teamByPlayer[killer],
					   let prior = lastVictimKillTimeByKiller[victim],
					   prior.victimTeam == killerTeam,
					   kill.roundTimeMillis - prior.time <= 5000 {
						tradesByPlayer[killer, default: 0] += 1
					}
					if let victimTeam = teamByPlayer[victim] {
						lastVictimKillTimeByKiller[killer] = (victimTeam, kill.roundTimeMillis)
					}
				}
				
				if round.ceremony.lowercased().contains("clutch") {
					let deadPlayers = Set(roundKills.map(\.victim))
					for p in match.players where p.teamID == round.winningTeam && !deadPlayers.contains(p.id) {
						clutchesByPlayer[p.id, default: 0] += 1
					}
				}
				
				for ps in round.playerStats {
					let dmg = ps.damageDealt.reduce(0) { $0 + $1.damage }
					damageByPlayer[ps.subject, default: 0] += dmg
					if ps.subject == userID {
						for d in ps.damageDealt {
							headshots += d.headshots
							totalHits += d.headshots + d.bodyshots + d.legshots
						}
					}
				}
			}
			
			// Compute a 0...500 Performance Score per player in the lobby so MVP and Masterful share one scale.
			var perfScores: [Player.ID: Int] = [:]
			for p in match.players {
				guard let s = p.stats, s.roundsPlayed > 0 else { continue }
				let acs = Double(s.score) / Double(s.roundsPlayed)
				let adr = Double(damageByPlayer[p.id, default: 0]) / Double(s.roundsPlayed)
				let fk = Double(firstKillsByPlayer[p.id, default: 0])
				let tr = Double(tradesByPlayer[p.id, default: 0])
				let cl = Double(clutchesByPlayer[p.id, default: 0])
				let ac = Double(acesByPlayer[p.id, default: 0])
				let kdDiff = Double(max(0, s.kills - s.deaths))
				let raw = acs * Double(1.05) + kdDiff * Double(6.0) + adr * Double(0.45)
					+ fk * Double(14.0) + tr * Double(10.0) + cl * Double(28.0) + ac * Double(45.0)
				perfScores[p.id] = min(500, max(0, Int(raw.rounded())))
			}
			
			let myPerf = perfScores[userID, default: 0]
			let maxPerf = perfScores.values.max() ?? 0
			if myPerf > 0 && myPerf >= maxPerf {
				record(.mvp, match, value: myPerf)
			}
			if myPerf >= 400 {
				record(.masterful, match, value: myPerf)
			}
			
			let maxKills = match.players.compactMap(\.stats?.kills).max() ?? 0
			if stats.kills > 0 && stats.kills == maxKills {
				record(.topFrag, match, value: stats.kills)
			}
			if stats.kills >= 20 {
				record(.kills, match, value: stats.kills)
			}
			
			let myDmg = damageByPlayer[userID, default: 0]
			let myADR = Int((Double(myDmg) / Double(roundsPlayed)).rounded())
			let maxDmg = damageByPlayer.values.max() ?? 0
			if myADR >= 165 || (myDmg > 0 && myDmg == maxDmg) {
				record(.damage, match, value: myADR)
			}
			
			if totalHits >= 10 {
				let hsPct = Int((Double(headshots) * Double(100) / Double(totalHits)).rounded())
				if hsPct >= 35 {
					record(.headshots, match, value: hsPct)
				}
			}
			
			let myFK = firstKillsByPlayer[userID, default: 0]
			let maxFK = firstKillsByPlayer.values.max() ?? 0
			if myFK >= 3 || (myFK >= 2 && myFK == maxFK) {
				record(.firstBloods, match, value: myFK)
			}
			
			let myAces = acesByPlayer[userID, default: 0]
			if myAces >= 1 {
				record(.aces, match, value: myAces)
			}
			
			let myClutches = clutchesByPlayer[userID, default: 0]
			if myClutches >= 1 {
				record(.clutches, match, value: myClutches)
			}
			
			let myTrades = tradesByPlayer[userID, default: 0]
			if myTrades >= 3 {
				record(.trades, match, value: myTrades)
			}
			
			let maxAssists = match.players.compactMap(\.stats?.assists).max() ?? 0
			if stats.assists >= 10 || (stats.assists >= 5 && stats.assists == maxAssists) {
				record(.assists, match, value: stats.assists)
			}
			
			if userSpikeActions >= 3 {
				record(.spikePlants, match, value: userSpikeActions)
			}
		}
		
		return result
	}
}

extension Act {
	var shortDisplayLabel: String {
		if let episode {
			let epShort = episode.name
				.replacingOccurrences(of: "Episode ", with: "EP ", options: .caseInsensitive)
				.replacingOccurrences(of: "Season ", with: "V", options: .caseInsensitive)
				.replacingOccurrences(of: "20", with: "")
			return "\(epShort.uppercased()) — \(name.uppercased())"
		}
		return name.uppercased()
	}
}
