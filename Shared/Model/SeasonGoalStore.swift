import Foundation
import ValorantAPI

struct SeasonGoal: Identifiable, Codable, Equatable {
	var id = UUID()
	var accountID: User.ID?
	var actID: Season.ID?
	var targetTier: Int
	var baselineTier: Int
	var baselineRR: Int
	var baselineElo: Int
	var createdAt = Date()
	var showsOnProfile = true
}

enum SeasonGoalStatus: Equatable {
	case reached
	case onTrack(projectedDate: Date)
	case behindPace(projectedDate: Date?)
	case negativePace
	case needsMoreData(playedCount: Int, requiredCount: Int)
}

struct SeasonGoalDivisionStep: Identifiable, Equatable {
	var id: Int { tier }
	var tier: Int
	var name: String
	/// 0...1 completion through this division band `[startElo ..< endElo]`
	var fillFraction: Double
	var rrToReach: Int
	var isCompleted: Bool
}

struct SeasonGoalTrajectory {
	var currentTier: Int
	var currentRR: Int
	var currentTierName: String
	var targetTier: Int
	var targetTierName: String
	var gamesNeededForRating: Int
	
	var currentElo: Int
	var targetElo: Int
	var rrToGo: Int
	var rrSinceSet: Int
	/// 0...1 climb progress from `goal.baselineElo` to `targetElo`
	var progress: Double
	
	var daysLeft: Int
	var actEndDate: Date?
	var isPreviousAct: Bool
	
	var matchesPlayed: Int
	var wins: Int
	var losses: Int
	var winRate: Double
	var avgRRPerMatch: Double
	var avgGain: Double
	var avgLoss: Double
	var matchesPerDay: Double
	var matchesLeft: Int?
	var requiredMatchesPerDay: Double?
	var requiredWinRate: Double?
	var momentumDelta: Double?
	var currentStreak: Int
	var recentChanges: [Int]
	
	var status: SeasonGoalStatus
	var divisions: [SeasonGoalDivisionStep]
	var startDivisionTier: Int
	var nextDivision: (tier: Int, name: String, rrToGo: Int)?
}

@MainActor
final class SeasonGoalStore: ObservableObject {
	@Published var goals: [SeasonGoal] = []
	
	private let filename = "SeasonGoals.v2.json"
	private var hasLoadedFromDisk = false
	private var initialLoadTask: Task<Void, Never>?
	private var pendingRemovedIDs: Set<UUID> = []
	private var pendingReplacedKeys: Set<String> = []
	private var pendingSaveTask: Task<Void, Never>?
	
