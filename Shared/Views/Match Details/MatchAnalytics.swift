import Foundation
import ValorantAPI

struct MatchAnalytics {
	struct PerformanceBreakdownItem: Identifiable {
		var id: String { title }
		var title: String
		var value: String
		var detail: String
	}
	
	struct HalfStats {
		var roundsWon = 0
		var roundsPlayed = 0
		var kills = 0
		var deaths = 0
		var assists = 0
		var plants = 0
		var defuses = 0
		var firstBloods = 0
		var firstDeaths = 0
	}
	
	struct MatchHighlight: Identifiable, Hashable {
		var id: String { label }
		var label: String
		var isNegative: Bool
	}
	
	struct PlayerRoundEntry: Identifiable {
		var id: Int { roundNumber }
		var roundNumber: Int
		var won: Bool
		var isAttack: Bool
		var acs: Int
		var damage: Int
		var kills: Int
		var deaths: Int
		var assists: Int
		var killedAgentIDs: [Agent.ID]
		var weaponID: Weapon.ID?
		var loadoutValue: Int
		var spent: Int
		var remaining: Int
		var outcome: String
		var ceremony: String
		var headshots: Int
		var totalHits: Int
	}
	
	struct PlayerMatchAnalytics {
		var playerID: Player.ID
		var kills: Int
		var deaths: Int
		var assists: Int
		var score: Int
		var roundsPlayed: Int
		var acs: Double
		var adr: Double
		var totalDamage: Int
		var kd: Double
		var hsPercent: Double
		var headshots: Int
		var bodyshots: Int
		var legshots: Int
		var kastPercent: Double
		var firstBloods: Int
		var firstDeaths: Int
		var fkPerRound: Double
		var plants: Int
		var defuses: Int
		var trades: Int
		var clutchesWon: Int
		var clutchesLost: Int
		var clutchWonSizes: [Int: Int]
		var multiKills: [Int: Int]
		var abilityCasts: Int
		var performanceScore: Int
		var fightsScore: Int
		var supportScore: Int
		var breakdownItems: [PerformanceBreakdownItem]
		var attackHalf: HalfStats
		var defenseHalf: HalfStats
		var highlights: [MatchHighlight]
		var roundEntries: [PlayerRoundEntry]
		var avgLoadout: Double
		var avgSpent: Double
		var totalSpent: Int
		var damagePer1kCredits: Double
		var weaponsUsed: [WeaponUsageStat]
	}
	
	struct WeaponUsageStat: Identifiable {
		var id: Weapon.ID { weaponID }
		var weaponID: Weapon.ID
		var kills: Int
		var damage: Int
		var headshots: Int
		var roundsUsed: Int
	}
	
	struct SitePreferenceStat: Identifiable {
		var id: String { site }
		var site: String
		var plants: Int
		var wins: Int
		var losses: Int
		var focusedPlayerPlants: Int
		
		var conversionRate: Double {
			plants > 0 ? Double(wins) / Double(plants) : Double(0)
		}
	}
	
	struct OpponentMatchupRow: Identifiable {
		var id: Player.ID { opponent.id }
		var opponent: Player
		var myKills: Int
		var theirKills: Int
		var damageDealt: Int
		var damageTaken: Int
		var headshotsDealt: Int
		var firstBloodsWon: Int
		var firstBloodsLost: Int
		var events: [DuelKillEvent]
	}
	
	struct LobbyComparison {
		var otherCount: Int
		var avgPerformanceScore: Double
		var avgACS: Double
		var avgADR: Double
		var avgHSPercent: Double
		var avgKASTPercent: Double
		var avgKD: Double
		var avgFKPerRound: Double
		var perfRank: Int
		var acsRank: Int
		var adrRank: Int
		var hsRank: Int
		var kastRank: Int
		var kdRank: Int
		var fkRank: Int
		var totalPlayers: Int
	}
	
	struct DuelPairKey: Hashable {
		var allyID: Player.ID
		var enemyID: Player.ID
	}
	
	struct DuelKillEvent: Identifiable {
		var id = UUID()
		var roundNumber: Int
		var roundTimeMillis: Int
		var killerIsAlly: Bool
		var isFirstBlood: Bool
		var weaponID: Weapon.ID?
	}
	
	struct DuelMatchup: Identifiable {
		var id: DuelPairKey { DuelPairKey(allyID: allyPlayer.id, enemyID: enemyPlayer.id) }
		var allyPlayer: Player
		var enemyPlayer: Player
		var allyKills: Int
		var enemyKills: Int
		var allyFirstBloods: Int
		var enemyFirstBloods: Int
		var allyDamage: Int
		var enemyDamage: Int
		var allyHeadshots: Int
		var enemyHeadshots: Int
		var events: [DuelKillEvent]
		
		var totalDuels: Int { allyKills + enemyKills }
	}
	
	struct DuelMatrixData {
		var allyPlayers: [Player]
		var enemyPlayers: [Player]
		var cells: [DuelPairKey: DuelMatchup]
		var topRivalry: DuelMatchup?
		var biggestMismatch: DuelMatchup?
		var mostTraded: DuelMatchup?
		var totalDuels: Int
		var allyFirstBloods: Int
		var allyDuelWinRate: Double
	}
	
	enum BuyType: String, CaseIterable, Identifiable {
		case pistol = "Pistol Round"
		case save = "Save"
		case halfBuy = "Half Buy"
		case fullBuy = "Full Buy"
		
