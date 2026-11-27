import Foundation
import SwiftUI
import ValorantAPI

enum GroupPerformanceQueueScope: String, CaseIterable, Identifiable, Hashable, Sendable {
	case allTeamModes
	case competitive
	case unrated
	case swiftplay
	case premier
	case spikeRush
	case teamDeathmatch
	case custom
	case allQueues
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .allTeamModes: return "All Team Modes"
		case .competitive: return "Competitive"
		case .unrated: return "Unrated"
		case .swiftplay: return "Swiftplay"
		case .premier: return "Premier"
		case .spikeRush: return "Spike Rush"
		case .teamDeathmatch: return "Team Deathmatch"
		case .custom: return "Custom"
		case .allQueues: return "All Modes"
		}
	}
	
	func accepts(queueID: QueueID?, modeID: GameMode.ID) -> Bool {
		switch self {
		case .allTeamModes:
			return queueID != .custom
				&& queueID != .deathmatch
				&& modeID != .deathmatch
				&& modeID != .practice
				&& modeID != .onboarding
		case .competitive:
			return queueID == .competitive || queueID == .premier
		case .unrated:
			return queueID == .unrated
		case .swiftplay:
			return queueID == .swiftplay
		case .premier:
			return queueID == .premier
		case .spikeRush:
			return queueID == .spikeRush
		case .teamDeathmatch:
			return queueID == .teamDeathmatch || modeID == .teamDeathmatch
		case .custom:
			return queueID == .custom
		case .allQueues:
			return modeID != .practice && modeID != .onboarding
		}
	}
	
	func acceptsUpdate(_ match: CompetitiveUpdate) -> Bool {
		switch self {
		case .competitive:
			return match.isRanked
		default:
			return true
		}
	}
}

enum GroupPerformanceSort: String, CaseIterable, Identifiable, Hashable, Sendable {
	case matches
	case winRate
	case kd
	case acs
	case recent
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .matches: return "Most Played"
		case .winRate: return "Win Rate"
		case .kd: return "Best K/D"
		case .acs: return "Highest ACS"
		case .recent: return "Most Recent"
		}
	}
	
	var icon: String {
		switch self {
		case .matches: return "flame.fill"
		case .winRate: return "percent"
		case .kd: return "scope"
		case .acs: return "bolt.fill"
		case .recent: return "clock.fill"
		}
	}
}

enum GroupViewMode: String, CaseIterable, Identifiable, Hashable, Sendable {
	case players
	case groups
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .players: return "Players"
		case .groups: return "Groups"
		}
	}
}

enum StackSizeFilter: Int, CaseIterable, Identifiable, Hashable, Sendable {
	case all = 0
	case duo = 2
	case trio = 3
	case fourStack = 4
	case fiveStack = 5
	
	var id: Int { rawValue }
	
	var label: String {
		switch self {
		case .all: return "All"
		case .duo: return "Duo"
		case .trio: return "Trio"
		case .fourStack: return "4-Stack"
		case .fiveStack: return "5-Stack"
		}
	}
	
	func matches(stackSize: Int) -> Bool {
		switch self {
		case .all: return true
		case .fiveStack: return stackSize >= 5
		default: return stackSize == rawValue
		}
	}
}

struct ResolvedPlayerName: Equatable, Hashable {
	var gameName: String
	var tagLine: String
}

struct GroupFriendHint: Equatable, Hashable {
	var userID: User.ID
	var gameName: String
	var tagLine: String
	var cardID: PlayerCard.ID?
	var competitiveTier: Int?
	var note: String?
}

struct GroupCombatStats: Equatable, Hashable {
	var matches: Int = 0
	var wins: Int = 0
	var losses: Int = 0
	var draws: Int = 0
	var kills: Int = 0
	var deaths: Int = 0
	var assists: Int = 0
	var totalScore: Int = 0
	var totalRounds: Int = 0
	var totalDamage: Int = 0
	var headshots: Int = 0
	var totalHits: Int = 0
	var roundsWon: Int = 0
	var roundsLost: Int = 0
	var netRR: Int = 0
	var rankedMatches: Int = 0
	var totalPlaytime: TimeInterval = 0
	
	var decidedMatches: Int { wins + losses }
	
	var winRate: Double {
		decidedMatches > 0 ? Double(wins) / Double(decidedMatches) : Double(0)
	}
	
	var kd: Double {
		deaths > 0 ? Double(kills) / Double(deaths) : Double(kills)
	}
	
	var avgACS: Double {
		totalRounds > 0 ? Double(totalScore) / Double(totalRounds) : Double(0)
	}
	
	var avgADR: Double {
		totalRounds > 0 ? Double(totalDamage) / Double(totalRounds) : Double(0)
	}
	
	var hsPercent: Double {
		totalHits > 0 ? (Double(headshots) / Double(totalHits)) * Double(100) : Double(0)
	}
	
	var recordText: String {
		draws > 0 ? "\(wins)W–\(losses)L–\(draws)D" : "\(wins)W–\(losses)L"
	}
}

