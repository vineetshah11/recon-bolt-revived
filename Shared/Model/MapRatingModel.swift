import SwiftUI
import ValorantAPI

enum MapRatingTier: String, CaseIterable, Codable, Hashable, Comparable {
	case uncalibrated
	case c1, c2, c3
	case b1, b2, b3
	case a1, a2, a3
	case s
	
	private var sortOrder: Int {
		switch self {
		case .uncalibrated: return 0
		case .c1: return 1
		case .c2: return 2
		case .c3: return 3
		case .b1: return 4
		case .b2: return 5
		case .b3: return 6
		case .a1: return 7
		case .a2: return 8
		case .a3: return 9
		case .s: return 10
		}
	}
	
	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.sortOrder < rhs.sortOrder
	}
	
	var letter: String {
		switch self {
		case .uncalibrated: return "?"
		case .c1, .c2, .c3: return "C"
		case .b1, .b2, .b3: return "B"
		case .a1, .a2, .a3: return "A"
		case .s: return "S"
		}
	}
	
	var starCount: Int {
		switch self {
		case .uncalibrated, .s: return 0
		case .c1, .b1, .a1: return 1
		case .c2, .b2, .a2: return 2
		case .c3, .b3, .a3: return 3
		}
	}
	
	var displayCode: String {
		switch self {
		case .uncalibrated: return "?"
		case .s: return "S"
		default: return "\(letter)\(starCount)"
		}
	}
	
	var minimumScore: Int {
		switch self {
		case .uncalibrated, .c1: return 0
		case .c2: return 80
		case .c3: return 140
		case .b1: return 200
		case .b2: return 260
		case .b3: return 315
		case .a1: return 355
		case .a2: return 395
		case .a3: return 435
		case .s: return 470
		}
	}
	
	var accentColor: Color {
		switch self {
		case .uncalibrated: return .secondary
		case .c1, .c2, .c3: return Color(red: 0.62, green: 0.66, blue: 0.72)
		case .b1, .b2, .b3: return Color(red: 0.36, green: 0.72, blue: 0.92)
		case .a1, .a2, .a3: return Color(red: 0.25, green: 0.87, blue: 0.69)
		case .s: return Color(red: 0.98, green: 0.78, blue: 0.28)
		}
	}
	
	static let orderedCalibratedTiers: [MapRatingTier] = [
		.c1, .c2, .c3, .b1, .b2, .b3, .a1, .a2, .a3, .s
	]
	
	static func calibratedTier(for score: Int) -> MapRatingTier {
		let clamped = max(0, min(500, score))
		for tier in orderedCalibratedTiers.reversed() {
			if clamped >= tier.minimumScore {
				return tier
			}
		}
		return .c1
	}
	
	static func tier(for score: Int, matchCount: Int) -> MapRatingTier {
		guard matchCount >= 5 else { return .uncalibrated }
		return calibratedTier(for: score)
	}
	
	var nextThreshold: (tier: MapRatingTier, score: Int)? {
		switch self {
		case .uncalibrated: return (.b2, MapRatingTier.b2.minimumScore)
		case .s: return nil
		default:
			guard let idx = Self.orderedCalibratedTiers.firstIndex(of: self),
				  idx + 1 < Self.orderedCalibratedTiers.count else {
				return nil
			}
			let next = Self.orderedCalibratedTiers[idx + 1]
			return (next, next.minimumScore)
		}
	}
}

/// Extension hook allowing future live server Map Rating endpoints to override local estimation cleanly.
struct LiveMapRatingOverride: Hashable {
	var mapID: MapID
	var score: Int
	var tier: MapRatingTier
	var matchesRemainingForCalibration: Int
}

struct MapRatingMatchEntry: Identifiable, Hashable {
	var id: Match.ID
	var matchStart: Date
	var seasonID: Season.ID
	var queueID: QueueID?
	var agentID: Agent.ID?
	var won: Bool
	var tied: Bool
	var roundsWon: Int
	var roundsLost: Int
	var ratingAfter: Int
	var ratingDelta: Int
	var performanceScore: Int
	var attackWinRate: Double
	var defenseWinRate: Double
	var kills: Int
	var deaths: Int
	var assists: Int
	var acs: Double
	var adr: Double
	var hsPercent: Double
	var kastPercent: Double
	var firstBloods: Int
	var firstDeaths: Int
	var pistolWins: Int
	var pistolPlayed: Int
	var isBestMatchOfAct: Bool
	
	var scoreText: String { "\(roundsWon)–\(roundsLost)" }
	var kdaText: String { "\(kills)/\(deaths)/\(assists)" }
}

