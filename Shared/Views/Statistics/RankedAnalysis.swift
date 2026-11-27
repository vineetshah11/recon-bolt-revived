import Foundation
import ValorantAPI

@available(iOS 16.0, *)
struct RankedAnalysis {
	enum Window: String, CaseIterable, Identifiable {
		case last5 = "Last 5"
		case last10 = "Last 10"
		case last20 = "Last 20"
		case currentAct = "Current Act"
		
		var id: String { rawValue }
	}
	
	enum Outcome: String, Hashable {
		case win, loss, draw
		
		var badgeText: String {
			switch self {
			case .win: return "WIN"
			case .loss: return "LOSS"
			case .draw: return "DRAW"
			}
		}
	}
	
	struct MatchEntry: Identifiable {
		var id: Match.ID
		var update: CompetitiveUpdate
		var startTime: Date
		var mapID: MapID
		var outcome: Outcome
		var ratingEarned: Int
		var performanceBonus: Int
		var hasDetails: Bool
		var ownRounds: Int?
		var enemyRounds: Int?
		var agentID: Agent.ID?
		var acs: Double?
		var lobbyAvgACS: Double?
		var lobbyPlace: Int?
		var totalLobbyPlayers: Int?
		var kills: Int?
		var deaths: Int?
		var assists: Int?
		var score: Int
		var damage: Int
		var roundsPlayed: Int
		var headshots: Int
		var hits: Int
		var avgLobbyTier: Int?
	}
	
	struct HiddenMMREstimate {
		enum Signal: Hashable {
			case muchHigher
			case slightlyHigher
			case aligned
			case slightlyLower
			case muchLower
			case insufficientData
			
			var headline: String {
				switch self {
				case .muchHigher:
					return "Your hidden MMR looks clearly higher than your rank"
				case .slightlyHigher:
					return "Your hidden MMR looks slightly higher than your rank"
				case .aligned:
					return "Your hidden MMR looks aligned with your rank"
				case .slightlyLower:
					return "Your hidden MMR looks slightly lower than your rank"
				case .muchLower:
					return "Your hidden MMR looks lower than your rank"
				case .insufficientData:
					return "Play ranked matches to estimate your hidden MMR"
				}
			}
			
			var shortLabel: String {
				switch self {
				case .muchHigher: return "Much Higher"
				case .slightlyHigher: return "Slightly Higher"
				case .aligned: return "Aligned"
				case .slightlyLower: return "Slightly Lower"
				case .muchLower: return "Lower"
				case .insufficientData: return "No Data"
				}
			}
			
			var isPositive: Bool? {
				switch self {
				case .muchHigher, .slightlyHigher: return true
				case .aligned: return nil
				case .slightlyLower, .muchLower: return false
				case .insufficientData: return nil
				}
			}
		}
		
		var signal: Signal
		var avgRRPerWin: Double?
		var avgRRPerLoss: Double?
		var avgPerformanceBonus: Double?
		var avgLobbyTierDelta: Double?
		var rrSampleCount: Int
	}
	
	struct RankOutlook {
		var avgRRPerMatch: Double
		var nextTierName: String?
		var rrToRankUp: Int
		var estimatedMatchesToRankUp: Int?
		var summaryText: String
	}
	
	struct MapSummary {
		var mapID: MapID
		var wins: Int
		var losses: Int
		var draws: Int
		var total: Int
		
		var winRate: Double {
			total > 0 ? Double(wins) * Double(100) / Double(total) : Double(0)
		}
	}
	
	struct LobbyPerformanceSummary {
		enum Verdict: Hashable {
			case carrying
			case aboveAverage
			case onPar
			case belowAverage
			
			var headline: String {
				switch self {
				case .carrying: return "You're carrying your lobbies"
				case .aboveAverage: return "You're outperforming your lobbies"
				case .onPar: return "You're holding your own in your lobbies"
				case .belowAverage: return "Your lobbies have been tough lately"
				}
			}
		}
		
		var detailedMatchCount: Int
		var userACS: Double
		var lobbyAvgACS: Double
		var acsDiffPercent: Double
		var kd: Double
		var hsPercent: Double
		var adr: Double
		var avgLobbyPlace: Double
		var top3Count: Int
		var verdict: Verdict
	}
	