struct GroupMapStat: Identifiable, Equatable, Hashable {
	var id: MapID
	var matches: Int
	var wins: Int
	var losses: Int
	var draws: Int
	var winRate: Double
	var kd: Double
	var avgACS: Double
}

struct GroupAgentStat: Identifiable, Equatable, Hashable {
	var id: Agent.ID
	var matches: Int
	var wins: Int
	var winRate: Double
	var kd: Double
}

struct GroupSharedMatchEntry: Identifiable, Equatable, Hashable {
	var id: Match.ID
	var gameStart: Date
	var mapID: MapID
	var queueID: QueueID?
	var won: Bool
	var tied: Bool
	var roundsWon: Int
	var roundsLost: Int
	var userAgentID: Agent.ID?
	var userKills: Int
	var userDeaths: Int
	var userAssists: Int
	var userACS: Int
	var partnerAgentID: Agent.ID?
	var partnerKills: Int?
	var partnerDeaths: Int?
	var partnerAssists: Int?
	var partnerACS: Int?
	var rrDelta: Int?
	var partySize: Int
	var wasSameTeam: Bool
	var wasSameParty: Bool
	
	var scoreText: String { "\(roundsWon)–\(roundsLost)" }
	var kdaText: String { "\(userKills)/\(userDeaths)/\(userAssists)" }
}

struct PlayerSynergyReport: Identifiable, Equatable, Hashable {
	var id: User.ID
	var gameName: String
	var tagLine: String
	var cardID: PlayerCard.ID?
	var competitiveTier: Int?
	var friendNote: String?
	var isRiotFriend: Bool
	var isPremade: Bool
	var totalMatches: Int
	var teammateMatches: Int
	var partyMatches: Int
	var opponentMatches: Int
	var stats: GroupCombatStats
	var allEncountersStats: GroupCombatStats
	var teammateStats: GroupCombatStats
	var opponentStats: GroupCombatStats
	var partnerStats: GroupCombatStats
	var winRateDeltaVsOverall: Double
	var mapStats: [GroupMapStat]
	var topUserAgents: [GroupAgentStat]
	var topPartnerAgents: [GroupAgentStat]
	var recentMatches: [GroupSharedMatchEntry]
	var lastPlayed: Date
	
	var hasResolvedName: Bool {
		!gameName.isEmpty
	}
	
	var displayName: String {
		guard !gameName.isEmpty else { return "Unknown Player" }
		return tagLine.isEmpty ? gameName : "\(gameName) #\(tagLine)"
	}
}

struct SquadMemberStat: Identifiable, Equatable, Hashable {
	var id: User.ID
	var gameName: String
	var tagLine: String
	var cardID: PlayerCard.ID?
	var competitiveTier: Int?
	var isRiotFriend: Bool
	var matches: Int
	var kills: Int
	var deaths: Int
	var assists: Int
	var kd: Double
	var avgACS: Double
	var hsPercent: Double
	var topAgentID: Agent.ID?
	
	var hasResolvedName: Bool {
		!gameName.isEmpty
	}
	
	var displayName: String {
		guard !gameName.isEmpty else { return "Unknown Player" }
		return tagLine.isEmpty ? gameName : "\(gameName) #\(tagLine)"
	}
}

struct SquadPerformanceReport: Identifiable, Equatable, Hashable {
	var id: String
	var memberIDs: [User.ID]
	var members: [SquadMemberStat]
	var stackSize: Int
	var isCustomSuperset: Bool
	var stats: GroupCombatStats
	var winRateDeltaVsOverall: Double
	var mapStats: [GroupMapStat]
	var recentMatches: [GroupSharedMatchEntry]
	var lastPlayed: Date
	
	var stackLabel: String {
		GroupPerformanceCalculator.stackLabel(for: stackSize)
	}
	
	var namesSummary: String {
		members.map { $0.gameName.isEmpty ? "Unknown" : $0.gameName }.joined(separator: ", ")
	}
}

struct StackSizeSummary: Identifiable, Equatable, Hashable {
	var id: Int { stackSize }
	var stackSize: Int
	var label: String
	var stats: GroupCombatStats
}

struct GroupPerformanceReport: Equatable {
	var analyzedMatches: Int
	var overallStats: GroupCombatStats
	var soloStats: GroupCombatStats
	var groupedStats: GroupCombatStats
	var stackSizes: [StackSizeSummary]
	var friends: [PlayerSynergyReport]
	var randoms: [PlayerSynergyReport]
	var allSelectableTeammates: [SquadMemberStat]
	var squads: [SquadPerformanceReport]
	var bestFriendPartner: PlayerSynergyReport?
	var bestSquad: SquadPerformanceReport?
}

// MARK: - Calculator

enum GroupPerformanceCalculator {
	static func stackLabel(for stackSize: Int) -> String {
		switch stackSize {
		case 1: return "Solo"
		case 2: return "Duo"
		case 3: return "Trio"
		case 4: return "4-Stack"
		case 5: return "5-Stack"
		default: return "\(stackSize)-Stack"
		}
	}
	