	init() {
		initialLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let loaded = await LocalJSONStore.loadAsync([SeasonGoal].self, from: self.filename) ?? []
			self.mergeDiskGoals(loaded)
		}
	}
	
	func waitUntilLoaded() async {
		if let initialLoadTask, !hasLoadedFromDisk {
			await initialLoadTask.value
		}
	}
	
	private static func scopeKey(accountID: User.ID?, actID: Season.ID?) -> String {
		"\(accountID?.description ?? "*")_\(actID?.description ?? "*")"
	}
	
	private func mergeDiskGoals(_ diskGoals: [SeasonGoal]) {
		hasLoadedFromDisk = true
		guard !diskGoals.isEmpty else {
			pendingRemovedIDs.removeAll()
			pendingReplacedKeys.removeAll()
			return
		}
		if goals.isEmpty && pendingRemovedIDs.isEmpty && pendingReplacedKeys.isEmpty {
			goals = diskGoals
			return
		}
		var working = goals
		var seenIDs = Set(working.map(\.id))
		for diskGoal in diskGoals {
			let key = Self.scopeKey(accountID: diskGoal.accountID, actID: diskGoal.actID)
			guard !pendingRemovedIDs.contains(diskGoal.id),
				  !pendingReplacedKeys.contains(key),
				  seenIDs.insert(diskGoal.id).inserted else { continue }
			working.append(diskGoal)
		}
		working.sort { $0.createdAt > $1.createdAt }
		pendingRemovedIDs.removeAll()
		pendingReplacedKeys.removeAll()
		goals = working
	}
	
	func goal(for accountID: User.ID?, actID: Season.ID?) -> SeasonGoal? {
		let matchingAccount = goals.filter { goal in
			goal.accountID == accountID || accountID == nil || goal.accountID == nil
		}
		if let actID, let exact = matchingAccount.first(where: { $0.actID == actID }) {
			return exact
		}
		return matchingAccount.max { $0.createdAt < $1.createdAt }
	}
	
	func setGoal(
		accountID: User.ID?,
		actID: Season.ID?,
		targetTier: Int,
		currentTier: Int,
		currentRR: Int,
		tiers: CompetitiveTier.Collection?,
		showsOnProfile: Bool? = nil
	) {
		let baselineTier = currentTier >= 3 ? currentTier : targetTier
		let baselineRR = currentTier >= 3 ? currentRR : 0
		let baselineElo = Self.elo(tier: baselineTier, rr: baselineRR, tiers: tiers)
		let existingProfilePref = goal(for: accountID, actID: actID)?.showsOnProfile ?? true
		
		if !hasLoadedFromDisk {
			pendingReplacedKeys.insert(Self.scopeKey(accountID: accountID, actID: actID))
		}
		goals.removeAll { g in
			(g.accountID == accountID || accountID == nil)
				&& (actID == nil || g.actID == nil || g.actID == actID)
		}
		let newGoal = SeasonGoal(
			accountID: accountID,
			actID: actID,
			targetTier: targetTier,
			baselineTier: baselineTier,
			baselineRR: baselineRR,
			baselineElo: baselineElo,
			createdAt: Date(),
			showsOnProfile: showsOnProfile ?? existingProfilePref
		)
		goals.insert(newGoal, at: 0)
		persist()
	}
	
	func toggleShowOnProfile(id: UUID) {
		guard let idx = goals.firstIndex(where: { $0.id == id }) else { return }
		goals[idx].showsOnProfile.toggle()
		persist()
	}
	
	func removeGoal(id: UUID) {
		if !hasLoadedFromDisk {
			pendingRemovedIDs.insert(id)
		}
		let before = goals.count
		goals.removeAll { $0.id == id }
		guard goals.count != before else { return }
		persist()
	}
	
	func exportGoals(for playerIDs: Set<User.ID>?) -> [SeasonGoal] {
		guard let playerIDs else { return goals }
		return goals.filter { goal in
			guard let accountID = goal.accountID else { return !playerIDs.isEmpty }
			return playerIDs.contains(accountID)
		}
	}
	
	@discardableResult
	func importGoals(_ incoming: [SeasonGoal], replaceAll: Bool) async -> Int {
		await waitUntilLoaded()
		pendingSaveTask?.cancel()
		var working = replaceAll ? [] : goals
		var indexByID: [UUID: Int] = Dictionary(uniqueKeysWithValues: working.enumerated().map { ($1.id, $0) })
		var indexByScope: [String: Int] = [:]
		for (idx, existing) in working.enumerated() {
			let key = Self.scopeKey(accountID: existing.accountID, actID: existing.actID)
			if indexByScope[key] == nil {
				indexByScope[key] = idx
			}
		}
		var changedCount = 0
		
		for goal in incoming {
			let scope = Self.scopeKey(accountID: goal.accountID, actID: goal.actID)
			if let idx = indexByID[goal.id] {
				if goal.createdAt > working[idx].createdAt {
					working[idx] = goal
					changedCount += 1
				}
			} else if let idx = indexByScope[scope] {
				if goal.createdAt > working[idx].createdAt {
					indexByID.removeValue(forKey: working[idx].id)
					working[idx] = goal
					indexByID[goal.id] = idx
					changedCount += 1
				}
			} else {
				let idx = working.count
				working.append(goal)
				indexByID[goal.id] = idx
				indexByScope[scope] = idx
				changedCount += 1
			}
		}
		
		working.sort { $0.createdAt > $1.createdAt }
		goals = working
		await LocalJSONStore.saveAndWait(goals, to: filename)
		return replaceAll ? working.count : changedCount
	}
	
	private func persist() {
		if hasLoadedFromDisk {
			LocalJSONStore.save(goals, to: filename)
		} else {
			pendingSaveTask?.cancel()
			pendingSaveTask = Task { @MainActor [weak self] in
				await self?.waitUntilLoaded()
				guard let self, !Task.isCancelled else { return }
				LocalJSONStore.save(self.goals, to: self.filename)
			}
		}
	}
	
	// MARK: - Elo & Trajectory Calculation
	
	nonisolated static func lowestImmortalTier(in tiers: CompetitiveTier.Collection?) -> Int {
		tiers?.lowestImmortalPlusTier() ?? 24
	}
	
	nonisolated static func elo(tier: Int, rr: Int, tiers: CompetitiveTier.Collection?) -> Int {
		guard tier >= 3 else { return 0 }
		let lowestImm = lowestImmortalTier(in: tiers)
		if tier < lowestImm {
			return (tier - 3) * 100 + max(0, min(99, rr))
		}
		// In Immortal+, Riot stores `rr` cumulatively from Immortal 1 (0 RR).
		let immBase = (lowestImm - 3) * 100
		return immBase + max(0, rr)
	}
	
	nonisolated static func targetThresholdElo(for targetTier: Int, tiers: CompetitiveTier.Collection?) -> Int {
		guard targetTier >= 3 else { return 0 }
		let lowestImm = lowestImmortalTier(in: tiers)
		if targetTier <= lowestImm {
			return (targetTier - 3) * 100
		}
		let immBase = (lowestImm - 3) * 100
		let offset = targetTier - lowestImm
		switch offset {
		case 1: return immBase + 100 // Immortal 2
		case 2: return immBase + 200 // Immortal 3
		default: return immBase + 450 // Radiant threshold baseline
		}
	}
	
	nonisolated static func currentRank(
		summary: CareerSummary?,
		matchList: MatchList?,
		act: Act?
	) -> (tier: Int, rr: Int, gamesNeeded: Int) {
		if let act, let seasonInfo = summary?.competitiveInfo?.bySeason?[act.id], seasonInfo.competitiveTier >= 3 {
			return (seasonInfo.competitiveTier, seasonInfo.adjustedRankedRating, seasonInfo.gamesNeededForRating)
		}
		if let latestRanked = matchList?.matches.first(where: { $0.isRanked && (act == nil || act!.timeSpan.contains($0.startTime)) }) {
			return (latestRanked.tierAfterUpdate, latestRanked.tierProgressAfterUpdate, 0)
		}
		if let latest = summary?.latestUpdate, latest.isRanked {
			return (latest.tierAfterUpdate, latest.tierProgressAfterUpdate, 0)
		}
		let gamesNeeded = act.flatMap { summary?.competitiveInfo?.bySeason?[$0.id]?.gamesNeededForRating } ?? 0
		return (0, 0, gamesNeeded)
	}
	
	nonisolated static func compute(
		goal: SeasonGoal,
		summary: CareerSummary?,
		matchList: MatchList?,
		currentAct: Act?,
		seasons: SeasonCollection.Accessor?
	) -> SeasonGoalTrajectory {
		let tiers = seasons?.currentTiers()
		let rank = currentRank(summary: summary, matchList: matchList, act: currentAct)
		let currentTierName = tiers?.tier(rank.tier)?.name ?? (rank.tier == 0 ? "Unranked" : "Tier \(rank.tier)")
		let targetTierName = tiers?.tier(goal.targetTier)?.name ?? "Tier \(goal.targetTier)"
		
		let currentElo = elo(tier: rank.tier, rr: rank.rr, tiers: tiers)
		let targetElo = targetThresholdElo(for: goal.targetTier, tiers: tiers)
		let rrToGo = max(0, targetElo - currentElo)
		let effectiveBaselineElo = rank.tier >= 3 ? goal.baselineElo : 0
		let rrSinceSet = rank.tier >= 3 ? (currentElo - effectiveBaselineElo) : 0
		
		let progress: Double = {
			if rrToGo == 0 && rank.tier >= goal.targetTier { return Double(1) }
			let denom = targetElo - effectiveBaselineElo
			if denom > 0 {
				return min(Double(1), max(Double(0), Double(currentElo - effectiveBaselineElo) / Double(denom)))
			}
			return rank.tier >= goal.targetTier ? Double(1) : Double(0)
		}()
		
		let isPreviousAct = (goal.actID != nil && currentAct != nil && goal.actID != currentAct?.id)
		let actEnd = currentAct?.timeSpan.end
		let actStart = currentAct?.timeSpan.start ?? goal.createdAt
		let now = Date()
		let daysLeft: Int = {
			guard let actEnd else { return 0 }
			let secs = max(Double(0), actEnd.timeIntervalSince(now))
			return Int(ceil(secs / Double(86_400)))
		}()
		
		// Ranked matches from this Act, chronological oldest -> newest for streak, newest first for chips.
		let actRanked = (matchList?.matches ?? []).filter { match in
			guard match.isRanked && !match.isDodge else { return false }
			if let currentAct {
				return currentAct.timeSpan.contains(match.startTime)
			}
			return true
		}
		.sorted { $0.startTime > $1.startTime }
		
		let recentChanges = Array(actRanked.prefix(10).map(\.ratingEarned))
		let currentStreak: Int = {
			guard let first = actRanked.first?.ratingEarned, first != 0 else { return 0 }
			let positive = first > 0
			var count = 0
			for m in actRanked {
				if m.ratingEarned == 0 { continue }
				if (m.ratingEarned > 0) == positive {
					count += 1
				} else {
					break
				}
			}
			return positive ? count : -count
		}()
		
		let matchesPlayed = actRanked.count
		var wins = 0
		var losses = 0
		var totalRR = 0
		var totalGain = 0
		var totalLossAbs = 0
		for match in actRanked {
			let rr = match.ratingEarned
			totalRR += rr
			if rr > 0 {
				wins += 1
				totalGain += rr
			} else if rr < 0 {
				losses += 1
				totalLossAbs += -rr
			}
		}
		let decided = wins + losses
		let winRate: Double = decided > 0 ? (Double(wins) / Double(decided)) : Double(0)
		let avgRR: Double = matchesPlayed > 0 ? Double(totalRR) / Double(matchesPlayed) : Double(0)
		let avgGain: Double = wins == 0 ? Double(20) : Double(totalGain) / Double(wins)
		let avgLoss: Double = losses == 0 ? Double(18) : Double(totalLossAbs) / Double(losses)
		
		let firstMatchDate = actRanked.last?.startTime ?? actStart
		let spanStart = max(actStart, firstMatchDate)
		let daysActive = max(Double(1), now.timeIntervalSince(spanStart) / Double(86_400))
		let matchesPerDay = Double(matchesPlayed) / daysActive
		
		let momentumDelta: Double? = {
			guard actRanked.count >= 5 else { return nil }
			let recent5 = Double(actRanked.prefix(5).reduce(0) { $0 + $1.ratingEarned }) / Double(5)
			return recent5 - avgRR
		}()
		
		let matchesLeft: Int? = {
			if rrToGo == 0 { return 0 }
			guard avgRR > Double(0.25) else { return nil }
			return Int(ceil(Double(rrToGo) / avgRR))
		}()
		
		let projectedDate: Date? = {
			guard let left = matchesLeft, left > 0, matchesPerDay > Double(0.05) else { return nil }
			let daysNeeded = Double(left) / matchesPerDay
			guard daysNeeded < Double(3650) else { return nil }
			return now.addingTimeInterval(daysNeeded * Double(86_400))
		}()
		
		let requiredMatchesPerDay: Double? = {
			guard rrToGo > 0, daysLeft > 0 else { return nil }
			let paceDenom = max(avgRR, Double(5))
			return (Double(rrToGo) / paceDenom) / Double(daysLeft)
		}()
		
		let requiredWinRate: Double? = {
			guard rrToGo > 0, daysLeft > 0 else { return nil }
			let estMatches = max(1, Int(round(max(matchesPerDay, Double(0.5)) * Double(daysLeft))))
			let neededAvgRR = Double(rrToGo) / Double(estMatches)
			// neededAvgRR = wr * avgGain - (1 - wr) * avgLoss => wr = (neededAvgRR + avgLoss) / (avgGain + avgLoss)
			let denom = avgGain + avgLoss
			guard denom > Double(0) else { return nil }
			let raw = (neededAvgRR + avgLoss) / denom
			return min(Double(1), max(Double(0), raw))
		}()
		
		let minSample = 3
		let status: SeasonGoalStatus = {
			if rrToGo == 0 && rank.tier >= goal.targetTier {
				return .reached
			}
			if matchesPlayed < minSample {
				return .needsMoreData(playedCount: matchesPlayed, requiredCount: minSample)
			}
			if avgRR <= Double(0) {
				return .negativePace
			}
			if let projectedDate {
				if let actEnd, projectedDate <= actEnd {
					return .onTrack(projectedDate: projectedDate)
				}
				return .behindPace(projectedDate: projectedDate)
			}
			return .behindPace(projectedDate: nil)
		}()
		
		// Division steps for "The Climb"
		let lowestImm = lowestImmortalTier(in: tiers)
		let baselineTierValid = goal.baselineTier >= 3 ? goal.baselineTier : max(3, rank.tier >= 3 ? rank.tier : goal.targetTier - 3)
		let startTier = min(baselineTierValid, rank.tier >= 3 ? rank.tier : baselineTierValid, max(3, goal.targetTier - 1))
		
		let sortedTierNumbers = (tiers?.tiers.values
			.map(\.number)
			.filter { $0 >= 3 }
			.sorted()) ?? Array(3...27)
		
		let climbTiers = sortedTierNumbers.filter { $0 >= startTier && $0 < goal.targetTier }
		let steps: [SeasonGoalDivisionStep] = climbTiers.map { tierNum in
			let bandStart = targetThresholdElo(for: tierNum, tiers: tiers)
			let nextTierNum = sortedTierNumbers.first(where: { $0 > tierNum }) ?? (tierNum + 1)
			let bandEnd = min(targetElo, targetThresholdElo(for: nextTierNum, tiers: tiers))
			let span = max(1, bandEnd - bandStart)
			let fraction: Double = {
				if currentElo >= bandEnd { return Double(1) }
				if currentElo <= bandStart { return Double(0) }
				return Double(currentElo - bandStart) / Double(span)
			}()
			let stepName = tiers?.tier(nextTierNum)?.name ?? "Tier \(nextTierNum)"
			return SeasonGoalDivisionStep(
				tier: nextTierNum,
				name: stepName,
				fillFraction: fraction,
				rrToReach: max(0, bandEnd - currentElo),
				isCompleted: currentElo >= bandEnd
			)
		}
		
		let nextDiv: (tier: Int, name: String, rrToGo: Int)? = {
			guard rrToGo > 0, rank.tier < goal.targetTier else { return nil }
			if rank.tier < 3 {
				let startRankNum = sortedTierNumbers.first ?? 3
				let nextName = tiers?.tier(startRankNum)?.name ?? "Iron 1"
				return (startRankNum, nextName, max(0, 100 - rank.rr))
			}
			if rank.tier >= lowestImm {
				let imm2Threshold = targetThresholdElo(for: goal.targetTier, tiers: tiers)
				let nextT = sortedTierNumbers.first(where: { $0 > rank.tier }) ?? goal.targetTier
				let stepTarget = min(imm2Threshold, targetThresholdElo(for: nextT, tiers: tiers))
				let nextName = tiers?.tier(nextT)?.name ?? targetTierName
				return (nextT, nextName, max(0, stepTarget - currentElo))
			}
			let nextT = sortedTierNumbers.first(where: { $0 > rank.tier }) ?? min(goal.targetTier, rank.tier + 1)
			let nextName = tiers?.tier(nextT)?.name ?? "Tier \(nextT)"
			return (nextT, nextName, max(0, 100 - rank.rr))
		}()
		
		return SeasonGoalTrajectory(
			currentTier: rank.tier,
			currentRR: rank.rr,
			currentTierName: currentTierName,
			targetTier: goal.targetTier,
			targetTierName: targetTierName,
			gamesNeededForRating: rank.gamesNeeded,
			currentElo: currentElo,
			targetElo: targetElo,
			rrToGo: rrToGo,
			rrSinceSet: rrSinceSet,
			progress: progress,
			daysLeft: daysLeft,
			actEndDate: actEnd,
			isPreviousAct: isPreviousAct,
			matchesPlayed: matchesPlayed,
			wins: wins,
			losses: losses,
			winRate: winRate,
			avgRRPerMatch: avgRR,
			avgGain: avgGain,
			avgLoss: avgLoss,
			matchesPerDay: matchesPerDay,
			matchesLeft: matchesLeft,
			requiredMatchesPerDay: requiredMatchesPerDay,
			requiredWinRate: requiredWinRate,
			momentumDelta: momentumDelta,
			currentStreak: currentStreak,
			recentChanges: recentChanges,
			status: status,
			divisions: steps,
			startDivisionTier: startTier,
			nextDivision: nextDiv
		)
	}
}