	struct AgentSummary: Identifiable {
		var id: Agent.ID { agentID }
		var agentID: Agent.ID
		var wins: Int
		var losses: Int
		var draws: Int
		var totalGames: Int
		var decidedGames: Int
		var winRate: Double
	}
	
	var window: Window
	var totalRankedAvailable: Int
	var currentTier: Int
	var currentTierName: String
	var currentRR: Int
	var currentELO: Int
	var lastRRChange: Int?
	var peakRank: RankSnapshot?
	var peakRankName: String?
	var isImmortalPlus: Bool
	
	var matches: [MatchEntry]
	var missingDetailsIDs: [Match.ID]
	var hiddenMMR: HiddenMMREstimate
	var rankOutlook: RankOutlook
	
	var wins: Int
	var losses: Int
	var draws: Int
	var totalWinRate: Double
	var decidedWinRate: Double
	var streakCount: Int
	var streakOutcome: Outcome?
	var streakDescription: String?
	var bestMap: MapSummary?
	
	var lobbyPerformance: LobbyPerformanceSummary?
	var recommendation: String
	var agentPerformance: [AgentSummary]
	
	init(
		userID: User.ID,
		updates: [CompetitiveUpdate],
		detailsByID: [Match.ID: MatchDetails],
		summary: CareerSummary?,
		seasons: SeasonCollection.Accessor?,
		window: Window = .last5
	) {
		self.window = window
		
		let allRanked = updates
			.filter { $0.isRanked && !$0.isDodge }
			.sorted { $0.startTime > $1.startTime }
		self.totalRankedAvailable = allRanked.count
		
		let currentAct = seasons?.currentAct()
		let tiers = seasons?.currentTiers()
		let lowestImm = SeasonGoalStore.lowestImmortalTier(in: tiers)
		
		var resolvedRank = SeasonGoalStore.currentRank(summary: summary, matchList: nil, act: currentAct)
		if resolvedRank.tier < 3, let latest = allRanked.first {
			resolvedRank = (latest.tierAfterUpdate, latest.tierProgressAfterUpdate, resolvedRank.gamesNeeded)
		}
		
		let resolvedELO = SeasonGoalStore.elo(tier: resolvedRank.tier, rr: resolvedRank.rr, tiers: tiers)
		self.currentTier = resolvedRank.tier
		self.currentRR = resolvedRank.rr
		self.currentTierName = tiers?.tier(resolvedRank.tier)?.name
			?? (resolvedRank.tier == 0 ? "Unranked" : "Tier \(resolvedRank.tier)")
		self.currentELO = resolvedELO
		self.isImmortalPlus = resolvedRank.tier >= lowestImm && resolvedRank.tier >= 3
		self.lastRRChange = allRanked.first?.ratingEarned
		
		let peak = summary?.peakRank(seasons: seasons)
		self.peakRank = peak
		self.peakRankName = peak.flatMap { seasons?.tierInfo($0)?.name }
		
		let windowedUpdates: [CompetitiveUpdate] = {
			switch window {
			case .last5: return Array(allRanked.prefix(5))
			case .last10: return Array(allRanked.prefix(10))
			case .last20: return Array(allRanked.prefix(20))
			case .currentAct:
				if let currentAct {
					return allRanked.filter { currentAct.timeSpan.contains($0.startTime) }
				}
				return Array(allRanked.prefix(20))
			}
		}()
		
		var entries: [MatchEntry] = []
		var missingIDs: [Match.ID] = []
		
		for upd in windowedUpdates {
			let details = detailsByID[upd.id]
			if details == nil {
				missingIDs.append(upd.id)
			}
			let player = details?.players.firstElement(withID: userID)
			
			let outcome: Outcome = {
				if let details, let player {
					if let winner = details.teams.first(where: \.won) {
						return winner.id == player.teamID ? .win : .loss
					}
					return .draw
				}
				if upd.ratingEarned > 5 { return .win }
				if upd.ratingEarned < 0 { return .loss }
				return .draw
			}()
			
			var ownRounds: Int?
			var enemyRounds: Int?
			if let details, let player, details.teams.count == 2 {
				ownRounds = details.teams.first(where: { $0.id == player.teamID })?.roundsWon
				enemyRounds = details.teams.first(where: { $0.id != player.teamID })?.roundsWon
			}
			
			var userACS: Double?
			var lobbyAvgACS: Double?
			var lobbyPlace: Int?
			var totalLobbyPlayers: Int?
			var avgTier: Int?
			var totalDamage = 0
			var headshots = 0
			var hits = 0
			
			if let details {
				let activePlayers = details.players.filter { $0.teamID != .neutral }
				var totalLobbyACS = Double(0)
				var tierSum = 0
				var tierCount = 0
				var acsByPlayerID: [(id: Player.ID, acs: Double)] = []
				acsByPlayerID.reserveCapacity(activePlayers.count)
				
				for p in activePlayers {
					let pRounds = max(1, p.stats?.roundsPlayed ?? details.roundResults.count)
					let pACS = Double(p.stats?.score ?? 0) / Double(pRounds)
					acsByPlayerID.append((p.id, pACS))
					totalLobbyACS += pACS
					if p.id == userID {
						userACS = pACS
					}
					if p.competitiveTier >= 3 {
						tierSum += p.competitiveTier
						tierCount += 1
					}
				}
				
				if !activePlayers.isEmpty {
					lobbyAvgACS = totalLobbyACS / Double(activePlayers.count)
					totalLobbyPlayers = activePlayers.count
				}
				if let userACS {
					lobbyPlace = 1 + acsByPlayerID.filter { $0.id != userID && $0.acs > userACS + Double(0.0001) }.count
				}
				if tierCount > 0 {
					avgTier = Int((Double(tierSum) / Double(tierCount)).rounded())
				}
				
				for round in details.roundResults {
					guard let ps = round.playerStats.first(where: { $0.subject == userID }) else { continue }
					for dmg in ps.damageDealt {
						totalDamage += dmg.damage
						headshots += dmg.headshots
						hits += dmg.headshots + dmg.bodyshots + dmg.legshots
					}
				}
			}
			
			entries.append(MatchEntry(
				id: upd.id,
				update: upd,
				startTime: upd.startTime,
				mapID: details?.matchInfo.mapID ?? upd.mapID ?? .ascent,
				outcome: outcome,
				ratingEarned: upd.ratingEarned,
				performanceBonus: upd.performanceBonus,
				hasDetails: details != nil,
				ownRounds: ownRounds,
				enemyRounds: enemyRounds,
				agentID: player?.agentID,
				acs: userACS,
				lobbyAvgACS: lobbyAvgACS.flatMap { $0 > Double(0) ? $0 : nil },
				lobbyPlace: lobbyPlace,
				totalLobbyPlayers: totalLobbyPlayers,
				kills: player?.stats?.kills,
				deaths: player?.stats?.deaths,
				assists: player?.stats?.assists,
				score: player?.stats?.score ?? 0,
				damage: totalDamage,
				roundsPlayed: player?.stats?.roundsPlayed ?? (details?.roundResults.count ?? 0),
				headshots: headshots,
				hits: hits,
				avgLobbyTier: avgTier
			))
		}
		
		self.matches = entries
		self.missingDetailsIDs = missingIDs
		
		// Form & streaks
		var winCount = 0
		var lossCount = 0
		var drawCount = 0
		for e in entries {
			switch e.outcome {
			case .win: winCount += 1
			case .loss: lossCount += 1
			case .draw: drawCount += 1
			}
		}
		self.wins = winCount
		self.losses = lossCount
		self.draws = drawCount
		let decided = winCount + lossCount
		self.decidedWinRate = decided > 0 ? Double(winCount) * Double(100) / Double(decided) : Double(0)
		self.totalWinRate = !entries.isEmpty ? Double(winCount) * Double(100) / Double(entries.count) : Double(0)
		
		var sCount = 0
		let firstOutcome = entries.first?.outcome
		if let firstOutcome, firstOutcome != .draw {
			for e in entries {
				if e.outcome == firstOutcome {
					sCount += 1
				} else {
					break
				}
			}
			self.streakCount = sCount
			self.streakOutcome = firstOutcome
			self.streakDescription = firstOutcome == .win
				? "\(sCount) win\(sCount == 1 ? "" : "s") in a row"
				: "\(sCount) loss\(sCount == 1 ? "" : "es") in a row"
		} else {
			self.streakCount = 0
			self.streakOutcome = firstOutcome
			self.streakDescription = firstOutcome == .draw ? "Last match drawn" : nil
		}
		
		// Best Map
		var mapBuckets: [MapID: MapSummary] = [:]
		for e in entries {
			var b = mapBuckets[e.mapID] ?? MapSummary(mapID: e.mapID, wins: 0, losses: 0, draws: 0, total: 0)
			b.total += 1
			switch e.outcome {
			case .win: b.wins += 1
			case .loss: b.losses += 1
			case .draw: b.draws += 1
			}
			mapBuckets[e.mapID] = b
		}
		self.bestMap = mapBuckets.values
			.filter { $0.wins > 0 }
			.max { lhs, rhs in
				if abs(lhs.winRate - rhs.winRate) > 0.001 { return lhs.winRate < rhs.winRate }
				if lhs.wins != rhs.wins { return lhs.wins < rhs.wins }
				return lhs.total < rhs.total
			}
		
		// Lobby Performance
		let detailedEntries = entries.filter(\.hasDetails)
		let lobbyPerf: LobbyPerformanceSummary? = {
			guard !detailedEntries.isEmpty else { return nil }
			
			let totalScore = detailedEntries.reduce(0) { $0 + $1.score }
			let totalRounds = detailedEntries.reduce(0) { $0 + $1.roundsPlayed }
			let totalDamage = detailedEntries.reduce(0) { $0 + $1.damage }
			let totalKills = detailedEntries.reduce(0) { $0 + ($1.kills ?? 0) }
			let totalDeaths = detailedEntries.reduce(0) { $0 + ($1.deaths ?? 0) }
			let totalHeadshots = detailedEntries.reduce(0) { $0 + $1.headshots }
			let totalHits = detailedEntries.reduce(0) { $0 + $1.hits }
			
			let userACS: Double = {
				if totalRounds > 0 { return Double(totalScore) / Double(totalRounds) }
				let acsValues = detailedEntries.compactMap(\.acs)
				return acsValues.isEmpty ? Double(0) : acsValues.reduce(Double(0), +) / Double(acsValues.count)
			}()
			
			let lobbyACSValues = detailedEntries.compactMap(\.lobbyAvgACS)
			let lobbyAvgACS = lobbyACSValues.isEmpty
				? userACS
				: lobbyACSValues.reduce(Double(0), +) / Double(lobbyACSValues.count)
			let acsDiffPct = lobbyAvgACS > Double(0)
				? (userACS - lobbyAvgACS) * Double(100) / lobbyAvgACS
				: Double(0)
			
			let kd = totalDeaths > 0 ? Double(totalKills) / Double(totalDeaths) : Double(totalKills)
			let hsPercent = totalHits > 0 ? Double(totalHeadshots) * Double(100) / Double(totalHits) : Double(0)
			let adr = totalRounds > 0 ? Double(totalDamage) / Double(totalRounds) : Double(0)
			
			let places = detailedEntries.compactMap(\.lobbyPlace)
			let avgPlace = places.isEmpty ? Double(5) : Double(places.reduce(0, +)) / Double(places.count)
			let top3 = places.filter { $0 <= 3 }.count
			
			let verdict: LobbyPerformanceSummary.Verdict = {
				if acsDiffPct >= Double(15) || avgPlace <= Double(3.0) { return .carrying }
				if acsDiffPct >= Double(5) || avgPlace <= Double(4.5) { return .aboveAverage }
				if acsDiffPct >= Double(-5) && avgPlace <= Double(6.5) { return .onPar }
				return .belowAverage
			}()
			
			return LobbyPerformanceSummary(
				detailedMatchCount: detailedEntries.count,
				userACS: userACS,
				lobbyAvgACS: lobbyAvgACS,
				acsDiffPercent: acsDiffPct,
				kd: kd,
				hsPercent: hsPercent,
				adr: adr,
				avgLobbyPlace: avgPlace,
				top3Count: top3,
				verdict: verdict
			)
		}()
		self.lobbyPerformance = lobbyPerf
		
		// Hidden MMR estimation
		let winUpdates = entries.filter { $0.outcome == .win }
		let lossUpdates = entries.filter { $0.outcome == .loss }
		let avgWinRR: Double? = winUpdates.isEmpty
			? nil
			: Double(winUpdates.reduce(0) { $0 + $1.ratingEarned }) / Double(winUpdates.count)
		let avgLossRR: Double? = lossUpdates.isEmpty
			? nil
			: Double(lossUpdates.reduce(0) { $0 + $1.ratingEarned }) / Double(lossUpdates.count)
		
		let totalPerfBonus = entries.reduce(0) { $0 + max(0, $1.performanceBonus) }
		let avgPerfBonus: Double? = (!entries.isEmpty && totalPerfBonus > 0)
			? Double(totalPerfBonus) / Double(entries.count)
			: nil
		
		let tierDeltas: [Double] = entries.compactMap { entry in
			guard let lobbyTier = entry.avgLobbyTier, resolvedRank.tier >= 3 else { return nil }
			return Double(lobbyTier - resolvedRank.tier)
		}
		let avgTierDelta: Double? = tierDeltas.isEmpty
			? nil
			: tierDeltas.reduce(Double(0), +) / Double(tierDeltas.count)
		
		let signal: HiddenMMREstimate.Signal = {
			guard !entries.isEmpty else { return .insufficientData }
			if let win = avgWinRR, let loss = avgLossRR {
				let diff = (win - abs(loss)) + Double(0.5) * (avgTierDelta ?? Double(0))
				if diff >= Double(6) { return .muchHigher }
				if diff >= Double(2) { return .slightlyHigher }
				if diff > Double(-2) { return .aligned }
				if diff > Double(-6) { return .slightlyLower }
				return .muchLower
			} else if let win = avgWinRR {
				if win >= Double(23) { return .muchHigher }
				if win >= Double(19) { return .slightlyHigher }
				if win >= Double(15) { return .aligned }
				return .slightlyLower
			} else if let loss = avgLossRR {
				let absLoss = abs(loss)
				if absLoss <= Double(14) { return .slightlyHigher }
				if absLoss <= Double(18) { return .aligned }
				if absLoss <= Double(22) { return .slightlyLower }
				return .muchLower
			} else {
				return .aligned
			}
		}()
		
		let mmrEstimate = HiddenMMREstimate(
			signal: signal,
			avgRRPerWin: avgWinRR,
			avgRRPerLoss: avgLossRR,
			avgPerformanceBonus: avgPerfBonus,
			avgLobbyTierDelta: avgTierDelta,
			rrSampleCount: entries.count
		)
		self.hiddenMMR = mmrEstimate
		
		// Rank Outlook
		let avgRRPerMatch = entries.isEmpty
			? Double(0)
			: Double(entries.reduce(0) { $0 + $1.ratingEarned }) / Double(entries.count)
		let sortedTierNumbers = (tiers?.tiers.values.map(\.number).filter { $0 >= 3 }.sorted()) ?? Array(3...27)
		let highestTier = sortedTierNumbers.last ?? 27
		let nextTierNumber = sortedTierNumbers.first(where: { $0 > resolvedRank.tier })
		let nextTierName = (resolvedRank.tier >= 3 && resolvedRank.tier < highestTier)
			? (nextTierNumber.flatMap { tiers?.tier($0)?.name } ?? "Next Rank")
			: (resolvedRank.tier < 3 ? (tiers?.tier(sortedTierNumbers.first ?? 3)?.name ?? "Iron 1") : nil)
		
		let rrToGo: Int = {
			if resolvedRank.tier < 3 { return 100 }
			if resolvedRank.tier >= highestTier { return 0 }
			if resolvedRank.tier >= lowestImm, let nextTierNumber {
				return max(1, SeasonGoalStore.targetThresholdElo(for: nextTierNumber, tiers: tiers) - resolvedELO)
			}
			return max(1, 100 - resolvedRank.rr)
		}()
		
		let estMatches: Int? = (resolvedRank.tier >= 3 && rrToGo > 0 && avgRRPerMatch > Double(0.25))
			? Int(ceil(Double(rrToGo) / avgRRPerMatch))
			: nil
		
		let outlookText: String = {
			if resolvedRank.tier < 3 {
				return "Complete your placement matches to establish a current rank and projection."
			}
			guard let nextTierName else {
				return "You've reached the highest rank."
			}
			let paceStr = String(format: "%+.1f", avgRRPerMatch)
			if let estMatches {
				return "At this pace (\(paceStr) RR per match) you could reach \(nextTierName) in about \(estMatches) match\(estMatches == 1 ? "" : "es")."
			}
			return "At your current pace (\(paceStr) RR per match), a positive RR trend is needed to climb to \(nextTierName)."
		}()
		
		self.rankOutlook = RankOutlook(
			avgRRPerMatch: avgRRPerMatch,
			nextTierName: nextTierName,
			rrToRankUp: rrToGo,
			estimatedMatchesToRankUp: estMatches,
			summaryText: outlookText
		)
		
		// What to do next
		self.recommendation = Self.buildRecommendation(mmr: mmrEstimate.signal, verdict: lobbyPerf?.verdict)
		
		// Agent Performance sorted by Win Rate descending
		var agentBuckets: [Agent.ID: (wins: Int, losses: Int, draws: Int, total: Int)] = [:]
		for e in detailedEntries {
			guard let aid = e.agentID else { continue }
			var b = agentBuckets[aid] ?? (0, 0, 0, 0)
			b.total += 1
			switch e.outcome {
			case .win: b.wins += 1
			case .loss: b.losses += 1
			case .draw: b.draws += 1
			}
			agentBuckets[aid] = b
		}
		self.agentPerformance = agentBuckets.map { aid, b in
			let d = b.wins + b.losses
			let wr = d > 0 ? Double(b.wins) * Double(100) / Double(d) : Double(0)
			return AgentSummary(
				agentID: aid,
				wins: b.wins,
				losses: b.losses,
				draws: b.draws,
				totalGames: b.total,
				decidedGames: d,
				winRate: wr
			)
		}
		.sorted { lhs, rhs in
			if (lhs.decidedGames > 0) != (rhs.decidedGames > 0) {
				return lhs.decidedGames > 0
			}
			if abs(lhs.winRate - rhs.winRate) > 0.001 { return lhs.winRate > rhs.winRate }
			if lhs.wins != rhs.wins { return lhs.wins > rhs.wins }
			return lhs.totalGames > rhs.totalGames
		}
	}
	