	static func resolveNameAndTag(
		bucketName: String,
		bucketTag: String,
		resolved: ResolvedPlayerName?,
		friendHint: GroupFriendHint?
	) -> (name: String, tag: String) {
		if !bucketName.isEmpty {
			let tag = !bucketTag.isEmpty
				? bucketTag
				: ((resolved?.tagLine.isEmpty == false ? resolved?.tagLine : nil) ?? friendHint?.tagLine ?? "")
			return (bucketName, tag)
		}
		if let resolved, !resolved.gameName.isEmpty {
			let tag = !resolved.tagLine.isEmpty
				? resolved.tagLine
				: (friendHint?.tagLine ?? "")
			return (resolved.gameName, tag)
		}
		if let friendHint, !friendHint.gameName.isEmpty {
			return (friendHint.gameName, friendHint.tagLine)
		}
		return ("", "")
	}
	
	static func compute(
		entries: [CachedGroupMatchSummary],
		rrDeltaByMatchID: [Match.ID: Int],
		friendHints: [User.ID: GroupFriendHint],
		resolvedNames: [User.ID: ResolvedPlayerName] = [:],
		isOwnAccount: Bool = true,
		selectedActID: Season.ID?,
		queueScope: GroupPerformanceQueueScope,
		sort: GroupPerformanceSort
	) -> GroupPerformanceReport {
		let filtered = entries
			.filter { entry in
				guard entry.isCompleted,
					  (selectedActID == nil || entry.seasonID == selectedActID),
					  queueScope.accepts(queueID: entry.queueID, modeID: entry.modeID) else {
					return false
				}
				return true
			}
			.sorted { $0.gameStart > $1.gameStart }
		
		var overallAccum = StatsAccumulator()
		var soloAccum = StatsAccumulator()
		var groupedAccum = StatsAccumulator()
		var stackAccumBySize: [Int: StatsAccumulator] = [:]
		
		var playerAccum: [User.ID: PlayerBucket] = [:]
		var squadAccum: [String: SquadBucket] = [:]
		var selectablePartyPlayers: [User.ID: SquadMemberAccumulator] = [:]
		
		for match in filtered {
			let rrDelta = rrDeltaByMatchID[match.matchID]
			overallAccum.addUserMatch(match, rrDelta: rrDelta)
			
			let partyTeammates = match.participants.filter(\.sameParty)
			let rawStackSize = 1 + partyTeammates.count
			let normalizedStackSize = min(5, max(1, rawStackSize))
			
			if rawStackSize == 1 {
				soloAccum.addUserMatch(match, rrDelta: rrDelta)
			} else {
				groupedAccum.addUserMatch(match, rrDelta: rrDelta)
			}
			stackAccumBySize[normalizedStackSize, default: StatsAccumulator()].addUserMatch(match, rrDelta: rrDelta)
			
			if !partyTeammates.isEmpty {
				let sortedMembers = partyTeammates.sorted { $0.id.description < $1.id.description }
				let memberIDs = sortedMembers.map(\.id)
				let squadKey = memberIDs.map(\.description).joined(separator: ",")
				
				var squad = squadAccum[squadKey] ?? SquadBucket(
					id: squadKey,
					memberIDs: memberIDs,
					stackSize: rawStackSize,
					lastPlayed: match.gameStart
				)
				squad.stats.addUserMatch(match, rrDelta: rrDelta)
				squad.maps[match.mapID, default: MapBucket(mapID: match.mapID)].addUserMatch(match)
				squad.lastPlayed = max(squad.lastPlayed, match.gameStart)
				squad.matches.append(makeSharedMatchEntry(match: match, partner: nil, partySize: rawStackSize, rrDelta: rrDelta, wasSameTeam: true, wasSameParty: true))
				for member in sortedMembers {
					squad.memberStats[member.id, default: SquadMemberAccumulator(id: member.id)].add(member, gameStart: match.gameStart)
					selectablePartyPlayers[member.id, default: SquadMemberAccumulator(id: member.id)].add(member, gameStart: match.gameStart)
				}
				squadAccum[squadKey] = squad
			}
			
			for participant in match.participants {
				var bucket = playerAccum[participant.id] ?? PlayerBucket(id: participant.id, lastPlayed: match.gameStart)
				bucket.updateIdentity(from: participant, gameStart: match.gameStart)
				bucket.totalMatches += 1
				bucket.lastPlayed = max(bucket.lastPlayed, match.gameStart)
				bucket.allStats.addUserMatch(match, rrDelta: rrDelta)
				
				if participant.sameTeam {
					bucket.teammateMatches += 1
					if participant.sameParty {
						bucket.partyMatches += 1
					}
					bucket.teammateStats.addUserMatch(match, rrDelta: rrDelta)
					bucket.partnerStats.addParticipant(participant, in: match)
					bucket.teammateMaps[match.mapID, default: MapBucket(mapID: match.mapID)].addUserMatch(match)
					if let userAgent = match.userAgentID {
						bucket.userAgents[userAgent, default: AgentBucket(agentID: userAgent)].add(
							won: match.won,
							tied: match.tied,
							kills: match.userKills,
							deaths: match.userDeaths
						)
					}
					if let partnerAgent = participant.agentID {
						bucket.partnerAgents[partnerAgent, default: AgentBucket(agentID: partnerAgent)].add(
							won: match.won,
							tied: match.tied,
							kills: participant.kills,
							deaths: participant.deaths
						)
					}
				} else {
					bucket.opponentMatches += 1
					bucket.opponentStats.addUserMatch(match, rrDelta: rrDelta)
					bucket.opponentMaps[match.mapID, default: MapBucket(mapID: match.mapID)].addUserMatch(match)
				}
				
				bucket.recentMatches.append(
					makeSharedMatchEntry(
						match: match,
						partner: participant,
						partySize: rawStackSize,
						rrDelta: rrDelta,
						wasSameTeam: participant.sameTeam,
						wasSameParty: participant.sameParty
					)
				)
				playerAccum[participant.id] = bucket
			}
		}
		
		let overallStats = overallAccum.build()
		let overallWinRate = overallStats.winRate
		
		let stackSizes: [StackSizeSummary] = [1, 2, 3, 4, 5].compactMap { size in
			guard let acc = stackAccumBySize[size], acc.matches > 0 else { return nil }
			return StackSizeSummary(
				stackSize: size,
				label: stackLabel(for: size),
				stats: acc.build()
			)
		}
		
		var friends: [PlayerSynergyReport] = []
		var randoms: [PlayerSynergyReport] = []
		
		for bucket in playerAccum.values {
			let hint = friendHints[bucket.id]
			let isRiotFriend = isOwnAccount && (hint != nil)
			let isPremade = bucket.partyMatches > 0
			guard bucket.totalMatches >= 2 else { continue }
			
			let allBuilt = bucket.allStats.build()
			let mateBuilt = bucket.teammateStats.build()
			let oppBuilt = bucket.opponentStats.build()
			let partnerBuilt = bucket.partnerStats.build()
			let primaryStats = bucket.teammateMatches > 0 ? mateBuilt : allBuilt
			let activeMaps = bucket.teammateMatches > 0 ? bucket.teammateMaps : bucket.opponentMaps
			
			let (resolvedName, resolvedTag) = resolveNameAndTag(
				bucketName: bucket.gameName,
				bucketTag: bucket.tagLine,
				resolved: resolvedNames[bucket.id],
				friendHint: hint
			)
			let resolvedCard: PlayerCard.ID? = {
				if let card = bucket.cardID, !card.isPseudoNull { return card }
				if let hintCard = hint?.cardID, !hintCard.isPseudoNull { return hintCard }
				return nil
			}()
			let resolvedTier = (bucket.competitiveTier >= 3 ? bucket.competitiveTier : nil) ?? hint?.competitiveTier
			
			let mapStats = activeMaps.values
				.map { $0.build() }
				.sorted { lhs, rhs in
					if lhs.matches != rhs.matches { return lhs.matches > rhs.matches }
					return lhs.winRate > rhs.winRate
				}
			let userAgents = bucket.userAgents.values
				.map { $0.build() }
				.sorted { lhs, rhs in
					if lhs.matches != rhs.matches { return lhs.matches > rhs.matches }
					return lhs.winRate > rhs.winRate
				}
			let partnerAgents = bucket.partnerAgents.values
				.map { $0.build() }
				.sorted { lhs, rhs in
					if lhs.matches != rhs.matches { return lhs.matches > rhs.matches }
					return lhs.winRate > rhs.winRate
				}
			
			let synergy = PlayerSynergyReport(
				id: bucket.id,
				gameName: resolvedName,
				tagLine: resolvedTag,
				cardID: resolvedCard,
				competitiveTier: resolvedTier,
				friendNote: isOwnAccount ? hint?.note : nil,
				isRiotFriend: isRiotFriend,
				isPremade: isPremade,
				totalMatches: bucket.totalMatches,
				teammateMatches: bucket.teammateMatches,
				partyMatches: bucket.partyMatches,
				opponentMatches: bucket.opponentMatches,
				stats: primaryStats,
				allEncountersStats: allBuilt,
				teammateStats: mateBuilt,
				opponentStats: oppBuilt,
				partnerStats: partnerBuilt,
				winRateDeltaVsOverall: (primaryStats.winRate - overallWinRate) * Double(100),
				mapStats: mapStats,
				topUserAgents: userAgents,
				topPartnerAgents: partnerAgents,
				recentMatches: bucket.recentMatches,
				lastPlayed: bucket.lastPlayed
			)
			
			if isRiotFriend || isPremade {
				friends.append(synergy)
			} else {
				randoms.append(synergy)
			}
		}
		
		friends.sort { comparePlayers($0, $1, sort: sort) }
		randoms.sort { comparePlayers($0, $1, sort: sort) }
		
		let squads: [SquadPerformanceReport] = squadAccum.values
			.map { bucket in
				bucket.build(
					isCustomSuperset: false,
					friendHints: friendHints,
					resolvedNames: resolvedNames,
					isOwnAccount: isOwnAccount,
					overallWinRate: overallWinRate
				)
			}
			.sorted { compareSquads($0, $1, sort: sort) }
		
		let selectableTeammates = selectablePartyPlayers.values
			.map {
				$0.build(
					friendHint: friendHints[$0.id],
					resolvedName: resolvedNames[$0.id],
					isOwnAccount: isOwnAccount
				)
			}
			.sorted { lhs, rhs in
				if lhs.matches != rhs.matches { return lhs.matches > rhs.matches }
				return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
			}
		
		let bestFriend: PlayerSynergyReport? = {
			let candidates3 = friends.filter { $0.teammateMatches >= 3 && $0.stats.decidedMatches >= 3 }
			let pool = candidates3.isEmpty ? friends.filter { $0.teammateMatches >= 2 && $0.stats.decidedMatches >= 2 } : candidates3
			return pool.max { lhs, rhs in
				if lhs.stats.winRate != rhs.stats.winRate { return lhs.stats.winRate < rhs.stats.winRate }
				return lhs.teammateMatches < rhs.teammateMatches
			}
		}()
		
		let bestSquad: SquadPerformanceReport? = {
			let pool = squads.filter { $0.stats.matches >= 2 && $0.stats.decidedMatches >= 2 }
			return pool.max { lhs, rhs in
				if lhs.stats.winRate != rhs.stats.winRate { return lhs.stats.winRate < rhs.stats.winRate }
				return lhs.stats.matches < rhs.stats.matches
			}
		}()
		
		return GroupPerformanceReport(
			analyzedMatches: filtered.count,
			overallStats: overallStats,
			soloStats: soloAccum.build(),
			groupedStats: groupedAccum.build(),
			stackSizes: stackSizes,
			friends: friends,
			randoms: randoms,
			allSelectableTeammates: selectableTeammates,
			squads: squads,
			bestFriendPartner: bestFriend,
			bestSquad: bestSquad
		)
	}
	
