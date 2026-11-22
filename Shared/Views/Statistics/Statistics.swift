import Foundation
import ValorantAPI
import HandyOperators

final class Statistics {
	// for icons
	let modeByQueue: [QueueID?: GameMode.ID]
	
	let userID: User.ID
	let matches: [MatchDetails]
	let playtime: Playtime
	let hitDistribution: HitDistribution
	let winRate: WinRate
	let overview: Overview
	let kdRatio: KDRatio
	let economy: Economy
	
	init(userID: User.ID, matches: [MatchDetails], competitiveUpdates: [CompetitiveUpdate] = []) {
		self.userID = userID
		self.matches = matches
		
		modeByQueue = .init(
			matches.map { ($0.matchInfo.queueID, $0.matchInfo.modeID) },
			uniquingKeysWith: { old, new in old }
		)
		
		let analyticsByMatch: [Match.ID: MatchAnalytics] = Dictionary(
			uniqueKeysWithValues: matches.map { ($0.id, MatchAnalytics(details: $0)) }
		)
		
		let playtime = Playtime(userID: userID, matches: matches)
		let hitDistribution = HitDistribution(userID: userID, matches: matches)
		let winRate = WinRate(userID: userID, matches: matches)
		self.playtime = playtime
		self.hitDistribution = hitDistribution
		self.winRate = winRate
		self.overview = Overview(
			userID: userID,
			matches: matches,
			competitiveUpdates: competitiveUpdates,
			analyticsByMatch: analyticsByMatch,
			winRate: winRate,
			playtime: playtime,
			hitDistribution: hitDistribution
		)
		self.kdRatio = KDRatio(
			userID: userID,
			matches: matches,
			analyticsByMatch: analyticsByMatch,
			hitDistribution: hitDistribution
		)
		self.economy = Economy(userID: userID, matches: matches)
	}
	
	struct Playtime {
		var total: Entry = .init()
		var byQueue: [QueueID?: Entry] = [:]
		var byAgent: [Agent.ID: Entry] = [:]
		var byPremade: [User.ID: Entry] = [:]
		var byNonPremade: [User.ID: Entry] = [:]
		var byMap: [MapID: Entry] = [:]
		
		init(userID: User.ID, matches: [MatchDetails]) {
			for match in matches {
				let queue = match.matchInfo.queueID
				total += match
				byQueue[queue, default: .init()] += match
				byMap[match.matchInfo.mapID, default: .init()] += match
				
				guard let user = match.players.firstElement(withID: userID) else { continue }
				if let agentID = user.agentID {
					byAgent[agentID, default: .init()] += match
				}
				for player in match.players {
					guard player.id != userID else { continue }
					if player.partyID == user.partyID {
						byPremade[player.id, default: .init()] += match
					} else {
						byNonPremade[player.id, default: .init()] += match
					}
				}
			}
			byNonPremade = byNonPremade.filter { $0.value.games.count > 1 }
		}
		
		struct Entry {
			var time: TimeInterval = 0
			var games: [CompetitiveUpdate] = [] // need these to display as match list
			
			static func += (entry: inout Self, match: MatchDetails) {
				entry.games.append(.init(
					id: match.id,
					mapID: match.matchInfo.mapID,
					startTime: match.matchInfo.gameStart
				))
				entry.time += match.matchInfo.gameLength
			}
			
			static func + (lhs: Self, rhs: Self) -> Self {
				.init(time: lhs.time + rhs.time, games: lhs.games + rhs.games)
			}
		}
	}
	
	struct HitDistribution {
		var overall = Tally()
		var byWeapon: [Weapon.ID: Tally] = [:]
		var byMatch: [(time: Date, tally: Tally)]
		