struct MapAgentBestStat: Identifiable, Hashable {
	var id: Agent.ID
	var matches: Int
	var wins: Int
	var winRate: Double
	var avgPerformanceScore: Int
	var kd: Double
	var acs: Double
}

struct MapRatingReport: Identifiable, Hashable {
	static let calibrationRequiredMatches = 5
	
	var id: MapID { mapID }
	var mapID: MapID
	var score: Int
	var potentialTier: MapRatingTier
	var tier: MapRatingTier
	var isCalibrating: Bool
	var matchesRemainingForCalibration: Int
	var totalMatches: Int
	var actMatches: Int
	var overallWinRate: Double
	var avgPerformanceScore: Int
	var attackWinRate: Double
	var defenseWinRate: Double
	var bestMatch: MapRatingMatchEntry?
	var bestAgents: [MapAgentBestStat]
	var matches: [MapRatingMatchEntry]
	
	// Extended tactical analytics beyond in-game UI
	var avgKD: Double
	var avgACS: Double
	var avgADR: Double
	var avgHSPercent: Double
	var avgKASTPercent: Double
	var firstBloodDiff: Int
	var pistolWinRate: Double?
	var recentRatingTrend: [Int]
	
	var hasPlayed: Bool { totalMatches > 0 }
}

enum MapRatingQueueScope: String, CaseIterable, Identifiable {
	case competitiveAndPremier
	case allStandardQueues
	
	var id: String { rawValue }
	
	var title: LocalizedStringKey {
		switch self {
		case .competitiveAndPremier: return "Competitive"
		case .allStandardQueues: return "All Queues"
		}
	}
	
	func accepts(_ queueID: QueueID?) -> Bool {
		switch self {
		case .competitiveAndPremier:
			return queueID == .competitive || queueID == .premier
		case .allStandardQueues:
			guard let queueID else { return false }
			return queueID == .competitive
				|| queueID == .premier
				|| queueID == .unrated
				|| queueID == .swiftplay
				|| queueID == .spikeRush
		}
	}
}

enum MapRatingCalculator {
	private struct RawObservation {
		var details: MatchDetails
		var analytics: MatchAnalytics.PlayerMatchAnalytics
		var won: Bool
		var tied: Bool
		var roundsWon: Int
		var roundsLost: Int
		var agentID: Agent.ID?
		var attackWinRate: Double
		var defenseWinRate: Double
		var pistolWins: Int
		var pistolPlayed: Int
		var inSelectedAct: Bool
	}
	
	static func eligibleCatalogMaps(
		assets: AssetCollection?,
		playedMapIDs: Set<MapID>
	) -> [MapInfo] {
		guard let assets else { return [] }
		return assets.maps.values
			.filter { map in
				if playedMapIDs.contains(map.id) { return true }
				if map.id == .range || map.id == .rangeV2 || map.id == .gauntlet { return false }
				let raw = map.id.rawValue.lowercased()
				if raw.contains("hurm") || raw.contains("skirmish") || raw.contains("npe") || raw.contains("poveglia") {
					return false
				}
				return !(map.callouts ?? []).isEmpty && map.displayIcon != nil
			}
			.sorted { lhs, rhs in
				lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
			}
	}
	