		var id: String { rawValue }
	}
	
	struct BuyTypeSummary: Identifiable {
		var id: BuyType { type }
		var type: BuyType
		var wins: Int
		var losses: Int
		var avgLoadout: Int
		
		var rounds: Int { wins + losses }
		var winRate: Double {
			rounds > 0 ? Double(wins) / Double(rounds) : Double(0)
		}
	}
	
	struct RoundTeamEconomy: Identifiable {
		var id: Int { roundNumber }
		var roundNumber: Int
		var allyLoadout: Int
		var enemyLoadout: Int
		var allySpent: Int
		var enemySpent: Int
		var allyWon: Bool
		var allyBuyType: BuyType
	}
	
	struct EconomyAnalytics {
		var roundEntries: [RoundTeamEconomy]
		var allyBuyTypes: [BuyTypeSummary]
		var lobbyAvgLoadout: Double
		var lobbyAvgSpent: Double
		var lobbyAvgDmgPer1k: Double
	}
	
	let details: MatchDetails
	let byPlayer: [Player.ID: PlayerMatchAnalytics]
	let matchMVPID: Player.ID?
	let teamMVPByTeam: [Team.ID: Player.ID]
	let serverDisplayName: String?
	let lobbyAvgACS: Double
	let lobbyAvgADR: Double
	let lobbyAvgKills: Double
	