		init(userID: User.ID, matches: [MatchDetails]) {
			let rounds = matches
				.lazy
				.flatMap(\.roundResults)
			for round in rounds {
				guard let stats = round.stats(for: userID) else { continue }
				guard let startingWeapon = stats.economy.weapon else { continue }
				
				for damage in stats.damageDealt {
					overall += damage
				}
				
				// we don't get nearly enough information from the data to say anything with confidence here, so we'll use a heuristic to approximate reality:
				// we know what weapon the user had at the start of the round, and when they get a kill, we know the weapon or ability used
				// so we'll track the last known weapon for the user as the round plays out, and assume all damage dealt to an enemy was done with the last known weapon at their time of death or the end of the round
				var damages: [Player.ID: Tally] = stats.damageDealt.reduce(into: [:]) {
					$0[$1.receiver, default: .zero] += $1
				}
				
				var lastKnownWeapon = startingWeapon
				let allKillsInOrder = round.playerStats
					.lazy
					.flatMap(\.kills)
					.sorted(on: \.roundTimeMillis)
				for kill in allKillsInOrder {
					// update weapon
					if kill.killer == userID {
						lastKnownWeapon = kill.finishingDamage.weapon ?? lastKnownWeapon
					}
					// if we've damaged the victim, assume we used the last weapon we're known to have had at the time they died to do all damage to them
					if let damage = damages.removeValue(forKey: kill.victim) {
						byWeapon[lastKnownWeapon, default: .zero] += damage
					}
				}
				
				// assume last known weapon for all damage without a known kill
				for damage in damages.values {
					byWeapon[lastKnownWeapon, default: .zero] += damage
				}
			}
			
			// this can happen for ability-only damage
			byWeapon = byWeapon.filter { $0.value != .zero }
			
			byMatch = matches
				.lazy
				.map { (
					$0.matchInfo.gameStart,
					$0.roundResults.lazy
						.compactMap { $0.stats(for: userID) }
						.flatMap(\.damageDealt)
						.reduce(into: Tally.zero, +=) as Tally
				) }
				.filter { $0.tally != .zero }
		}
		
		struct Tally: Equatable {
			typealias Raw = RoundResult.PlayerStats.Damage
			
			public var headshots = 0
			public var bodyshots = 0
			public var legshots = 0
			
			var total: Int { headshots + bodyshots + legshots }
			
			static let zero = Self()
			
			static func += (lhs: inout Self, rhs: Raw) {
				lhs += .init(rhs)
			}
			
			static func += (lhs: inout Self, rhs: Self) {
				lhs.headshots += rhs.headshots
				lhs.bodyshots += rhs.bodyshots
				lhs.legshots += rhs.legshots
			}
		}
	}
	
	struct WinRate {
		var byDay: [Date: Tally] = [:]
		var byMap: [MapID: Tally] = [:]
		var byAgent: [Agent.ID: Tally] = [:]
		var byPremade: [User.ID: Tally] = [:]
		var byStartingSide: [Side: [MapID: Tally]] = [:]
		var roundsBySide: [MapID: [Side: Tally]] = [:]
		var roundsByLoadoutDelta: [Int: Tally] = [:]
		
		init(userID: User.ID, matches: [MatchDetails]) {
			for match in matches {
				guard let player = match.players.firstElement(withID: userID) else { continue }
				let teamID = player.teamID
				let winner = match.teams.first(where: \.won)
				let outcome: Outcome = winner == nil ? .draw
				: winner?.id == teamID ? .win : .loss
				
				let day = Calendar.current.startOfDay(for: match.matchInfo.gameStart)
				byDay[day, default: .zero] += outcome
				
				let map = match.matchInfo.mapID
				byMap[map, default: .zero] += outcome
				
				if let agentID = player.agentID {
					byAgent[agentID, default: .zero] += outcome
				}
				
				for teammate in match.players where teammate.id != userID && teammate.partyID == player.partyID {
					byPremade[teammate.id, default: .zero] += outcome
				}
				
				if match.teams.count == 2, let startingSide = Side(teamID), let structure = match.roundStructure {
					let playerTeams = Dictionary(uniqueKeysWithValues: match.players.lazy.map { ($0.id, $0.teamID) })
					
					byStartingSide[startingSide, default: [:]][map, default: .zero] += outcome
					for round in match.roundResults {
						guard round.outcome != .surrendered else { break }
						let side = startingSide.flipped(if: structure.areRolesSwapped(inRound: round.number))
						let outcome: Outcome = round.winningTeam == teamID ? .win : .loss
						roundsBySide[map, default: [:]][side, default: .zero] += outcome
						
						let averageLoadoutValues: [Team.ID: Int] = [Team.ID: [RoundResult.PlayerStats]](
							grouping: round.playerStats.filter { playerTeams[$0.subject] != nil },
							by: { playerTeams[$0.subject]! }
						)
						.mapValues { $0.lazy.map(\.economy.loadoutValue).reduce(0, +) / max(1, $0.count) }
						if
							let ownLoadout = averageLoadoutValues[teamID],
							let enemyLoadout = averageLoadoutValues.onlyElement(where: { $0.key != teamID })?.value
						{
							let loadoutDelta = ownLoadout - enemyLoadout
							roundsByLoadoutDelta[loadoutDelta, default: .zero] += outcome
						}
					}
				}
			}
		}
		