	static func compute(
		userID: User.ID,
		matches: [MatchDetails],
		selectedActID: Season.ID?,
		queueScope: MapRatingQueueScope = .competitiveAndPremier,
		seasons: SeasonCollection? = nil,
		assets: AssetCollection?,
		overrides: [MapID: LiveMapRatingOverride] = [:]
	) -> [MapRatingReport] {
		let targetActID = selectedActID
		let effectiveActForBonus = targetActID ?? seasons?.actsInOrder.last?.id
		
		var byMap: [MapID: [RawObservation]] = [:]
		for match in matches {
			guard match.matchInfo.isCompleted,
				  queueScope.accepts(match.matchInfo.queueID),
				  let player = match.players.firstElement(withID: userID) else {
				continue
			}
			let analytics = MatchAnalytics(details: match)
			guard let pAnalytics = analytics.byPlayer[userID] else { continue }
			
			let myTeam = match.teams.firstElement(withID: player.teamID)
			let enemyRounds = match.teams
				.filter { $0.id != player.teamID }
				.map(\.roundsWon)
				.max() ?? 0
			let myRounds = myTeam?.roundsWon ?? 0
			let won = myTeam?.won ?? (myRounds > enemyRounds)
			let tied = !won && myRounds == enemyRounds && !match.teams.contains(where: \.won)
			
			let atkPlayed = pAnalytics.attackHalf.roundsPlayed
			let atkWon = pAnalytics.attackHalf.roundsWon
			let defPlayed = pAnalytics.defenseHalf.roundsPlayed
			let defWon = pAnalytics.defenseHalf.roundsWon
			let atkWR = atkPlayed > 0 ? Double(atkWon) / Double(atkPlayed) : 0
			let defWR = defPlayed > 0 ? Double(defWon) / Double(defPlayed) : 0
			
			let pistolRounds = match.roundResults.filter { $0.number == 0 || $0.number == 12 }
			let pistolWins = pistolRounds.count { $0.winningTeam == player.teamID }
			
			let matchesActFilter: Bool
			if let selectedActID {
				matchesActFilter = (match.matchInfo.seasonID == selectedActID)
			} else {
				matchesActFilter = true
			}
			guard matchesActFilter else { continue }
			
			let isBonusAct = effectiveActForBonus.map { match.matchInfo.seasonID == $0 } ?? true
			byMap[match.matchInfo.mapID, default: []].append(
				RawObservation(
					details: match,
					analytics: pAnalytics,
					won: won,
					tied: tied,
					roundsWon: myRounds,
					roundsLost: enemyRounds,
					agentID: player.agentID,
					attackWinRate: atkWR,
					defenseWinRate: defWR,
					pistolWins: pistolWins,
					pistolPlayed: pistolRounds.count,
					inSelectedAct: isBonusAct
				)
			)
		}
		
		let catalogMaps = eligibleCatalogMaps(assets: assets, playedMapIDs: Set(byMap.keys))
		var allMapIDs = catalogMaps.map(\.id)
		for mapID in byMap.keys where !allMapIDs.contains(mapID) {
			allMapIDs.append(mapID)
		}
		
		let reports = allMapIDs.map { mapID -> MapRatingReport in
			let rawList = (byMap[mapID] ?? [])
				.sorted { $0.details.matchInfo.gameStart < $1.details.matchInfo.gameStart }
			return buildReport(
				for: mapID,
				chronological: rawList,
				override: overrides[mapID]
			)
		}
		
		return reports.sorted(by: { lhs, rhs in
			if lhs.hasPlayed != rhs.hasPlayed { return lhs.hasPlayed }
			if lhs.score != rhs.score { return lhs.score > rhs.score }
			let lhsName = assets?.maps[lhs.mapID]?.displayName ?? lhs.mapID.rawValue
			let rhsName = assets?.maps[rhs.mapID]?.displayName ?? rhs.mapID.rawValue
			return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
		})
	}
	