	init(details: MatchDetails) {
		self.details = details
		self.serverDisplayName = Self.parseServerName(from: details.matchInfo.gamePodID)
		
		let activePlayers = details.players.filter { $0.teamID != .neutral }
		let teamByPlayer = Dictionary(uniqueKeysWithValues: details.players.map { ($0.id, $0.teamID) })
		let agentByPlayer = Dictionary(uniqueKeysWithValues: details.players.compactMap { p in
			p.agentID.map { (p.id, $0) }
		})
		
		// Determine which team starts on Attack during half 1 (defaults to .red per Riot API).
		let roundStruct = details.roundStructure
		let half1Attackers: Team.ID = {
			for r in details.roundResults {
				if let planter = r.plant?.actor, let planterTeam = teamByPlayer[planter] {
					let swapped = roundStruct?.areRolesSwapped(inRound: r.number) ?? false
					if swapped {
						return planterTeam == .red ? .blue : .red
					}
					return planterTeam
				}
			}
			return .red
		}()
		
		func isAttackTeam(_ teamID: Team.ID, roundNumber: Int) -> Bool {
			let swapped = roundStruct?.areRolesSwapped(inRound: roundNumber) ?? false
			return swapped ? (teamID != half1Attackers) : (teamID == half1Attackers)
		}
		
		var tempStats: [Player.ID: PlayerMatchAnalytics] = [:]
		var totalLobbyACS: Double = 0
		var totalLobbyADR: Double = 0
		var totalLobbyKills: Double = 0
		var lobbyCount = 0
		
		for player in activePlayers {
			let stats = player.stats
			let roundsPlayed = max(1, stats?.roundsPlayed ?? details.roundResults.count)
			let kills = stats?.kills ?? 0
			let deaths = stats?.deaths ?? 0
			let assists = stats?.assists ?? 0
			let score = stats?.score ?? 0
			let acs = Double(score) / Double(roundsPlayed)
			let kd = deaths > 0 ? Double(kills) / Double(deaths) : Double(kills)
			
			var headshots = 0
			var bodyshots = 0
			var legshots = 0
			var totalDamage = 0
			var firstBloods = 0
			var firstDeaths = 0
			var plants = 0
			var defuses = 0
			var trades = 0
			var kastRounds = 0
			var clutchesWon = 0
			var clutchesLost = 0
			var clutchWonSizes: [Int: Int] = [:]
			var clutchLostSizes: [Int: Int] = [:]
			var multiKills: [Int: Int] = [:]
			var atkHalf = HalfStats()
			var defHalf = HalfStats()
			var roundEntries: [PlayerRoundEntry] = []
			var totalLoadout = 0
			var totalSpent = 0
			var economyRoundCount = 0
			var killsByWeapon: [Weapon.ID: Int] = [:]
			var damageByWeapon: [Weapon.ID: Int] = [:]
			var headshotsByWeapon: [Weapon.ID: Int] = [:]
			var roundsUsedByWeapon: [Weapon.ID: Int] = [:]
			
			for round in details.roundResults {
				let won = round.winningTeam == player.teamID
				let isAtk = isAttackTeam(player.teamID, roundNumber: round.number)
				
				if isAtk {
					atkHalf.roundsPlayed += 1
					if won { atkHalf.roundsWon += 1 }
				} else {
					defHalf.roundsPlayed += 1
					if won { defHalf.roundsWon += 1 }
				}
				
				let allKills = round.playerStats
					.flatMap(\.kills)
					.sorted { $0.roundTimeMillis < $1.roundTimeMillis }
				
				if let firstKill = allKills.first {
					if firstKill.killer == player.id {
						firstBloods += 1
						if isAtk { atkHalf.firstBloods += 1 } else { defHalf.firstBloods += 1 }
					}
					if firstKill.victim == player.id {
						firstDeaths += 1
						if isAtk { atkHalf.firstDeaths += 1 } else { defHalf.firstDeaths += 1 }
					}
				}
				
				let didPlant = round.plant?.actor == player.id
				let didDefuse = round.defusal?.actor == player.id
				if didPlant {
					plants += 1
					atkHalf.plants += 1
				}
				if didDefuse {
					defuses += 1
					defHalf.defuses += 1
				}
				
				// Kills, deaths, assists, killed enemy agents in this round
				var roundKills = 0
				var killedAgents: [Agent.ID] = []
				var roundAssists = 0
				var diedTime: Int?
				var killerOfPlayer: Player.ID?
				var weaponKillsInRound: [Weapon.ID: Int] = [:]
				
				for k in allKills {
					if k.killer == player.id && teamByPlayer[k.victim] != player.teamID {
						roundKills += 1
						if let victimAgent = agentByPlayer[k.victim] {
							killedAgents.append(victimAgent)
						}
						if k.finishingDamage.type == .weapon, let wid = Weapon.ID(k.finishingDamage.source) {
							weaponKillsInRound[wid, default: 0] += 1
							killsByWeapon[wid, default: 0] += 1
						} else if k.finishingDamage.type == .melee {
							weaponKillsInRound[Weapon.ID.melee, default: 0] += 1
							killsByWeapon[Weapon.ID.melee, default: 0] += 1
						}
					}
					if k.assistants.contains(player.id) {
						roundAssists += 1
					}
					if k.victim == player.id && diedTime == nil {
						diedTime = k.roundTimeMillis
						killerOfPlayer = k.killer
					}
				}
				let roundDeaths = diedTime != nil ? 1 : 0
				if roundKills >= 2 {
					let bucket = min(5, roundKills)
					multiKills[bucket, default: 0] += 1
				}
				
				if isAtk {
					atkHalf.kills += roundKills
					atkHalf.deaths += roundDeaths
					atkHalf.assists += roundAssists
				} else {
					defHalf.kills += roundKills
					defHalf.deaths += roundDeaths
					defHalf.assists += roundAssists
				}
				
				// Offensive trades & KAST check
				var lastVictimKillByEnemy: [Player.ID: Int] = [:]
				var wasTraded = false
				for k in allKills {
					guard let killer = k.killer else { continue }
					if let killerTeam = teamByPlayer[killer], killerTeam == player.teamID,
					   let tEnemyKill = lastVictimKillByEnemy[k.victim],
					   k.roundTimeMillis - tEnemyKill <= 5000,
					   killer == player.id {
						trades += 1
					}
					if let vTeam = teamByPlayer[k.victim], vTeam == player.teamID {
						lastVictimKillByEnemy[killer] = k.roundTimeMillis
					}
					if let diedTime, let killerOfPlayer,
					   k.victim == killerOfPlayer,
					   let avengerTeam = teamByPlayer[killer],
					   avengerTeam == player.teamID,
					   k.roundTimeMillis >= diedTime,
					   k.roundTimeMillis - diedTime <= 5000 {
						wasTraded = true
					}
				}
				
				if roundKills > 0 || roundAssists > 0 || diedTime == nil || wasTraded {
					kastRounds += 1
				}
				
				// Clutch detection: walk kills in chronological order to check if player ended up last alive on their team vs enemies.
				let teammates = Set(activePlayers.filter { $0.teamID == player.teamID }.map(\.id))
				let opponents = Set(activePlayers.filter { $0.teamID != player.teamID }.map(\.id))
				if teammates.count > 1 && !opponents.isEmpty {
					var aliveAllies = teammates
					var aliveEnemies = opponents
					var maxClutchOpponents = 0
					for k in allKills {
						aliveAllies.remove(k.victim)
						aliveEnemies.remove(k.victim)
						if aliveAllies.count == 1 && aliveAllies.contains(player.id) && !aliveEnemies.isEmpty {
							maxClutchOpponents = max(maxClutchOpponents, aliveEnemies.count)
						}
					}
					if maxClutchOpponents >= 1 {
						if won {
							clutchesWon += 1
							clutchWonSizes[maxClutchOpponents, default: 0] += 1
						} else if diedTime != nil || round.winningTeam != player.teamID {
							clutchesLost += 1
							clutchLostSizes[maxClutchOpponents, default: 0] += 1
						}
					}
				}
				
				// Damage & hits in this round
				let myRoundStats = round.playerStats.first { $0.subject == player.id }
				var rDmg = 0
				var rHS = 0
				var rHits = 0
				if let myRoundStats {
					for d in myRoundStats.damageDealt {
						rDmg += d.damage
						rHS += d.headshots
						rHits += d.headshots + d.bodyshots + d.legshots
						headshots += d.headshots
						bodyshots += d.bodyshots
						legshots += d.legshots
					}
				}
				totalDamage += rDmg
				
				let rScore = myRoundStats?.combatScore
					?? round.playerScores?.first(where: { $0.subject == player.id })?.score
					?? 0
				let econ = myRoundStats?.economy
					?? round.playerEconomies?.first(where: { $0.subject == player.id })
				let loadoutVal = econ?.loadoutValue ?? 0
				let spentVal = econ?.spent ?? 0
				let remainingVal = econ?.remaining ?? 0
				if econ != nil {
					totalLoadout += loadoutVal
					totalSpent += spentVal
					economyRoundCount += 1
				}
				
				let totalWK = weaponKillsInRound.values.reduce(0, +)
				if totalWK > 0 {
					var allocatedDmg = 0
					var allocatedHS = 0
					let sortedWK = weaponKillsInRound.sorted { $0.value > $1.value }
					for (idx, item) in sortedWK.enumerated() {
						roundsUsedByWeapon[item.key, default: 0] += 1
						if idx == sortedWK.count - 1 {
							damageByWeapon[item.key, default: 0] += max(0, rDmg - allocatedDmg)
							headshotsByWeapon[item.key, default: 0] += max(0, rHS - allocatedHS)
						} else {
							let shareD = Int((Double(rDmg) * Double(item.value) / Double(totalWK)).rounded())
							let shareH = Int((Double(rHS) * Double(item.value) / Double(totalWK)).rounded())
							allocatedDmg += shareD
							allocatedHS += shareH
							damageByWeapon[item.key, default: 0] += shareD
							headshotsByWeapon[item.key, default: 0] += shareH
						}
					}
				} else if let heldWeapon = econ?.weapon {
					roundsUsedByWeapon[heldWeapon, default: 0] += 1
					if rDmg > 0 {
						damageByWeapon[heldWeapon, default: 0] += rDmg
						headshotsByWeapon[heldWeapon, default: 0] += rHS
					}
				}
				
				roundEntries.append(PlayerRoundEntry(
					roundNumber: round.number,
					won: won,
					isAttack: isAtk,
					acs: rScore,
					damage: rDmg,
					kills: roundKills,
					deaths: roundDeaths,
					assists: roundAssists,
					killedAgentIDs: killedAgents,
					weaponID: econ?.weapon,
					loadoutValue: loadoutVal,
					spent: spentVal,
					remaining: remainingVal,
					outcome: round.outcome.rawValue,
					ceremony: round.ceremony,
					headshots: rHS,
					totalHits: rHits
				))
			}
			
			// Deathmatch / non-round modes have empty roundResults: fall back to roundDamage
			if details.roundResults.isEmpty, let dmgArr = player.damageDealtByRound {
				totalDamage = dmgArr.reduce(0) { $0 + $1.damage }
			}
			
			let adr = Double(totalDamage) / Double(roundsPlayed)
			let totalHits = headshots + bodyshots + legshots
			let hsPercent = totalHits > 0 ? (Double(headshots) * Double(100) / Double(totalHits)) : Double(0)
			let evaluatedRounds = max(1, details.roundResults.count)
			let kastPercent = details.roundResults.isEmpty
				? Double(0)
				: (Double(kastRounds) * Double(100) / Double(evaluatedRounds))
			let fkPerRound = Double(firstBloods) / Double(roundsPlayed)
			
			let abilityCasts = stats?.abilityCasts.map { $0.first + $0.second + $0.signature + $0.ultimate } ?? 0
			
			// Calibrated 0...500 Fights & Support scores (250 = lobby average, 330+ = strong, 420+ = Masterful)
			let rp = Double(roundsPlayed)
			let multiKillBonus = Double(multiKills[2, default: 0] * 10 + multiKills[3, default: 0] * 22 + multiKills[4, default: 0] * 38 + multiKills[5, default: 0] * 55) / rp
			let clutchBonus = Double(clutchesWon) / rp * Double(140)
			let fightsRaw = Double(70)
				+ (acs / Double(210)) * Double(110)
				+ min(Double(3.0), kd) * Double(52)
				+ (adr / Double(135)) * Double(60)
				+ fkPerRound * Double(140)
				+ multiKillBonus * Double(1.4)
				+ clutchBonus
			let fightsScore = min(500, max(0, Int(fightsRaw.rounded())))
			
			let assistsPerRound = Double(assists) / rp
			let tradesPerRound = Double(trades) / rp
			let objPerRound = Double(plants + defuses) / rp
			let fdRate = Double(firstDeaths) / rp
			let supportRaw = Double(45)
				+ (kastPercent / Double(100)) * Double(175)
				+ assistsPerRound * Double(180)
				+ tradesPerRound * Double(220)
				+ objPerRound * Double(160)
				- fdRate * Double(110)
			let supportScore = min(500, max(0, Int(supportRaw.rounded())))
			
			let perfRaw = Double(fightsScore) * Double(0.70) + Double(supportScore) * Double(0.30)
			let performanceScore = min(500, max(0, Int(perfRaw.rounded())))
			
			let breakdownItems: [PerformanceBreakdownItem] = [
				PerformanceBreakdownItem(title: "Combat Score (ACS)", value: "\(Int(acs.rounded()))", detail: "Primary fight impact"),
				PerformanceBreakdownItem(title: "Kill / Death Ratio", value: String(format: "%.2f", kd), detail: "\(kills) / \(deaths)"),
				PerformanceBreakdownItem(title: "Damage / Round", value: "\(Int(adr.rounded()))", detail: "ADR across \(roundsPlayed) rounds"),
				PerformanceBreakdownItem(title: "KAST %", value: String(format: "%.0f%%", kastPercent), detail: "Kills, Assists, Survived, Traded"),
				PerformanceBreakdownItem(title: "First Bloods / Deaths", value: "\(firstBloods) / \(firstDeaths)", detail: String(format: "%.2f FK/round", fkPerRound)),
				PerformanceBreakdownItem(title: "Clutches & Multi-Kills", value: "\(clutchesWon) / \(multiKills.values.reduce(0, +))", detail: "\(trades) trades"),
			]
			
			var highlights: [MatchHighlight] = []
			if let k2 = multiKills[2], k2 > 0 { highlights.append(.init(label: k2 > 1 ? "2K ×\(k2)" : "2K", isNegative: false)) }
			if let k3 = multiKills[3], k3 > 0 { highlights.append(.init(label: k3 > 1 ? "3K ×\(k3)" : "3K", isNegative: false)) }
			if let k4 = multiKills[4], k4 > 0 { highlights.append(.init(label: k4 > 1 ? "4K ×\(k4)" : "4K", isNegative: false)) }
			if let k5 = multiKills[5], k5 > 0 { highlights.append(.init(label: k5 > 1 ? "ACE ×\(k5)" : "ACE", isNegative: false)) }
			for enemiesCount in clutchWonSizes.keys.sorted() {
				let c = clutchWonSizes[enemiesCount, default: 0]
				let base = "1V\(enemiesCount) CLUTCH"
				highlights.append(.init(label: c > 1 ? "\(base) ×\(c)" : base, isNegative: false))
			}
			if kastPercent >= 80 && !details.roundResults.isEmpty {
				highlights.append(.init(label: "HIGH KAST", isNegative: false))
			}
			if hsPercent >= 30 && totalHits >= 10 {
				highlights.append(.init(label: "HIGH HS%", isNegative: false))
			}
			if firstBloods >= 3 {
				highlights.append(.init(label: "FIRST BLOODS ×\(firstBloods)", isNegative: false))
			}
			for enemiesCount in clutchLostSizes.keys.sorted() {
				guard enemiesCount >= 2 else { continue }
				let c = clutchLostSizes[enemiesCount, default: 0]
				let base = "1V\(enemiesCount) LOST"
				highlights.append(.init(label: c > 1 ? "\(base) ×\(c)" : base, isNegative: true))
			}
			
			let avgLoadout = economyRoundCount > 0 ? Double(totalLoadout) / Double(economyRoundCount) : Double(0)
			let avgSpent = economyRoundCount > 0 ? Double(totalSpent) / Double(economyRoundCount) : Double(0)
			let dmgPer1k = totalSpent > 0 ? (Double(totalDamage) * Double(1000) / Double(totalSpent)) : Double(0)
			
			let allWeapons = Set(killsByWeapon.keys).union(damageByWeapon.keys)
			let weaponsUsed: [WeaponUsageStat] = allWeapons.compactMap { wid in
				let kCount = killsByWeapon[wid, default: 0]
				let dCount = damageByWeapon[wid, default: 0]
				guard kCount > 0 || dCount > 0 else { return nil }
				return WeaponUsageStat(
					weaponID: wid,
					kills: kCount,
					damage: dCount,
					headshots: headshotsByWeapon[wid, default: 0],
					roundsUsed: roundsUsedByWeapon[wid, default: 0]
				)
			}
			.sorted { lhs, rhs in
				if lhs.kills != rhs.kills { return lhs.kills > rhs.kills }
				if lhs.damage != rhs.damage { return lhs.damage > rhs.damage }
				return lhs.roundsUsed > rhs.roundsUsed
			}
			
			tempStats[player.id] = PlayerMatchAnalytics(
				playerID: player.id,
				kills: kills,
				deaths: deaths,
				assists: assists,
				score: score,
				roundsPlayed: roundsPlayed,
				acs: acs,
				adr: adr,
				totalDamage: totalDamage,
				kd: kd,
				hsPercent: hsPercent,
				headshots: headshots,
				bodyshots: bodyshots,
				legshots: legshots,
				kastPercent: kastPercent,
				firstBloods: firstBloods,
				firstDeaths: firstDeaths,
				fkPerRound: fkPerRound,
				plants: plants,
				defuses: defuses,
				trades: trades,
				clutchesWon: clutchesWon,
				clutchesLost: clutchesLost,
				clutchWonSizes: clutchWonSizes,
				multiKills: multiKills,
				abilityCasts: abilityCasts,
				performanceScore: performanceScore,
				fightsScore: fightsScore,
				supportScore: supportScore,
				breakdownItems: breakdownItems,
				attackHalf: atkHalf,
				defenseHalf: defHalf,
				highlights: highlights,
				roundEntries: roundEntries,
				avgLoadout: avgLoadout,
				avgSpent: avgSpent,
				totalSpent: totalSpent,
				damagePer1kCredits: dmgPer1k,
				weaponsUsed: weaponsUsed
			)
			
			totalLobbyACS += acs
			totalLobbyADR += adr
			totalLobbyKills += Double(kills) / Double(roundsPlayed)
			lobbyCount += 1
		}
		
		self.byPlayer = tempStats
		self.lobbyAvgACS = lobbyCount > 0 ? totalLobbyACS / Double(lobbyCount) : Double(0)
		self.lobbyAvgADR = lobbyCount > 0 ? totalLobbyADR / Double(lobbyCount) : Double(0)
		self.lobbyAvgKills = lobbyCount > 0 ? totalLobbyKills / Double(lobbyCount) : Double(0)
		
		self.matchMVPID = activePlayers.max { lhs, rhs in
			let lACS = tempStats[lhs.id]?.acs ?? 0
			let rACS = tempStats[rhs.id]?.acs ?? 0
			if abs(lACS - rACS) > 0.01 { return lACS < rACS }
			return lhs.score < rhs.score
		}?.id
		
		var teamMVPs: [Team.ID: Player.ID] = [:]
		for (teamID, teamPlayers) in Dictionary(grouping: activePlayers, by: \.teamID) {
			if let best = teamPlayers.max(by: { (tempStats[$0.id]?.acs ?? 0) < (tempStats[$1.id]?.acs ?? 0) }) {
				teamMVPs[teamID] = best.id
			}
		}
		self.teamMVPByTeam = teamMVPs
	}
	