		enum Outcome {
			case win, draw, loss
		}
		
		struct Tally: Equatable {
			var wins = 0
			var draws = 0
			var losses = 0
			
			var total: Int { wins + draws + losses }
			
			static let zero = Self()
			
			static func + (lhs: Self, rhs: Self) -> Self {
				lhs <- { $0 += rhs }
			}
			
			static func += (lhs: inout Self, rhs: Self) {
				lhs.wins += rhs.wins
				lhs.draws += rhs.draws
				lhs.losses += rhs.losses
			}
			
			static func += (tally: inout Self, outcome: Outcome) {
				switch outcome {
				case .win:
					tally.wins += 1
				case .draw:
					tally.draws += 1
				case .loss:
					tally.losses += 1
				}
			}
		}
		
		enum Side: Hashable, CaseIterable {
			case attacking
			case defending
			
			func flipped(`if` condition: Bool) -> Self {
				guard condition else { return self }
				switch self {
				case .attacking: return .defending
				case .defending: return .attacking
				}
			}
			
			init?(_ team: Team.ID) {
				switch team {
				case .red:
					self = .attacking
				case .blue:
					self = .defending
				default:
					return nil
				}
			}
		}
	}
	
	struct Overview {
		// Performance
		var matchesCount = 0
		var wins = 0
		var losses = 0
		var draws = 0
		var winRate: Double = Double(0)
		var totalKills = 0
		var totalDeaths = 0
		var totalAssists = 0
		var kdRatio: Double = Double(0)
		var kadRatio: Double = Double(0)
		var headshots = 0
		var totalHits = 0
		var hsPercent: Double = Double(0)
		var totalPlaytime: TimeInterval = 0
		var avgRRChange: Double?
		
		// Rank Rating
		var rankedMatchCount = 0
		var avgRRGain: Double?
		var avgRRLoss: Double?
		var netRR = 0
		var bestRRGain: Int?
		var worstRRLoss: Int?
		var currentStreakCount = 0
		var currentStreakIsWin = true
		var longestWinStreak = 0
		var longestLossStreak = 0
		
		// Combat Stats
		var averageACS: Double = Double(0)
		var averageADR: Double = Double(0)
		var averageKAST: Double = Double(0)
		var firstBloods = 0
		var firstDeaths = 0
		var clutchesWon = 0
		var clutchesAttempted = 0
		var clutchWinRate: Double = Double(0)
		var tripleKills = 0
		var quadraKills = 0
		var aces = 0
		var longestKillStreak = 0
		var matchMVPs = 0
		var teamMVPs = 0
		
		// Lobby Overview
		var averageLobbyTier: Int?
		var averageAccountLevel: Int?
		var averageMatchDuration: TimeInterval = 0
		var totalRoundsPlayed = 0
		var roundWinRate: Double = Double(0)
		