	private static func buildReport(
		for mapID: MapID,
		chronological: [RawObservation],
		override: LiveMapRatingOverride?
	) -> MapRatingReport {
		guard !chronological.isEmpty else {
			let baseScore = override?.score ?? 0
			let remaining = override?.matchesRemainingForCalibration ?? MapRatingReport.calibrationRequiredMatches
			return MapRatingReport(
				mapID: mapID,
				score: baseScore,
				potentialTier: .uncalibrated,
				tier: override?.tier ?? .uncalibrated,
				isCalibrating: true,
				matchesRemainingForCalibration: remaining,
				totalMatches: 0,
				actMatches: 0,
				overallWinRate: 0,
				avgPerformanceScore: 0,
				attackWinRate: 0,
				defenseWinRate: 0,
				bestMatch: nil,
				bestAgents: [],
				matches: [],
				avgKD: 0,
				avgACS: 0,
				avgADR: 0,
				avgHSPercent: 0,
				avgKASTPercent: 0,
				firstBloodDiff: 0,
				pistolWinRate: nil,
				recentRatingTrend: []
			)
		}
		
		var matchEntriesChronological: [MapRatingMatchEntry] = []
		var prevRating = 0
		
		for idx in chronological.indices {
			let obs = chronological[idx]
			let prefixSlice = Array(chronological[0...idx])
			let ratingAfter = computeScore(observations: prefixSlice)
			let delta = ratingAfter - prevRating
			prevRating = ratingAfter
			
			matchEntriesChronological.append(
				MapRatingMatchEntry(
					id: obs.details.id,
					matchStart: obs.details.matchInfo.gameStart,
					seasonID: obs.details.matchInfo.seasonID,
					queueID: obs.details.matchInfo.queueID,
					agentID: obs.agentID,
					won: obs.won,
					tied: obs.tied,
					roundsWon: obs.roundsWon,
					roundsLost: obs.roundsLost,
					ratingAfter: ratingAfter,
					ratingDelta: delta,
					performanceScore: obs.analytics.performanceScore,
					attackWinRate: obs.attackWinRate,
					defenseWinRate: obs.defenseWinRate,
					kills: obs.analytics.kills,
					deaths: obs.analytics.deaths,
					assists: obs.analytics.assists,
					acs: obs.analytics.acs,
					adr: obs.analytics.adr,
					hsPercent: obs.analytics.hsPercent,
					kastPercent: obs.analytics.kastPercent,
					firstBloods: obs.analytics.firstBloods,
					firstDeaths: obs.analytics.firstDeaths,
					pistolWins: obs.pistolWins,
					pistolPlayed: obs.pistolPlayed,
					isBestMatchOfAct: false
				)
			)
		}
		
		let actEntries = zip(chronological, matchEntriesChronological)
			.filter { $0.0.inSelectedAct }
			.map(\.1)
		let bestMatchID = (actEntries.isEmpty ? matchEntriesChronological : actEntries).max { lhs, rhs in
			if lhs.won != rhs.won { return !lhs.won && rhs.won }
			if lhs.performanceScore != rhs.performanceScore {
				return lhs.performanceScore < rhs.performanceScore
			}
			if lhs.ratingAfter != rhs.ratingAfter { return lhs.ratingAfter < rhs.ratingAfter }
			return lhs.matchStart < rhs.matchStart
		}?.id
		
		for idx in matchEntriesChronological.indices {
			if matchEntriesChronological[idx].id == bestMatchID {
				matchEntriesChronological[idx].isBestMatchOfAct = true
			}
		}
		
		let aggregateStats = computeWeightedPillars(from: chronological)
		let finalScore = override?.score ?? (matchEntriesChronological.last?.ratingAfter ?? 0)
		let remaining = override?.matchesRemainingForCalibration
			?? max(0, MapRatingReport.calibrationRequiredMatches - chronological.count)
		let potential = MapRatingTier.calibratedTier(for: finalScore)
		let finalTier = override?.tier ?? MapRatingTier.tier(for: finalScore, matchCount: chronological.count)
		
		// Agent mastery on this map
		let groupedByAgent = Dictionary(grouping: chronological.compactMap { obs -> (Agent.ID, RawObservation)? in
			obs.agentID.map { ($0, obs) }
		}, by: \.0)
		let bestAgents = groupedByAgent.map { agentID, pairs -> MapAgentBestStat in
			let obsList = pairs.map(\.1)
			let count = obsList.count
			let wins = obsList.count(where: \.won)
			let totalKills = obsList.reduce(0) { $0 + $1.analytics.kills }
			let totalDeaths = obsList.reduce(0) { $0 + $1.analytics.deaths }
			let avgPerf = Double(obsList.reduce(0) { $0 + $1.analytics.performanceScore }) / Double(count)
			let avgACS = obsList.reduce(0.0) { $0 + $1.analytics.acs } / Double(count)
			return MapAgentBestStat(
				id: agentID,
				matches: count,
				wins: wins,
				winRate: Double(wins) / Double(count),
				avgPerformanceScore: Int(avgPerf.rounded()),
				kd: Double(totalKills) / Double(max(1, totalDeaths)),
				acs: avgACS
			)
		}
		.sorted { lhs, rhs in
			if lhs.matches != rhs.matches { return lhs.matches > rhs.matches }
			if lhs.winRate != rhs.winRate { return lhs.winRate > rhs.winRate }
			return lhs.avgPerformanceScore > rhs.avgPerformanceScore
		}
		
		let totalCount = Double(chronological.count)
		let totalKills = chronological.reduce(0) { $0 + $1.analytics.kills }
		let totalDeaths = chronological.reduce(0) { $0 + $1.analytics.deaths }
		let avgACS = chronological.reduce(0.0) { $0 + $1.analytics.acs } / totalCount
		let avgADR = chronological.reduce(0.0) { $0 + $1.analytics.adr } / totalCount
		let avgHS = chronological.reduce(0.0) { $0 + $1.analytics.hsPercent } / totalCount
		let avgKAST = chronological.reduce(0.0) { $0 + $1.analytics.kastPercent } / totalCount
		let fbDiff = chronological.reduce(0) { $0 + ($1.analytics.firstBloods - $1.analytics.firstDeaths) }
		let pistolWins = chronological.reduce(0) { $0 + $1.pistolWins }
		let pistolPlayed = chronological.reduce(0) { $0 + $1.pistolPlayed }
		let pistolWR = pistolPlayed > 0 ? Double(pistolWins) / Double(pistolPlayed) : nil
		
		let trend = Array(matchEntriesChronological.suffix(12).map(\.ratingAfter))
		let descendingMatches = Array(matchEntriesChronological.reversed())
		
		return MapRatingReport(
			mapID: mapID,
			score: finalScore,
			potentialTier: potential,
			tier: finalTier,
			isCalibrating: remaining > 0,
			matchesRemainingForCalibration: remaining,
			totalMatches: chronological.count,
			actMatches: actEntries.count,
			overallWinRate: aggregateStats.overallWinRate,
			avgPerformanceScore: Int(aggregateStats.avgPerformance.rounded()),
			attackWinRate: aggregateStats.attackWinRate,
			defenseWinRate: aggregateStats.defenseWinRate,
			bestMatch: descendingMatches.first(where: \.isBestMatchOfAct),
			bestAgents: bestAgents,
			matches: descendingMatches,
			avgKD: Double(totalKills) / Double(max(1, totalDeaths)),
			avgACS: avgACS,
			avgADR: avgADR,
			avgHSPercent: avgHS,
			avgKASTPercent: avgKAST,
			firstBloodDiff: fbDiff,
			pistolWinRate: pistolWR,
			recentRatingTrend: trend
		)
	}
	