	func lobbyComparison(for playerID: Player.ID) -> LobbyComparison? {
		guard let mine = byPlayer[playerID] else { return nil }
		let all = Array(byPlayer.values)
		let others = all.filter { $0.playerID != playerID }
		guard !others.isEmpty else { return nil }
		
		let n = Double(others.count)
		func rank(_ value: (PlayerMatchAnalytics) -> Double) -> Int {
			1 + others.filter { value($0) > value(mine) + Double(0.0001) }.count
		}
		
		return LobbyComparison(
			otherCount: others.count,
			avgPerformanceScore: Double(others.reduce(0) { $0 + $1.performanceScore }) / n,
			avgACS: others.reduce(Double(0)) { $0 + $1.acs } / n,
			avgADR: others.reduce(Double(0)) { $0 + $1.adr } / n,
			avgHSPercent: others.reduce(Double(0)) { $0 + $1.hsPercent } / n,
			avgKASTPercent: others.reduce(Double(0)) { $0 + $1.kastPercent } / n,
			avgKD: others.reduce(Double(0)) { $0 + $1.kd } / n,
			avgFKPerRound: others.reduce(Double(0)) { $0 + $1.fkPerRound } / n,
			perfRank: rank { Double($0.performanceScore) },
			acsRank: rank(\.acs),
			adrRank: rank(\.adr),
			hsRank: rank(\.hsPercent),
			kastRank: rank(\.kastPercent),
			kdRank: rank(\.kd),
			fkRank: rank(\.fkPerRound),
			totalPlayers: all.count
		)
	}
	