		init(
			userID: User.ID,
			matches: [MatchDetails],
			competitiveUpdates: [CompetitiveUpdate],
			analyticsByMatch: [Match.ID: MatchAnalytics],
			winRate: WinRate,
			playtime: Playtime,
			hitDistribution: HitDistribution
		) {
			self.matchesCount = matches.count
			self.totalPlaytime = playtime.total.time
			self.averageMatchDuration = matches.isEmpty ? 0 : playtime.total.time / TimeInterval(matches.count)
			
			let overallWinTally = winRate.byMap.values.reduce(into: WinRate.Tally.zero, +=)
			self.wins = overallWinTally.wins
			self.losses = overallWinTally.losses
			self.draws = overallWinTally.draws
			let decided = overallWinTally.wins + overallWinTally.losses
			self.winRate = decided > 0 ? Double(overallWinTally.wins) * Double(100) / Double(decided) : Double(0)
			
			self.headshots = hitDistribution.overall.headshots
			self.totalHits = hitDistribution.overall.total
			self.hsPercent = totalHits > 0 ? Double(headshots) * Double(100) / Double(totalHits) : Double(0)
			
			var scoreSum = 0
			var damageSum = 0
			var kastWeightedSum: Double = Double(0)
			var kastRoundCount = 0
			var roundsWonTotal = 0
			var tierSum = 0
			var tierCount = 0
			var levelSum = 0
			var levelCount = 0
			
			for match in matches {
				let analytics = analyticsByMatch[match.id]
				guard let player = match.players.firstElement(withID: userID) else { continue }
				
				if let s = player.stats {
					totalKills += s.kills
					totalDeaths += s.deaths
					totalAssists += s.assists
					scoreSum += s.score
					totalRoundsPlayed += s.roundsPlayed
				}
				
				if let pStats = analytics?.byPlayer[userID] {
					damageSum += pStats.totalDamage
					firstBloods += pStats.firstBloods
					firstDeaths += pStats.firstDeaths
					clutchesWon += pStats.clutchesWon
					clutchesAttempted += pStats.clutchesWon + pStats.clutchesLost
					tripleKills += pStats.multiKills[3, default: 0]
					quadraKills += pStats.multiKills[4, default: 0]
					aces += pStats.multiKills[5, default: 0]
					if !match.roundResults.isEmpty {
						kastWeightedSum += pStats.kastPercent * Double(match.roundResults.count)
						kastRoundCount += match.roundResults.count
					}
					let maxStreakInMatch = Self.maxKillStreak(in: match, userID: userID)
					longestKillStreak = max(longestKillStreak, maxStreakInMatch)
				}
				
				if analytics?.matchMVPID == userID {
					matchMVPs += 1
				} else if analytics?.teamMVPByTeam[player.teamID] == userID {
					teamMVPs += 1
				}
				
				for round in match.roundResults where round.outcome != .surrendered {
					if round.winningTeam == player.teamID {
						roundsWonTotal += 1
					}
				}
				
				for p in match.players where p.teamID != .neutral {
					if p.competitiveTier >= 3 {
						tierSum += p.competitiveTier
						tierCount += 1
					}
					if let lvl = p.accountLevel, lvl > 0 {
						levelSum += lvl
						levelCount += 1
					}
				}
			}
			
			self.kdRatio = totalDeaths > 0 ? Double(totalKills) / Double(totalDeaths) : Double(totalKills)
			self.kadRatio = totalDeaths > 0 ? Double(totalKills + totalAssists) / Double(totalDeaths) : Double(totalKills + totalAssists)
			self.averageACS = totalRoundsPlayed > 0 ? Double(scoreSum) / Double(totalRoundsPlayed) : Double(0)
			self.averageADR = totalRoundsPlayed > 0 ? Double(damageSum) / Double(totalRoundsPlayed) : Double(0)
			self.averageKAST = kastRoundCount > 0 ? kastWeightedSum / Double(kastRoundCount) : Double(0)
			self.clutchWinRate = clutchesAttempted > 0 ? Double(clutchesWon) * Double(100) / Double(clutchesAttempted) : Double(0)
			self.roundWinRate = totalRoundsPlayed > 0 ? Double(roundsWonTotal) * Double(100) / Double(totalRoundsPlayed) : Double(0)
			self.averageLobbyTier = tierCount > 0 ? Int((Double(tierSum) / Double(tierCount)).rounded()) : nil
			self.averageAccountLevel = levelCount > 0 ? Int((Double(levelSum) / Double(levelCount)).rounded()) : nil
			
			// Match streaks sorted chronologically
			let chronological = matches.sorted { $0.matchInfo.gameStart < $1.matchInfo.gameStart }
			var curWinRun = 0
			var curLossRun = 0
			var latestOutcomes: [Bool] = []
			for match in chronological {
				guard let player = match.players.firstElement(withID: userID),
					  let winner = match.teams.first(where: \.won) else { continue }
				let won = winner.id == player.teamID
				latestOutcomes.append(won)
				if won {
					curWinRun += 1
					curLossRun = 0
					longestWinStreak = max(longestWinStreak, curWinRun)
				} else {
					curLossRun += 1
					curWinRun = 0
					longestLossStreak = max(longestLossStreak, curLossRun)
				}
			}
			if let lastOutcome = latestOutcomes.last {
				currentStreakIsWin = lastOutcome
				var streak = 0
				for won in latestOutcomes.reversed() {
					if won == lastOutcome { streak += 1 } else { break }
				}
				currentStreakCount = streak
			}
			
			// Rank Rating summary over filtered matches
			let matchIDs = Set(matches.map(\.id))
			let rankedUpdates = competitiveUpdates.filter { matchIDs.contains($0.id) && $0.isRanked }
			self.rankedMatchCount = rankedUpdates.count
			if !rankedUpdates.isEmpty {
				let deltas = rankedUpdates.map(\.ratingEarned)
				let totalDelta = deltas.reduce(0, +)
				self.netRR = totalDelta
				self.avgRRChange = Double(totalDelta) / Double(rankedUpdates.count)
				
				let gains = deltas.filter { $0 > 0 }
				let losses = deltas.filter { $0 < 0 }
				if !gains.isEmpty {
					self.avgRRGain = Double(gains.reduce(0, +)) / Double(gains.count)
					self.bestRRGain = gains.max()
				}
				if !losses.isEmpty {
					self.avgRRLoss = Double(losses.reduce(0, +)) / Double(losses.count)
					self.worstRRLoss = losses.min()
				}
			}
		}
		