	private struct WeightedPillars {
		var overallWinRate: Double
		var avgPerformance: Double
		var attackWinRate: Double
		var defenseWinRate: Double
		var bestActPerf: Int
		var actMatchCount: Int
	}
	
	private static func computeWeightedPillars(from chronological: [RawObservation]) -> WeightedPillars {
		let n = chronological.count
		var weightSum = 0.0
		var weightedWin = 0.0
		var weightedPerf = 0.0
		var atkWonSum = 0.0
		var atkPlayedSum = 0.0
		var defWonSum = 0.0
		var defPlayedSum = 0.0
		var bestActPerf = 0
		var actCount = 0
		
		for idx in chronological.indices {
			let age = n - 1 - idx
			let weight = pow(0.88, Double(age))
			let obs = chronological[idx]
			
			weightSum += weight
			weightedWin += weight * (obs.won ? 1.0 : (obs.tied ? 0.5 : 0.0))
			weightedPerf += weight * Double(obs.analytics.performanceScore)
			
			atkWonSum += weight * Double(obs.analytics.attackHalf.roundsWon)
			atkPlayedSum += weight * Double(obs.analytics.attackHalf.roundsPlayed)
			defWonSum += weight * Double(obs.analytics.defenseHalf.roundsWon)
			defPlayedSum += weight * Double(obs.analytics.defenseHalf.roundsPlayed)
			
			if obs.inSelectedAct {
				actCount += 1
				bestActPerf = max(bestActPerf, obs.analytics.performanceScore)
			}
		}
		
		let overallWR = weightSum > 0 ? (weightedWin / weightSum) : 0
		let avgPerf = weightSum > 0 ? (weightedPerf / weightSum) : 0
		let atkWR = atkPlayedSum > 0 ? (atkWonSum / atkPlayedSum) : 0
		let defWR = defPlayedSum > 0 ? (defWonSum / defPlayedSum) : 0
		
		return WeightedPillars(
			overallWinRate: overallWR,
			avgPerformance: avgPerf,
			attackWinRate: atkWR,
			defenseWinRate: defWR,
			bestActPerf: bestActPerf,
			actMatchCount: actCount
		)
	}
	
	private static func computeScore(observations: [RawObservation]) -> Int {
		guard !observations.isEmpty else { return 0 }
		let p = computeWeightedPillars(from: observations)
		
		let normalizedPerf = min(1.0, max(0.0, p.avgPerformance / 500.0))
		let rawComposite = (
			0.35 * p.overallWinRate
			+ 0.30 * normalizedPerf
			+ 0.175 * p.attackWinRate
			+ 0.175 * p.defenseWinRate
		) * 500.0
		
		// During the 5-match calibration window, stabilize early variance around a baseline before unlocking full 0-500 range.
		let alpha = min(1.0, 0.45 + 0.55 * Double(observations.count - 1) / Double(MapRatingReport.calibrationRequiredMatches - 1))
		let stabilized = 225.0 + (rawComposite - 225.0) * alpha
		let actBonus = p.actMatchCount > 0 ? (Double(p.bestActPerf) / 500.0) * 12.0 : 0.0
		return max(0, min(500, Int((stabilized + actBonus).rounded())))
	}
}