	static func computeCustomSquad(
		entries: [CachedGroupMatchSummary],
		rrDeltaByMatchID: [Match.ID: Int],
		friendHints: [User.ID: GroupFriendHint],
		resolvedNames: [User.ID: ResolvedPlayerName] = [:],
		isOwnAccount: Bool = true,
		selectedMemberIDs: Set<User.ID>,
		exactPartyOnly: Bool,
		selectedActID: Season.ID?,
		queueScope: GroupPerformanceQueueScope,
		overallWinRate: Double
	) -> SquadPerformanceReport? {
		guard !selectedMemberIDs.isEmpty else { return nil }
		
		let filtered = entries
			.filter { entry in
				guard entry.isCompleted,
					  (selectedActID == nil || entry.seasonID == selectedActID),
					  queueScope.accepts(queueID: entry.queueID, modeID: entry.modeID) else {
					return false
				}
				return true
			}
			.sorted { $0.gameStart > $1.gameStart }
		
		let sortedSelected = Array(selectedMemberIDs).sorted { $0.description < $1.description }
		let idString = sortedSelected.map(\.description).joined(separator: ",")
		var bucket = SquadBucket(
			id: "\(exactPartyOnly ? "exact" : "superset"):\(idString)",
			memberIDs: sortedSelected,
			stackSize: sortedSelected.count + 1,
			lastPlayed: .distantPast
		)
		var matchCount = 0
		
		for match in filtered {
			let partyTeammates = match.participants.filter(\.sameParty)
			let partyIDs = Set(partyTeammates.map(\.id))
			let matchesCriteria = exactPartyOnly
				? (partyIDs == selectedMemberIDs)
				: selectedMemberIDs.isSubset(of: partyIDs)
			guard matchesCriteria else { continue }
			
			matchCount += 1
			let rrDelta = rrDeltaByMatchID[match.matchID]
			bucket.stats.addUserMatch(match, rrDelta: rrDelta)
			bucket.maps[match.mapID, default: MapBucket(mapID: match.mapID)].addUserMatch(match)
			bucket.lastPlayed = max(bucket.lastPlayed, match.gameStart)
			bucket.matches.append(
				makeSharedMatchEntry(
					match: match,
					partner: nil,
					partySize: 1 + partyTeammates.count,
					rrDelta: rrDelta,
					wasSameTeam: true,
					wasSameParty: true
				)
			)
			for member in partyTeammates where selectedMemberIDs.contains(member.id) {
				bucket.memberStats[member.id, default: SquadMemberAccumulator(id: member.id)].add(member, gameStart: match.gameStart)
			}
		}
		
		guard matchCount > 0 else { return nil }
		return bucket.build(
			isCustomSuperset: !exactPartyOnly,
			friendHints: friendHints,
			resolvedNames: resolvedNames,
			isOwnAccount: isOwnAccount,
			overallWinRate: overallWinRate
		)
	}
	