		private static func maxKillStreak(in match: MatchDetails, userID: User.ID) -> Int {
			var current = 0
			var best = 0
			for round in match.roundResults {
				let killsInRound = round.playerStats.first(where: { $0.subject == userID })?.kills.count ?? 0
				let allEvents = round.playerStats.flatMap(\.kills).sorted { $0.roundTimeMillis < $1.roundTimeMillis }
				var died = false
				var run = current
				for k in allEvents {
					if k.killer == userID {
						run += 1
						best = max(best, run)
					}
					if k.victim == userID {
						run = 0
						died = true
					}
				}
				if allEvents.isEmpty && killsInRound > 0 {
					run += killsInRound
					best = max(best, run)
				}
				current = died ? 0 : run
			}
			return best
		}
	}
	
	struct KDRatio {
		struct CombatTally {
			var kills = 0
			var deaths = 0
			var assists = 0
			var matches = 0
			var wins = 0
			var losses = 0
			var score = 0
			var rounds = 0
			var damage = 0
			var headshots = 0
			var hits = 0
			
			var kd: Double { deaths > 0 ? Double(kills) / Double(deaths) : Double(kills) }
			var kad: Double { deaths > 0 ? Double(kills + assists) / Double(deaths) : Double(kills + assists) }
			var winRate: Double {
				let d = wins + losses
				return d > 0 ? Double(wins) * Double(100) / Double(d) : Double(0)
			}
			var acs: Int { rounds > 0 ? score / rounds : 0 }
			var adr: Int { rounds > 0 ? damage / rounds : 0 }
			var hsPercent: Double { hits > 0 ? Double(headshots) * Double(100) / Double(hits) : Double(0) }
		}
		
