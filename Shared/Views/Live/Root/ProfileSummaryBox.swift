import SwiftUI
import ValorantAPI

/// The profile side of the combined Live/Profile tab: current rank, this act's career
/// summary, a session recap and win rate computed locally from cached matches, and the
/// player's three most-advanced agent contracts.
struct ProfileSummaryBox: View {
	let userID: User.ID
	var contractsProgress: ContractsProgress?

	@LocalData var user: User?
	@LocalData var summary: CareerSummary?
	@LocalData var matchList: MatchList?

	@Environment(\.seasons) private var seasons
	@Environment(\.assets) private var assets

	private let rankIconSize = 76.0

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			header

			Divider()

			careerSection

			Divider()

			sessionSection

			Divider()

			masterySection
		}
		.padding()
		.background(Color.secondaryGroupedBackground)
		.cornerRadius(20)
		.withLocalData($user, id: userID, shouldAutoUpdate: true)
		.withLocalData($summary, id: userID, shouldAutoUpdate: true)
		.withLocalData($matchList, id: userID, shouldAutoUpdate: true)
	}

	// MARK: Header

	private var header: some View {
		HStack(alignment: .center, spacing: 16) {
			RankInfoView(summary: summary, size: rankIconSize, lineWidth: 4)

			VStack(alignment: .leading, spacing: 4) {
				if let user {
					Text(verbatim: "\(user.gameName)#\(user.tagLine)")
						.font(.system(.headline, design: .rounded))
						.lineLimit(1)
				} else {
					Text("Not signed in", comment: "Profile box: shown when the signed-in user hasn't loaded")
						.font(.system(.headline, design: .rounded))
						.foregroundColor(.secondary)
				}

				Group {
					if currentTier > 0, let currentTierInfo {
						Text(currentTierInfo.name)
					} else if summary != nil || seasons != nil {
						Text("Unranked", comment: "Profile box: no rank in the current act")
					} else {
						Text("Rank unavailable", comment: "Profile box: rank data hasn't loaded")
					}
				}
				.font(.system(.subheadline, design: .rounded).weight(.semibold))
				.foregroundColor(.secondary)

				if let act = currentAct {
					Text(act.name)
						.font(.system(.caption, design: .rounded))
						.foregroundColor(.secondary)
				}

				if currentTier > 0 {
					Text(verbatim: "\(currentRR) RR")
						.font(.system(.caption, design: .rounded).weight(.bold))
						.monospacedDigit()
						.foregroundColor(.secondary)
				}
			}

			Spacer(minLength: 0)
		}
	}

	// MARK: Career summary

	private var careerSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			sectionHeader("Career Summary")

			if let info = currentSeasonInfo {
				HStack(spacing: 24) {
					stat("Games", "\(info.gameCount)")
					stat("Wins", "\(info.winCountIncludingPlacements)")
					stat("Win Rate", percent(info.winCountIncludingPlacements, of: info.gameCount))
				}
			} else {
				Text("No ranked games this act yet.", comment: "Profile box: no competitive games in the current act")
					.font(.system(.subheadline, design: .rounded))
					.foregroundColor(.secondary)
			}

			if let summary {
				NavigationLink(destination: CareerSummaryView(summary: summary)) {
					HStack(spacing: 4) {
						Text("Full Career Summary", comment: "Profile box: link to the full career summary screen")
						Image(systemName: "chevron.right")
							.font(.caption2.weight(.semibold))
					}
					.font(.system(.subheadline, design: .rounded).weight(.semibold))
				}
			}
		}
	}

	// MARK: Session recap & win rate (computed locally from the cached match list)

	private var sessionSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			sectionHeader("Today's Session")

			if todaysMatches.isEmpty {
				Text("No matches played today.", comment: "Profile box: no matches today")
					.font(.system(.subheadline, design: .rounded))
					.foregroundColor(.secondary)
			} else {
				HStack(spacing: 24) {
					stat("Matches", "\(todaysMatches.count)")
					stat("Ranked Record", "\(todayWins)–\(todayLosses)")
					stat("RR Change", todayRRChange > 0 ? "+\(todayRRChange)" : "\(todayRRChange)")
				}
			}

			if !recentRankedMatches.isEmpty {
				HStack(spacing: 24) {
					stat("Recent Win Rate", percent(recentWins, of: recentWins + recentLosses))
					stat("Record", "\(recentWins)W–\(recentLosses)L", detail: "last \(recentRankedMatches.count) ranked")
				}
			}
		}
	}

	// MARK: Agent mastery

	private var masterySection: some View {
		VStack(alignment: .leading, spacing: 10) {
			sectionHeader("Agent Mastery")

			if masteryEntries.isEmpty {
				Text("Agent contracts didn't load.", comment: "Profile box: agent contracts unavailable")
					.font(.system(.subheadline, design: .rounded))
					.foregroundColor(.secondary)
			} else {
				ForEach(masteryEntries) { entry in
					masteryRow(for: entry)
				}
			}
		}
	}

	private func masteryRow(for entry: MasteryEntry) -> some View {
		let contract = entry.contract
		let nextLevelXP = xpForNextLevel(of: contract)
		let progress: Double
		if let nextLevelXP, nextLevelXP > 0 {
			progress = min(1, Double(contract.progressionTowardsNextLevel) / Double(nextLevelXP))
		} else {
			progress = 1
		}

		return HStack(spacing: 12) {
			AgentImage.icon(entry.agentID)
				.frame(width: 32, height: 32)
				.mask(Circle())

			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text(assets?.agents[entry.agentID]?.displayName ?? "Unknown Agent")
						.font(.system(.subheadline, design: .rounded).weight(.semibold))
						.lineLimit(1)

					Spacer(minLength: 8)

					Text("Level \(contract.levelReached)", comment: "Profile box: agent contract level")
						.font(.system(.caption, design: .rounded).weight(.medium))
						.foregroundColor(.secondary)
						.monospacedDigit()
				}

				ProgressView(value: progress)
					.tint(Color.accentColor)
			}
		}
	}

	// MARK: Data

	private var currentAct: Act? {
		seasons?.currentAct()
	}

	private var currentSeasonInfo: CareerSummary.SeasonInfo? {
		summary?.competitiveInfo?.inSeason(currentAct?.id)
	}

	private var currentTier: Int {
		currentSeasonInfo?.competitiveTier ?? 0
	}

	private var currentRR: Int {
		currentSeasonInfo?.adjustedRankedRating ?? 0
	}

	private var currentTierInfo: CompetitiveTier? {
		seasons?.tierInfo(number: currentTier, in: currentAct)
	}

	private var todaysMatches: [CompetitiveUpdate] {
		let calendar = Calendar.current
		return (matchList?.matches ?? []).filter { calendar.isDateInToday($0.startTime) }
	}

	private var recentRankedMatches: [CompetitiveUpdate] {
		Array((matchList?.matches ?? []).filter(\.isRanked).prefix(20))
	}

	private var todayWins: Int {
		todaysMatches.filter { isWin($0) == true }.count
	}

	private var todayLosses: Int {
		todaysMatches.filter { isWin($0) == false }.count
	}

	private var todayRRChange: Int {
		todaysMatches.filter(\.isRanked).map(\.ratingEarned).reduce(0, +)
	}

	private var recentWins: Int {
		recentRankedMatches.filter { isWin($0) == true }.count
	}

	private var recentLosses: Int {
		recentRankedMatches.filter { isWin($0) == false }.count
	}

	/// Ranked matches report their RR change locally, so the sign doubles as the result.
	private func isWin(_ match: CompetitiveUpdate) -> Bool? {
		guard match.isRanked else { return nil }
		if match.ratingEarned > 0 { return true }
		if match.ratingEarned < 0 { return false }
		return nil
	}

	private var masteryEntries: [MasteryEntry] {
		guard let contractsProgress else { return [] }
		return contractsProgress.contracts.contracts
			.compactMap { contract -> MasteryEntry? in
				guard let agentID = assets?.contracts[contract.id]?.content.agentID else { return nil }
				return MasteryEntry(contract: contract, agentID: agentID)
			}
			.sorted {
				($0.contract.levelReached, $0.contract.progression.totalEarned)
					> ($1.contract.levelReached, $1.contract.progression.totalEarned)
			}
			.prefix(3)
			.map { $0 }
	}

	private func xpForNextLevel(of contract: Contract) -> Int? {
		guard let levels = assets?.contracts[contract.id]?.content.chapters.flatMap({ $0.levels }) else {
			return nil
		}
		guard contract.levelReached < levels.count else { return nil }
		return levels[contract.levelReached].xp
	}

	// MARK: Formatting

	private func sectionHeader(_ title: LocalizedStringKey) -> some View {
		Text(title)
			.font(.system(.caption, design: .rounded).weight(.bold))
			.textCase(.uppercase)
			.foregroundColor(.secondary)
	}

	private func stat(_ title: LocalizedStringKey, _ value: String, detail: LocalizedStringKey? = nil) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title)
				.font(.system(size: 10, weight: .semibold, design: .rounded))
				.foregroundColor(.secondary)

			Text(verbatim: value)
				.font(.system(.subheadline, design: .rounded).weight(.bold))
				.monospacedDigit()

			if let detail {
				Text(detail)
					.font(.system(size: 10, design: .rounded))
					.foregroundColor(.secondary)
			}
		}
	}

	private func percent(_ part: Int, of total: Int) -> String {
		guard total > 0 else { return "—" }
		return "\(Int((Double(part) / Double(total) * 100).rounded()))%"
	}

	private struct MasteryEntry: Identifiable {
		var contract: Contract
		var agentID: Agent.ID

		var id: Contract.ID { contract.id }
	}
}