	// MARK: - Private Helpers & Accumulators
	
	private static func makeSharedMatchEntry(
		match: CachedGroupMatchSummary,
		partner: CachedGroupParticipant?,
		partySize: Int,
		rrDelta: Int?,
		wasSameTeam: Bool,
		wasSameParty: Bool
	) -> GroupSharedMatchEntry {
		let userACS = match.userRoundsPlayed > 0
			? Int((Double(match.userScore) / Double(match.userRoundsPlayed)).rounded())
			: 0
		let partnerACS = partner.map { p in
			p.roundsPlayed > 0 ? Int((Double(p.score) / Double(p.roundsPlayed)).rounded()) : 0
		}
		return GroupSharedMatchEntry(
			id: match.matchID,
			gameStart: match.gameStart,
			mapID: match.mapID,
			queueID: match.queueID,
			won: match.won,
			tied: match.tied,
			roundsWon: match.roundsWon,
			roundsLost: match.roundsLost,
			userAgentID: match.userAgentID,
			userKills: match.userKills,
			userDeaths: match.userDeaths,
			userAssists: match.userAssists,
			userACS: userACS,
			partnerAgentID: partner?.agentID,
			partnerKills: partner?.kills,
			partnerDeaths: partner?.deaths,
			partnerAssists: partner?.assists,
			partnerACS: partnerACS,
			rrDelta: rrDelta,
			partySize: partySize,
			wasSameTeam: wasSameTeam,
			wasSameParty: wasSameParty
		)
	}
	