		struct WeaponTally {
			var kills = 0
			var damage = 0
			var headshots = 0
			var hits = 0
			
			var hsPercent: Double { hits > 0 ? Double(headshots) * Double(100) / Double(hits) : Double(0) }
		}
		
		struct MatchEntry: Identifiable {
			var id: Match.ID
			var startTime: Date
			var mapID: MapID
			var agentID: Agent.ID?
			var kills: Int
			var deaths: Int
			var assists: Int
			var kd: Double
			var kad: Double
			var acs: Int
			var won: Bool?
		}
		
		var byMatch: [MatchEntry] = []
		var byAgent: [Agent.ID: CombatTally] = [:]
		var byMap: [MapID: CombatTally] = [:]
		var byWeapon: [Weapon.ID: WeaponTally] = [:]
		var byPremade: [User.ID: CombatTally] = [:]
		
		init(
			userID: User.ID,
			matches: [MatchDetails],
			analyticsByMatch: [Match.ID: MatchAnalytics],
			hitDistribution: HitDistribution
		) {
			for match in matches.sorted(by: { $0.matchInfo.gameStart < $1.matchInfo.gameStart }) {
				guard let player = match.players.firstElement(withID: userID),
					  let s = player.stats else { continue }
				let pStats = analyticsByMatch[match.id]?.byPlayer[userID]
				let won = match.teams.first(where: \.won).map { $0.id == player.teamID }
				let kd = s.deaths > 0 ? Double(s.kills) / Double(s.deaths) : Double(s.kills)
				let kad = s.deaths > 0 ? Double(s.kills + s.assists) / Double(s.deaths) : Double(s.kills + s.assists)
				let acs = s.roundsPlayed > 0 ? s.score / s.roundsPlayed : 0
				
				byMatch.append(MatchEntry(
					id: match.id,
					startTime: match.matchInfo.gameStart,
					mapID: match.matchInfo.mapID,
					agentID: player.agentID,
					kills: s.kills,
					deaths: s.deaths,
					assists: s.assists,
					kd: kd,
					kad: kad,
					acs: acs,
					won: won
				))
				
				func add(_ tally: inout CombatTally) {
					tally.kills += s.kills
					tally.deaths += s.deaths
					tally.assists += s.assists
					tally.matches += 1
					if let won {
						if won { tally.wins += 1 } else { tally.losses += 1 }
					}
					tally.score += s.score
					tally.rounds += s.roundsPlayed
					tally.damage += pStats?.totalDamage ?? 0
					tally.headshots += pStats?.headshots ?? 0
					tally.hits += (pStats?.headshots ?? 0) + (pStats?.bodyshots ?? 0) + (pStats?.legshots ?? 0)
				}
				
				if let agentID = player.agentID {
					add(&byAgent[agentID, default: CombatTally()])
				}
				add(&byMap[match.matchInfo.mapID, default: CombatTally()])
				
				for teammate in match.players where teammate.id != userID && teammate.partyID == player.partyID {
					add(&byPremade[teammate.id, default: CombatTally()])
				}
				
				for weaponStat in pStats?.weaponsUsed ?? [] {
					byWeapon[weaponStat.weaponID, default: WeaponTally()].kills += weaponStat.kills
					byWeapon[weaponStat.weaponID, default: WeaponTally()].damage += weaponStat.damage
				}
			}
			
			for (weaponID, tally) in hitDistribution.byWeapon {
				byWeapon[weaponID, default: WeaponTally()].headshots += tally.headshots
				byWeapon[weaponID, default: WeaponTally()].hits += tally.total
			}
		}
	}
	
	struct Economy {
		enum BuyType: String, CaseIterable, Identifiable, Hashable {
			case pistol = "Pistol"
			case eco = "Eco"
			case semiBuy = "Semi-Buy"
			case fullBuy = "Full Buy"
			
			var id: String { rawValue }
		}
		
		struct BuyTypeStats {
			var rounds = 0
			var wins = 0
			var losses = 0
			var totalDamage = 0
			var totalLoadout = 0
			var totalSpent = 0
			