	func duelMatrix(for allyTeamID: Team.ID) -> DuelMatrixData? {
		guard details.teams.count == 2 else { return nil }
		let enemyTeamID = details.teams.first(where: { $0.id != allyTeamID })?.id ?? (allyTeamID == .blue ? .red : .blue)
		
		func sortedTeam(_ teamID: Team.ID) -> [Player] {
			details.players
				.filter { $0.teamID == teamID }
				.sorted {
					let l = byPlayer[$0.id]?.acs ?? Double($0.score)
					let r = byPlayer[$1.id]?.acs ?? Double($1.score)
					return l > r
				}
		}
		
		let allies = sortedTeam(allyTeamID)
		let enemies = sortedTeam(enemyTeamID)
		guard !allies.isEmpty && !enemies.isEmpty else { return nil }
		
		let allySet = Set(allies.map(\.id))
		let enemySet = Set(enemies.map(\.id))
		let allyMap = Dictionary(uniqueKeysWithValues: allies.map { ($0.id, $0) })
		let enemyMap = Dictionary(uniqueKeysWithValues: enemies.map { ($0.id, $0) })
		
		var matchups: [DuelPairKey: DuelMatchup] = [:]
		for a in allies {
			for e in enemies {
				let key = DuelPairKey(allyID: a.id, enemyID: e.id)
				matchups[key] = DuelMatchup(
					allyPlayer: a,
					enemyPlayer: e,
					allyKills: 0,
					enemyKills: 0,
					allyFirstBloods: 0,
					enemyFirstBloods: 0,
					allyDamage: 0,
					enemyDamage: 0,
					allyHeadshots: 0,
					enemyHeadshots: 0,
					events: []
				)
			}
		}
		
		for round in details.roundResults {
			let killsInRound = round.playerStats
				.flatMap(\.kills)
				.sorted { $0.roundTimeMillis < $1.roundTimeMillis }
			let firstKill = killsInRound.first
			
			for kill in killsInRound {
				guard let killer = kill.killer else { continue }
				let isFirst = (kill.roundTimeMillis == firstKill?.roundTimeMillis && kill.killer == firstKill?.killer && kill.victim == firstKill?.victim)
				let weaponID = kill.finishingDamage.type == .weapon ? Weapon.ID(kill.finishingDamage.source) : nil
				
				if allySet.contains(killer), enemySet.contains(kill.victim),
				   allyMap[killer] != nil, enemyMap[kill.victim] != nil {
					let key = DuelPairKey(allyID: killer, enemyID: kill.victim)
					matchups[key]?.allyKills += 1
					if isFirst { matchups[key]?.allyFirstBloods += 1 }
					matchups[key]?.events.append(DuelKillEvent(
						roundNumber: round.number,
						roundTimeMillis: kill.roundTimeMillis,
						killerIsAlly: true,
						isFirstBlood: isFirst,
						weaponID: weaponID
					))
				} else if enemySet.contains(killer), allySet.contains(kill.victim),
						  allyMap[kill.victim] != nil, enemyMap[killer] != nil {
					let key = DuelPairKey(allyID: kill.victim, enemyID: killer)
					matchups[key]?.enemyKills += 1
					if isFirst { matchups[key]?.enemyFirstBloods += 1 }
					matchups[key]?.events.append(DuelKillEvent(
						roundNumber: round.number,
						roundTimeMillis: kill.roundTimeMillis,
						killerIsAlly: false,
						isFirstBlood: isFirst,
						weaponID: weaponID
					))
				}
			}
			
			for ps in round.playerStats {
				if allySet.contains(ps.subject) {
					for dmg in ps.damageDealt where enemySet.contains(dmg.receiver) {
						let key = DuelPairKey(allyID: ps.subject, enemyID: dmg.receiver)
						matchups[key]?.allyDamage += dmg.damage
						matchups[key]?.allyHeadshots += dmg.headshots
					}
				} else if enemySet.contains(ps.subject) {
					for dmg in ps.damageDealt where allySet.contains(dmg.receiver) {
						let key = DuelPairKey(allyID: dmg.receiver, enemyID: ps.subject)
						matchups[key]?.enemyDamage += dmg.damage
						matchups[key]?.enemyHeadshots += dmg.headshots
					}
				}
			}
		}
		
		let nonZero = matchups.values.filter { $0.totalDuels > 0 }
		let topRivalry = nonZero.max { lhs, rhs in
			if lhs.totalDuels != rhs.totalDuels { return lhs.totalDuels < rhs.totalDuels }
			return (lhs.allyDamage + lhs.enemyDamage) < (rhs.allyDamage + rhs.enemyDamage)
		}
		let biggestMismatch = nonZero
			.filter { $0.totalDuels >= 2 }
			.max { abs($0.allyKills - $0.enemyKills) < abs($1.allyKills - $1.enemyKills) }
		let mostTraded = nonZero
			.filter { $0.allyKills > 0 && $0.enemyKills > 0 }
			.max { lhs, rhs in
				let lMin = min(lhs.allyKills, lhs.enemyKills)
				let rMin = min(rhs.allyKills, rhs.enemyKills)
				if lMin != rMin { return lMin < rMin }
				return lhs.totalDuels < rhs.totalDuels
			}
		
		let totalAllyKills = nonZero.reduce(0) { $0 + $1.allyKills }
		let totalEnemyKills = nonZero.reduce(0) { $0 + $1.enemyKills }
		let totalDuels = totalAllyKills + totalEnemyKills
		let allyFBs = nonZero.reduce(0) { $0 + $1.allyFirstBloods }
		let winRate = totalDuels > 0 ? Double(totalAllyKills) / Double(totalDuels) : Double(0)
		
		return DuelMatrixData(
			allyPlayers: allies,
			enemyPlayers: enemies,
			cells: matchups,
			topRivalry: topRivalry,
			biggestMismatch: biggestMismatch,
			mostTraded: mostTraded,
			totalDuels: totalDuels,
			allyFirstBloods: allyFBs,
			allyDuelWinRate: winRate
		)
	}
	