	private static func comparePlayers(
		_ lhs: PlayerSynergyReport,
		_ rhs: PlayerSynergyReport,
		sort: GroupPerformanceSort
	) -> Bool {
		switch sort {
		case .matches:
			if lhs.totalMatches != rhs.totalMatches { return lhs.totalMatches > rhs.totalMatches }
			if lhs.stats.winRate != rhs.stats.winRate { return lhs.stats.winRate > rhs.stats.winRate }
		case .winRate:
			if lhs.stats.winRate != rhs.stats.winRate { return lhs.stats.winRate > rhs.stats.winRate }
			if lhs.totalMatches != rhs.totalMatches { return lhs.totalMatches > rhs.totalMatches }
		case .kd:
			if lhs.stats.kd != rhs.stats.kd { return lhs.stats.kd > rhs.stats.kd }
			if lhs.totalMatches != rhs.totalMatches { return lhs.totalMatches > rhs.totalMatches }
		case .acs:
			if lhs.stats.avgACS != rhs.stats.avgACS { return lhs.stats.avgACS > rhs.stats.avgACS }
			if lhs.totalMatches != rhs.totalMatches { return lhs.totalMatches > rhs.totalMatches }
		case .recent:
			if lhs.lastPlayed != rhs.lastPlayed { return lhs.lastPlayed > rhs.lastPlayed }
			if lhs.totalMatches != rhs.totalMatches { return lhs.totalMatches > rhs.totalMatches }
		}
		if lhs.lastPlayed != rhs.lastPlayed { return lhs.lastPlayed > rhs.lastPlayed }
		return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
	}
	
	private static func compareSquads(
		_ lhs: SquadPerformanceReport,
		_ rhs: SquadPerformanceReport,
		sort: GroupPerformanceSort
	) -> Bool {
		switch sort {
		case .matches:
			if lhs.stats.matches != rhs.stats.matches { return lhs.stats.matches > rhs.stats.matches }
			if lhs.stats.winRate != rhs.stats.winRate { return lhs.stats.winRate > rhs.stats.winRate }
		case .winRate:
			if lhs.stats.winRate != rhs.stats.winRate { return lhs.stats.winRate > rhs.stats.winRate }
			if lhs.stats.matches != rhs.stats.matches { return lhs.stats.matches > rhs.stats.matches }
		case .kd:
			if lhs.stats.kd != rhs.stats.kd { return lhs.stats.kd > rhs.stats.kd }
			if lhs.stats.matches != rhs.stats.matches { return lhs.stats.matches > rhs.stats.matches }
		case .acs:
			if lhs.stats.avgACS != rhs.stats.avgACS { return lhs.stats.avgACS > rhs.stats.avgACS }
			if lhs.stats.matches != rhs.stats.matches { return lhs.stats.matches > rhs.stats.matches }
		case .recent:
			if lhs.lastPlayed != rhs.lastPlayed { return lhs.lastPlayed > rhs.lastPlayed }
			if lhs.stats.matches != rhs.stats.matches { return lhs.stats.matches > rhs.stats.matches }
		}
		if lhs.lastPlayed != rhs.lastPlayed { return lhs.lastPlayed > rhs.lastPlayed }
		return lhs.namesSummary.localizedCaseInsensitiveCompare(rhs.namesSummary) == .orderedAscending
	}
	
	private struct StatsAccumulator {
		var matches = 0
		var wins = 0
		var losses = 0
		var draws = 0
		var kills = 0
		var deaths = 0
		var assists = 0
		var totalScore = 0
		var totalRounds = 0
		var totalDamage = 0
		var headshots = 0
		var totalHits = 0
		var roundsWon = 0
		var roundsLost = 0
		var netRR = 0
		var rankedMatches = 0
		var totalPlaytime: TimeInterval = 0
		