			var winRate: Double { rounds > 0 ? Double(wins) * Double(100) / Double(rounds) : Double(0) }
			var avgDamage: Int { rounds > 0 ? totalDamage / rounds : 0 }
			var avgLoadout: Int { rounds > 0 ? totalLoadout / rounds : 0 }
			var avgSpent: Int { rounds > 0 ? totalSpent / rounds : 0 }
		}
		
		struct QueueSpendStats {
			var rounds = 0
			var totalSpent = 0
			var totalLoadout = 0
			var totalDamage = 0
			
			var avgSpend: Int { rounds > 0 ? totalSpent / rounds : 0 }
			var avgLoadout: Int { rounds > 0 ? totalLoadout / rounds : 0 }
		}
		
		var economyRounds = 0
		var totalSpent = 0
		var totalLoadoutValue = 0
		var totalDamage = 0
		var byBuyType: [BuyType: BuyTypeStats] = [:]
		var byQueue: [QueueID?: QueueSpendStats] = [:]
		
		var avgLoadoutValue: Double {
			economyRounds > 0 ? Double(totalLoadoutValue) / Double(economyRounds) : Double(0)
		}
		var avgSpendPerRound: Double {
			economyRounds > 0 ? Double(totalSpent) / Double(economyRounds) : Double(0)
		}
		var damagePer1000Spent: Double {
			totalSpent > 0 ? Double(totalDamage) * Double(1000) / Double(totalSpent) : Double(0)
		}
		var damagePer1000Loadout: Double {
			totalLoadoutValue > 0 ? Double(totalDamage) * Double(1000) / Double(totalLoadoutValue) : Double(0)
		}
		
		init(userID: User.ID, matches: [MatchDetails]) {
			for match in matches {
				guard match.teams.count == 2,
					  let player = match.players.firstElement(withID: userID) else { continue }
				let halfLength = match.roundStructure?.roundsPerHalf ?? 12
				let queue = match.matchInfo.queueID
				
				for round in match.roundResults where round.outcome != .surrendered {
					guard let ps = round.stats(for: userID) else { continue }
					let loadout = ps.economy.loadoutValue
					let spent = ps.economy.spent
					let dmg = ps.damageDealt.reduce(0) { $0 + $1.damage }
					let won = round.winningTeam == player.teamID
					
					economyRounds += 1
					totalSpent += spent
					totalLoadoutValue += loadout
					totalDamage += dmg
					
					let buyType: BuyType = {
						if round.number == 0 || round.number == halfLength {
							return .pistol
						}
						if loadout < 1800 { return .eco }
						if loadout < 3600 { return .semiBuy }
						return .fullBuy
					}()
					
					var bt = byBuyType[buyType] ?? BuyTypeStats()
					bt.rounds += 1
					if won { bt.wins += 1 } else { bt.losses += 1 }
					bt.totalDamage += dmg
					bt.totalLoadout += loadout
					bt.totalSpent += spent
					byBuyType[buyType] = bt
					
					var qs = byQueue[queue] ?? QueueSpendStats()
					qs.rounds += 1
					qs.totalSpent += spent
					qs.totalLoadout += loadout
					qs.totalDamage += dmg
					byQueue[queue] = qs
				}
			}
		}
	}
}

extension Statistics.HitDistribution.Tally {
	init(_ damage: Raw) {
		self.init(
			headshots: damage.headshots,
			bodyshots: damage.bodyshots,
			legshots: damage.legshots
		)
	}
}

extension RoundResult {
	func stats(for userID: User.ID) -> PlayerStats? {
		playerStats.onlyElement { $0.subject == userID }
	}
}

#if DEBUG
extension PreviewData {
	static let statistics = Statistics(userID: userID, matches: allMatches)
	
	static let allMatches: [MatchDetails] = Array(exampleMatches.values)
	+ [singleMatch, strangeMatch, surrenderedMatch, funkySpikeRush, deathmatch, escalation, doubleDamage]
}
#endif