	func economyAnalytics(for allyTeamID: Team.ID) -> EconomyAnalytics? {
		guard details.teams.count == 2, !details.roundResults.isEmpty else { return nil }
		let allySet = Set(details.players.filter { $0.teamID == allyTeamID }.map(\.id))
		let halfLength = details.roundStructure?.roundsPerHalf ?? 12
		
		var rounds: [RoundTeamEconomy] = []
		var countsByType: [BuyType: (wins: Int, losses: Int, loadoutSum: Int)] = [:]
		
		for round in details.roundResults {
			var allyLoadout = 0
			var enemyLoadout = 0
			var allySpent = 0
			var enemySpent = 0
			var allyCount = 0
			
			if let economies = round.playerEconomies, !economies.isEmpty {
				for e in economies {
					guard let subj = e.subject else { continue }
					if allySet.contains(subj) {
						allyLoadout += e.loadoutValue
						allySpent += e.spent
						allyCount += 1
					} else {
						enemyLoadout += e.loadoutValue
						enemySpent += e.spent
					}
				}
			} else {
				for ps in round.playerStats {
					if allySet.contains(ps.subject) {
						allyLoadout += ps.economy.loadoutValue
						allySpent += ps.economy.spent
						allyCount += 1
					} else {
						enemyLoadout += ps.economy.loadoutValue
						enemySpent += ps.economy.spent
					}
				}
			}
			
			let avgAlly = allyCount > 0 ? allyLoadout / allyCount : 0
			let isPistol = round.number == 0 || round.number == halfLength
			let buyType: BuyType = {
				if isPistol { return .pistol }
				if avgAlly < 1800 { return .save }
				if avgAlly < 3600 { return .halfBuy }
				return .fullBuy
			}()
			let won = round.winningTeam == allyTeamID
			var bucket = countsByType[buyType] ?? (0, 0, 0)
			if won { bucket.wins += 1 } else { bucket.losses += 1 }
			bucket.loadoutSum += avgAlly
			countsByType[buyType] = bucket
			
			rounds.append(RoundTeamEconomy(
				roundNumber: round.number,
				allyLoadout: allyLoadout,
				enemyLoadout: enemyLoadout,
				allySpent: allySpent,
				enemySpent: enemySpent,
				allyWon: won,
				allyBuyType: buyType
			))
		}
		
		let buyTypes: [BuyTypeSummary] = BuyType.allCases.compactMap { type in
			guard let b = countsByType[type], b.wins + b.losses > 0 else { return nil }
			return BuyTypeSummary(
				type: type,
				wins: b.wins,
				losses: b.losses,
				avgLoadout: b.loadoutSum / (b.wins + b.losses)
			)
		}
		
		let all = Array(byPlayer.values)
		let n = max(1, all.count)
		let avgLoadout = all.reduce(Double(0)) { $0 + $1.avgLoadout } / Double(n)
		let avgSpent = all.reduce(Double(0)) { $0 + $1.avgSpent } / Double(n)
		let avgDmgPer1k = all.reduce(Double(0)) { $0 + $1.damagePer1kCredits } / Double(n)
		
		return EconomyAnalytics(
			roundEntries: rounds,
			allyBuyTypes: buyTypes,
			lobbyAvgLoadout: avgLoadout,
			lobbyAvgSpent: avgSpent,
			lobbyAvgDmgPer1k: avgDmgPer1k
		)
	}
	