		mutating func addUserMatch(_ match: CachedGroupMatchSummary, rrDelta: Int?) {
			matches += 1
			if match.tied {
				draws += 1
			} else if match.won {
				wins += 1
			} else {
				losses += 1
			}
			kills += match.userKills
			deaths += match.userDeaths
			assists += match.userAssists
			totalScore += match.userScore
			totalRounds += max(0, match.userRoundsPlayed)
			totalDamage += match.userDamage
			headshots += match.userHeadshots
			totalHits += (match.userHeadshots + match.userBodyshots + match.userLegshots)
			roundsWon += match.roundsWon
			roundsLost += match.roundsLost
			totalPlaytime += match.gameLength
			if let rrDelta {
				netRR += rrDelta
				rankedMatches += 1
			}
		}
		
		mutating func addParticipant(_ participant: CachedGroupParticipant, in match: CachedGroupMatchSummary) {
			matches += 1
			if match.tied {
				draws += 1
			} else if match.won {
				wins += 1
			} else {
				losses += 1
			}
			kills += participant.kills
			deaths += participant.deaths
			assists += participant.assists
			totalScore += participant.score
			totalRounds += max(0, participant.roundsPlayed)
			headshots += participant.headshots
			totalHits += participant.totalHits
			roundsWon += match.roundsWon
			roundsLost += match.roundsLost
			totalPlaytime += match.gameLength
		}
		
		func build() -> GroupCombatStats {
			GroupCombatStats(
				matches: matches,
				wins: wins,
				losses: losses,
				draws: draws,
				kills: kills,
				deaths: deaths,
				assists: assists,
				totalScore: totalScore,
				totalRounds: totalRounds,
				totalDamage: totalDamage,
				headshots: headshots,
				totalHits: totalHits,
				roundsWon: roundsWon,
				roundsLost: roundsLost,
				netRR: netRR,
				rankedMatches: rankedMatches,
				totalPlaytime: totalPlaytime
			)
		}
	}
	
	private struct MapBucket {
		var mapID: MapID
		var matches = 0
		var wins = 0
		var losses = 0
		var draws = 0
		var kills = 0
		var deaths = 0
		var totalScore = 0
		var totalRounds = 0
		
		mutating func addUserMatch(_ match: CachedGroupMatchSummary) {
			matches += 1
			if match.tied {
				draws += 1
			} else if match.won {
				wins += 1
			} else {
				losses += 1
			}
			kills += match.userKills
			deaths += match.userDeaths
			totalScore += match.userScore
			totalRounds += max(0, match.userRoundsPlayed)
		}
		
		func build() -> GroupMapStat {
			let decided = wins + losses
			return GroupMapStat(
				id: mapID,
				matches: matches,
				wins: wins,
				losses: losses,
				draws: draws,
				winRate: decided > 0 ? Double(wins) / Double(decided) : Double(0),
				kd: deaths > 0 ? Double(kills) / Double(deaths) : Double(kills),
				avgACS: totalRounds > 0 ? Double(totalScore) / Double(totalRounds) : Double(0)
			)
		}
	}
	
	private struct AgentBucket {
		var agentID: Agent.ID
		var matches = 0
		var wins = 0
		var losses = 0
		var kills = 0
		var deaths = 0
		
		mutating func add(won: Bool, tied: Bool, kills: Int, deaths: Int) {
			matches += 1
			if !tied {
				if won { wins += 1 } else { losses += 1 }
			}
			self.kills += kills
			self.deaths += deaths
		}
		
		func build() -> GroupAgentStat {
			let decided = wins + losses
			return GroupAgentStat(
				id: agentID,
				matches: matches,
				wins: wins,
				winRate: decided > 0 ? Double(wins) / Double(decided) : Double(0),
				kd: deaths > 0 ? Double(kills) / Double(deaths) : Double(kills)
			)
		}
	}
	
	private struct PlayerBucket {
		var id: User.ID
		var gameName = ""
		var tagLine = ""
		var cardID: PlayerCard.ID?
		var competitiveTier = 0
		var latestIdentityDate: Date = .distantPast
		var totalMatches = 0
		var teammateMatches = 0
		var partyMatches = 0
		var opponentMatches = 0
		var allStats = StatsAccumulator()
		var teammateStats = StatsAccumulator()
		var opponentStats = StatsAccumulator()
		var partnerStats = StatsAccumulator()
		var teammateMaps: [MapID: MapBucket] = [:]
		var opponentMaps: [MapID: MapBucket] = [:]
		var userAgents: [Agent.ID: AgentBucket] = [:]
		var partnerAgents: [Agent.ID: AgentBucket] = [:]
		var recentMatches: [GroupSharedMatchEntry] = []
		var lastPlayed: Date
		
