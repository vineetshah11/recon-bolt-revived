import SwiftUI
import ValorantAPI

/// The 12 match accolades tracked across Cached Match Details.
enum AccoladeType: String, CaseIterable, Identifiable, Codable, Hashable {
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
		case .masterful: return "Reach a Performance Score of 420 or higher in a match"
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

struct AccoladeMatchItem: Identifiable, Hashable, Codable {
	var id: AccoladeType { type }
	var type: AccoladeType
	var value: Int
	var isNewBest: Bool = false
	
	enum CodingKeys: String, CodingKey {
		case type, value
	}
}

struct CachedMatchAccolades: Codable, Hashable, Identifiable {
	var id: Match.ID { matchID }
	var matchID: Match.ID
	var mapID: MapID
	var seasonID: Season.ID
	var gameStart: Date
	var items: [AccoladeMatchItem]
}

struct AccoladeMatchGroup: Identifiable, Hashable {
	var id: Match.ID { matchID }
	var matchID: Match.ID
	var mapID: MapID
	var seasonID: Season.ID
	var gameStart: Date
	var accolades: [AccoladeMatchItem]
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
	var recentMatches: [AccoladeMatchGroup] = []
}

private struct RawMatchAccoladeHit {
	var matchID: Match.ID
	var mapID: MapID
	var seasonID: Season.ID
	var gameStart: Date
	var value: Int
}

enum AccoladesCalculator {
	static func extractCachedEntry(
		userID: User.ID,
		match: MatchDetails
	) -> CachedMatchAccolades {
		CachedMatchAccolades(
			matchID: match.id,
			mapID: match.matchInfo.mapID,
			seasonID: match.matchInfo.seasonID,
			gameStart: match.matchInfo.gameStart,
			items: accolades(for: userID, in: match)
		)
	}
	