	func opponentMatchups(for playerID: Player.ID) -> [OpponentMatchupRow] {
		guard let player = details.players.first(where: { $0.id == playerID }),
			  let matrix = duelMatrix(for: player.teamID) else {
			return []
		}
		return matrix.enemyPlayers.compactMap { enemy in
			let key = DuelPairKey(allyID: playerID, enemyID: enemy.id)
			guard let m = matrix.cells[key] else { return nil }
			return OpponentMatchupRow(
				opponent: enemy,
				myKills: m.allyKills,
				theirKills: m.enemyKills,
				damageDealt: m.allyDamage,
				damageTaken: m.enemyDamage,
				headshotsDealt: m.allyHeadshots,
				firstBloodsWon: m.allyFirstBloods,
				firstBloodsLost: m.enemyFirstBloods,
				events: m.events
			)
		}
		.sorted { lhs, rhs in
			let lTotal = lhs.myKills + lhs.theirKills
			let rTotal = rhs.myKills + rhs.theirKills
			if lTotal != rTotal { return lTotal > rTotal }
			return lhs.myKills > rhs.myKills
		}
	}
	
	func sitePreferences(for teamID: Team.ID, focusedPlayerID: Player.ID) -> [SitePreferenceStat] {
		let teamByPlayer = Dictionary(uniqueKeysWithValues: details.players.map { ($0.id, $0.teamID) })
		var buckets: [String: (plants: Int, wins: Int, losses: Int, selfPlants: Int)] = [:]
		
		for round in details.roundResults {
			guard let site = round.plantSite, !site.isEmpty,
				  let planter = round.plant?.actor,
				  teamByPlayer[planter] == teamID else {
				continue
			}
			let key = site.uppercased()
			var b = buckets[key] ?? (0, 0, 0, 0)
			b.plants += 1
			if round.winningTeam == teamID {
				b.wins += 1
			} else {
				b.losses += 1
			}
			if planter == focusedPlayerID {
				b.selfPlants += 1
			}
			buckets[key] = b
		}
		
		return buckets.keys.sorted().map { site in
			let b = buckets[site]!
			return SitePreferenceStat(
				site: site,
				plants: b.plants,
				wins: b.wins,
				losses: b.losses,
				focusedPlayerPlants: b.selfPlants
			)
		}
	}
	