		mutating func updateIdentity(from participant: CachedGroupParticipant, gameStart: Date) {
			guard gameStart >= latestIdentityDate || gameName.isEmpty else { return }
			latestIdentityDate = gameStart
			if !participant.gameName.isEmpty {
				gameName = participant.gameName
				tagLine = participant.tagLine
			}
			if !participant.cardID.isPseudoNull {
				cardID = participant.cardID
			}
			if participant.competitiveTier >= 3 {
				competitiveTier = participant.competitiveTier
			}
		}
	}
	
	private struct SquadMemberAccumulator {
		var id: User.ID
		var gameName = ""
		var tagLine = ""
		var cardID: PlayerCard.ID?
		var competitiveTier = 0
		var latestIdentityDate: Date = .distantPast
		var matches = 0
		var kills = 0
		var deaths = 0
		var assists = 0
		var totalScore = 0
		var totalRounds = 0
		var headshots = 0
		var totalHits = 0
		var agentCounts: [Agent.ID: Int] = [:]
		
		mutating func add(_ member: CachedGroupParticipant, gameStart: Date) {
			if gameStart >= latestIdentityDate || gameName.isEmpty {
				latestIdentityDate = gameStart
				if !member.gameName.isEmpty {
					gameName = member.gameName
					tagLine = member.tagLine
				}
				if !member.cardID.isPseudoNull {
					cardID = member.cardID
				}
				if member.competitiveTier >= 3 {
					competitiveTier = member.competitiveTier
				}
			}
			matches += 1
			kills += member.kills
			deaths += member.deaths
			assists += member.assists
			totalScore += member.score
			totalRounds += max(0, member.roundsPlayed)
			headshots += member.headshots
			totalHits += member.totalHits
			if let agentID = member.agentID {
				agentCounts[agentID, default: 0] += 1
			}
		}
		
		func build(
			friendHint: GroupFriendHint?,
			resolvedName resolvedEntry: ResolvedPlayerName?,
			isOwnAccount: Bool
		) -> SquadMemberStat {
			let (resolvedName, resolvedTag) = GroupPerformanceCalculator.resolveNameAndTag(
				bucketName: gameName,
				bucketTag: tagLine,
				resolved: resolvedEntry,
				friendHint: friendHint
			)
			let resolvedCard: PlayerCard.ID? = {
				if let cardID, !cardID.isPseudoNull { return cardID }
				if let hintCard = friendHint?.cardID, !hintCard.isPseudoNull { return hintCard }
				return nil
			}()
			let resolvedTier = (competitiveTier >= 3 ? competitiveTier : nil) ?? friendHint?.competitiveTier
			let topAgent = agentCounts.max { lhs, rhs in
				if lhs.value != rhs.value { return lhs.value < rhs.value }
				return lhs.key.description < rhs.key.description
			}?.key
			
			return SquadMemberStat(
				id: id,
				gameName: resolvedName,
				tagLine: resolvedTag,
				cardID: resolvedCard,
				competitiveTier: resolvedTier,
				isRiotFriend: isOwnAccount && (friendHint != nil),
				matches: matches,
				kills: kills,
				deaths: deaths,
				assists: assists,
				kd: deaths > 0 ? Double(kills) / Double(deaths) : Double(kills),
				avgACS: totalRounds > 0 ? Double(totalScore) / Double(totalRounds) : Double(0),
				hsPercent: totalHits > 0 ? (Double(headshots) / Double(totalHits)) * Double(100) : Double(0),
				topAgentID: topAgent
			)
		}
	}
	
	private struct SquadBucket {
		var id: String
		var memberIDs: [User.ID]
		var stackSize: Int
		var stats = StatsAccumulator()
		var maps: [MapID: MapBucket] = [:]
		var memberStats: [User.ID: SquadMemberAccumulator] = [:]
		var matches: [GroupSharedMatchEntry] = []
		var lastPlayed: Date
		
		func build(
			isCustomSuperset: Bool,
			friendHints: [User.ID: GroupFriendHint],
			resolvedNames: [User.ID: ResolvedPlayerName],
			isOwnAccount: Bool,
			overallWinRate: Double
		) -> SquadPerformanceReport {
			let builtStats = stats.build()
			let builtMembers = memberIDs.map { id in
				let acc = memberStats[id] ?? SquadMemberAccumulator(id: id)
				return acc.build(
					friendHint: friendHints[id],
					resolvedName: resolvedNames[id],
					isOwnAccount: isOwnAccount
				)
			}
			let builtMaps = maps.values
				.map { $0.build() }
				.sorted { lhs, rhs in
					if lhs.matches != rhs.matches { return lhs.matches > rhs.matches }
					return lhs.winRate > rhs.winRate
				}
			return SquadPerformanceReport(
				id: id,
				memberIDs: memberIDs,
				members: builtMembers,
				stackSize: stackSize,
				isCustomSuperset: isCustomSuperset,
				stats: builtStats,
				winRateDeltaVsOverall: (builtStats.winRate - overallWinRate) * Double(100),
				mapStats: builtMaps,
				recentMatches: matches,
				lastPlayed: lastPlayed
			)
		}
	}
}