	static func buildReport(
		from entries: [CachedMatchAccolades],
		act: Act?,
		seasons: SeasonCollection.Accessor? = nil
	) -> AccoladesReport {
		var allHits: [AccoladeType: [RawMatchAccoladeHit]] = [:]
		for entry in entries {
			for item in entry.items {
				allHits[item.type, default: []].append(RawMatchAccoladeHit(
					matchID: entry.matchID,
					mapID: entry.mapID,
					seasonID: entry.seasonID,
					gameStart: entry.gameStart,
					value: item.value
				))
			}
		}
		
		let thisActID = act?.id
		let thisActTimeSpan = act?.timeSpan
		func belongsToThisAct(_ hit: RawMatchAccoladeHit) -> Bool {
			if let thisActID, hit.seasonID == thisActID { return true }
			if let thisActTimeSpan, thisActTimeSpan.contains(hit.gameStart) { return true }
			return false
		}
		
		let scopedEntries: [CachedMatchAccolades] = {
			let filtered: [CachedMatchAccolades]
			if act != nil {
				filtered = entries.filter { e in
					(thisActID != nil && e.seasonID == thisActID)
						|| (thisActTimeSpan?.contains(e.gameStart) == true)
				}
			} else {
				filtered = entries
			}
			return filtered.sorted { $0.gameStart > $1.gameStart }
		}()
		
		let allSummaries = AccoladeType.allCases.map { type -> AccoladeSummary in
			let rawAll = allHits[type] ?? []
			let (allRecords, allTimeBest) = buildRecords(from: rawAll)
			
			let thisActRecords: [AccoladeMatchRecord]
			let thisActBest: Int?
			let activeRecords: [AccoladeMatchRecord]
			let activeBest: Int?
			if act != nil {
				let rawThisAct = rawAll.filter(belongsToThisAct)
				let builtAct = buildRecords(from: rawThisAct)
				thisActRecords = builtAct.records
				thisActBest = builtAct.bestValue
				activeRecords = thisActRecords
				activeBest = thisActBest
			} else {
				thisActRecords = []
				thisActBest = nil
				activeRecords = allRecords
				activeBest = allTimeBest
			}
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
		
		let recentPrefix = Array(scopedEntries.prefix(20))
		let recentMatchIDs = Set(recentPrefix.map(\.matchID))
		var recordsByMatch: [Match.ID: [AccoladeType: AccoladeMatchRecord]] = [:]
		for summary in allSummaries {
			for record in summary.records where recentMatchIDs.contains(record.matchID) {
				recordsByMatch[record.matchID, default: [:]][summary.type] = record
			}
		}
		
		let recentMatches = recentPrefix.map { entry in
			let matchMap = recordsByMatch[entry.matchID] ?? [:]
			let items = AccoladeType.allCases.compactMap { type -> AccoladeMatchItem? in
				guard let record = matchMap[type] else { return nil }
				return AccoladeMatchItem(type: type, value: record.value, isNewBest: record.isNewBest)
			}
			return AccoladeMatchGroup(
				matchID: entry.matchID,
				mapID: entry.mapID,
				seasonID: entry.seasonID,
				gameStart: entry.gameStart,
				accolades: items
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
			scannedMatchesCount: scopedEntries.count,
			allItems: allSummaries,
			earnedItems: earned,
			recentMatches: recentMatches
		)
	}
	
	static func compute(
		userID: User.ID,
		matches: [MatchDetails],
		act: Act?,
		seasons: SeasonCollection.Accessor? = nil
	) -> AccoladesReport {
		let entries = matches.map { extractCachedEntry(userID: userID, match: $0) }
		return buildReport(from: entries, act: act, seasons: seasons)
	}
	
	private static func buildRecords(from raw: [RawMatchAccoladeHit]) -> (records: [AccoladeMatchRecord], bestValue: Int?) {
		// Walk chronologically oldest -> newest to mark every strict personal-best breakthrough.
		let chronological = raw.sorted { $0.gameStart < $1.gameStart }
		var runningBest = Int.min
		var maxValue: Int?
		var marked: [AccoladeMatchRecord] = []
		marked.reserveCapacity(chronological.count)
		
		for hit in chronological {
			let isNewBest = hit.value > runningBest
			if isNewBest { runningBest = hit.value }
			if maxValue == nil || hit.value > maxValue! {
				maxValue = hit.value
			}
			marked.append(AccoladeMatchRecord(
				matchID: hit.matchID,
				mapID: hit.mapID,
				seasonID: hit.seasonID,
				gameStart: hit.gameStart,
				value: hit.value,
				isNewBest: isNewBest
			))
		}
		return (marked.reversed(), maxValue)
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
	
	static func accolades(
		for playerID: Player.ID,
		in match: MatchDetails,
		analytics: MatchAnalytics? = nil
	) -> [AccoladeMatchItem] {
		guard let player = match.players.firstElement(withID: playerID),
			  let stats = player.stats else { return [] }
		
		let roundsPlayed = max(1, stats.roundsPlayed)
		let teamByPlayer = Dictionary(match.players.map { ($0.id, $0.teamID) }, uniquingKeysWith: { first, _ in first })
		
		var damageByPlayer: [Player.ID: Int] = [:]
		var firstKillsByPlayer: [Player.ID: Int] = [:]
		var tradesByPlayer: [Player.ID: Int] = [:]
		var clutchesByPlayer: [Player.ID: Int] = [:]
		var acesByPlayer: [Player.ID: Int] = [:]
		var headshots = 0
		var totalHits = 0
		var userSpikeActions = 0
		
		for round in match.roundResults {
			if round.plant?.actor == playerID { userSpikeActions += 1 }
			if round.defusal?.actor == playerID { userSpikeActions += 1 }
			
			let roundKills = round.playerStats
				.flatMap(\.kills)
				.sorted { $0.roundTimeMillis < $1.roundTimeMillis }
			
			if let opener = roundKills.first?.killer {
				firstKillsByPlayer[opener, default: 0] += 1
			}
			
			// Single pass over roundKills for ace counts and 5000ms trade detection.
			var killsInRound: [Player.ID: Int] = [:]
			var lastVictimKillTimeByKiller: [Player.ID: (victimTeam: Team.ID, time: Int)] = [:]
			for kill in roundKills {
				guard let killer = kill.killer else { continue }
				killsInRound[killer, default: 0] += 1
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
			for (killerID, count) in killsInRound where count >= 5 {
				acesByPlayer[killerID, default: 0] += 1
			}
			
			if round.ceremony.range(of: "clutch", options: .caseInsensitive) != nil {
				let deadPlayers = Set(roundKills.map(\.victim))
				for p in match.players where p.teamID == round.winningTeam && !deadPlayers.contains(p.id) {
					clutchesByPlayer[p.id, default: 0] += 1
				}
			}
			
			for ps in round.playerStats {
				let dmg = ps.damageDealt.reduce(0) { $0 + $1.damage }
				damageByPlayer[ps.subject, default: 0] += dmg
				if ps.subject == playerID {
					for d in ps.damageDealt {
						headshots += d.headshots
						totalHits += d.headshots + d.bodyshots + d.legshots
					}
				}
			}
		}
		
		let perfScores: [Player.ID: Int]
		if let analytics, !analytics.byPlayer.isEmpty {
			perfScores = analytics.byPlayer.mapValues(\.performanceScore)
		} else {
			var computed: [Player.ID: Int] = [:]
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
				computed[p.id] = min(500, max(0, Int(raw.rounded())))
			}
			perfScores = computed
		}
		
		var earned: [AccoladeType: Int] = [:]
		let myPerf = perfScores[playerID, default: 0]
		let maxPerf = perfScores.values.max() ?? 0
		if myPerf > 0 && myPerf >= maxPerf {
			earned[.mvp] = myPerf
		}
		if myPerf >= 420 {
			earned[.masterful] = myPerf
		}
		
		let maxKills = match.players.compactMap(\.stats?.kills).max() ?? 0
		if stats.kills > 0 && stats.kills == maxKills {
			earned[.topFrag] = stats.kills
		}
		if stats.kills >= 20 {
			earned[.kills] = stats.kills
		}
		
		let myDmg = damageByPlayer[playerID, default: 0]
		let myADR = Int((Double(myDmg) / Double(roundsPlayed)).rounded())
		let maxDmg = damageByPlayer.values.max() ?? 0
		if myADR >= 165 || (myDmg > 0 && myDmg == maxDmg) {
			earned[.damage] = myADR
		}
		
		if totalHits >= 10 {
			let hsPct = Int((Double(headshots) * Double(100) / Double(totalHits)).rounded())
			if hsPct >= 35 {
				earned[.headshots] = hsPct
			}
		}
		
		let myFK = firstKillsByPlayer[playerID, default: 0]
		let maxFK = firstKillsByPlayer.values.max() ?? 0
		if myFK >= 3 || (myFK >= 2 && myFK == maxFK) {
			earned[.firstBloods] = myFK
		}
		
		let myAces = acesByPlayer[playerID, default: 0]
		if myAces >= 1 {
			earned[.aces] = myAces
		}
		
		let myClutches = clutchesByPlayer[playerID, default: 0]
		if myClutches >= 1 {
			earned[.clutches] = myClutches
		}
		
		let myTrades = tradesByPlayer[playerID, default: 0]
		if myTrades >= 3 {
			earned[.trades] = myTrades
		}
		
		let maxAssists = match.players.compactMap(\.stats?.assists).max() ?? 0
		if stats.assists >= 10 || (stats.assists >= 5 && stats.assists == maxAssists) {
			earned[.assists] = stats.assists
		}
		
		if userSpikeActions >= 3 {
			earned[.spikePlants] = userSpikeActions
		}
		
		return AccoladeType.allCases.compactMap { type in
			earned[type].map { AccoladeMatchItem(type: type, value: $0) }
		}
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