	private static func buildRecommendation(
		mmr: HiddenMMREstimate.Signal,
		verdict: LobbyPerformanceSummary.Verdict?
	) -> String {
		switch (mmr, verdict) {
		case (.muchHigher, .carrying), (.slightlyHigher, .carrying),
			 (.muchHigher, .aboveAverage), (.slightlyHigher, .aboveAverage):
			return "Your MMR and your performance both point up. Keep queuing; your rank should catch up soon."
		case (.muchHigher, _), (.slightlyHigher, _):
			return "Your RR gains outweigh your losses. Staying consistent in your lobbies should let you keep climbing."
		case (.aligned, .carrying), (.aligned, .aboveAverage):
			return "You're consistently outperforming your lobbies. Keep up the high individual impact and your MMR will push upward."
		case (.slightlyLower, .carrying), (.muchLower, .carrying),
			 (.slightlyLower, .aboveAverage), (.muchLower, .aboveAverage):
			return "Your in-game impact is strong even if RR gains are lagging. Turning close rounds into wins will pull your hidden MMR back up."
		case (.slightlyLower, _), (.muchLower, _):
			return "Focus on your highest win-rate agents and tighter round fundamentals to stabilize your RR gains and rebuild MMR."
		case (.insufficientData, _):
			return "Play a few ranked matches to unlock personalized MMR and lobby performance guidance."
		default:
			return "Your results and MMR are balanced right now. Focus on your best maps and agents to build momentum."
		}
	}
}