	static func parseServerName(from gamePodID: String?) -> String? {
		guard let gamePodID = gamePodID?.lowercased(), !gamePodID.isEmpty else { return nil }
		let mapping: [(String, String)] = [
			("paris", "Paris"),
			("frankfurt", "Frankfurt"),
			("london", "London"),
			("madrid", "Madrid"),
			("stockholm", "Stockholm"),
			("warsaw", "Warsaw"),
			("tokyo", "Tokyo"),
			("singapore", "Singapore"),
			("sydney", "Sydney"),
			("virginia", "N. Virginia"),
			("oregon", "Oregon"),
			("texas", "Texas"),
			("illinois", "Illinois"),
			("georgia", "Georgia"),
			("california", "N. California"),
			("saopaulo", "São Paulo"),
			("santiago", "Santiago"),
			("mexico", "Mexico City"),
			("bogota", "Bogota"),
			("miami", "Miami"),
			("seoul", "Seoul"),
			("hongkong", "Hong Kong"),
			("mumbai", "Mumbai"),
			("bahrain", "Bahrain"),
			("istanbul", "Istanbul"),
			("dubai", "Dubai"),
			("capetown", "Cape Town"),
		]
		for (token, name) in mapping where gamePodID.contains(token) {
			return name
		}
		return nil
	}
}

extension Player {
	@MainActor
	func resolvedDisplayName(using resolvedUsers: [Player.ID: User]) -> String {
		if !gameName.isEmpty { return gameName }
		if let u = resolvedUsers[id], !u.gameName.isEmpty { return u.gameName }
		if let cached = LocalDataProvider.shared.userManager.loadedObject(for: id), !cached.gameName.isEmpty {
			return cached.gameName
		}
		return "Player"
	}
	
	@MainActor
	func resolvedTagLine(using resolvedUsers: [Player.ID: User]) -> String {
		if !tagLine.isEmpty { return tagLine }
		if let u = resolvedUsers[id], !u.tagLine.isEmpty { return u.tagLine }
		if let cached = LocalDataProvider.shared.userManager.loadedObject(for: id), !cached.tagLine.isEmpty {
			return cached.tagLine
		}
		return ""
	}
}
