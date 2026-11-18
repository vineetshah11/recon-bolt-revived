import SwiftUI
import SwiftUIMissingPieces
import HandyOperators
import ValorantAPI

// MARK: - Theme

enum ReconTheme {
	static let background = Color(red: 0x0F/255, green: 0x19/255, blue: 0x23/255) // #0F1923
	static let defeat     = Color(red: 0xFF/255, green: 0x46/255, blue: 0x55/255) // #FF4655
	static let victory    = Color(red: 0x16/255, green: 0xE5/255, blue: 0xB4/255) // #16E5B4
	static let victoryAlt = Color(red: 0x00/255, green: 0xF5/255, blue: 0xD4/255) // #00F5D4
	static let draw       = Color.gray
	static let border     = Color.white.opacity(0.08)
	static let secondary  = Color.white.opacity(0.55)
	
	enum Outcome {
		case win, loss, draw
		
		var accent: Color {
			switch self {
			case .win: return ReconTheme.victory
			case .loss: return ReconTheme.defeat
			case .draw: return ReconTheme.draw
			}
		}
		
		var title: LocalizedStringKey {
			switch self {
			case .win: return "Victory"
			case .loss: return "Defeat"
			case .draw: return "Draw"
			}
		}
		
		var gradient: LinearGradient {
			let colors: [Color]
			switch self {
			case .win: colors = [ReconTheme.victoryAlt, ReconTheme.victory]
			case .loss: colors = [ReconTheme.defeat, ReconTheme.defeat.opacity(0.7)]
			case .draw: colors = [ReconTheme.draw.opacity(0.8), ReconTheme.draw.opacity(0.5)]
			}
			return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
		}
	}
}

private struct MatchCardStyle: ViewModifier {
	let outcome: ReconTheme.Outcome
	
	func body(content: Content) -> some View {
		content
			.padding(12)
			.background(
				ZStack(alignment: .leading) {
					ReconTheme.background
					outcome.accent.frame(width: 3)
				}
			)
			.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.stroke(ReconTheme.border, lineWidth: 1)
			)
	}
}

private extension View {
	func matchCard(_ outcome: ReconTheme.Outcome) -> some View {
		modifier(MatchCardStyle(outcome: outcome))
	}
}

// MARK: - Cell

struct MatchCell: View {
	let match: CompetitiveUpdate
	let userID: User.ID
	let filter: MatchListFilter
	
	@LocalData var matchDetails: MatchDetails?
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.seasons) private var seasons
	
	var body: some View {
		matchInfo
			.listRowBackground(Color.clear)
			.listRowSeparator(.hidden)
			.listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
			.swipeActions(edge: .trailing) {
				if matchDetails == nil {
					AsyncButton {
						await load {
							try await $0.fetchMatchDetails(for: match.id)
						}
					} label: {
						Label(String(localized: "Fetch Details", comment: "Match List: accessibility label"), systemImage: "arrow.down")
							.labelStyle(.iconOnly)
					}
					.tint(.blue)
				}
			}
			.id(match.id)
			.withLocalData($matchDetails, id: match.id)
	}
	
	private let bannerHeight: CGFloat = 118
	private let bannerAgentWidth: CGFloat = 104
	private let cornerRadius: CGFloat = 16
	private let cardPadding: CGFloat = 14
	
	// MARK: Outcome
	
	private var myself: Player? {
		matchDetails?.players.firstElement(withID: userID)
	}
	
	private var outcome: ReconTheme.Outcome {
		if match.isRanked {
			if match.ratingEarned > 0 { return .win }
			if match.ratingEarned < 0 { return .loss }
		}
		if let matchDetails, let teamID = myself?.teamID,
		   let team = matchDetails.teams.first(where: { $0.id == teamID }) {
			return team.won ? .win : .loss
		}
		return .draw
	}
	
	private var isTeamMVP: Bool {
		guard
			let stats = myself?.stats,
			let teamID = myself?.teamID,
			let matchDetails
		else { return false }
		
		let team = matchDetails.players.filter { $0.teamID == teamID }
		guard team.count > 1 else { return false }
		return stats.score == team.compactMap { $0.stats?.score }.max()
	}
	
	private var platformIcon: String? {
		switch myself?.platformInfo.type.uppercased() {
		case "PC": return "desktopcomputer"
		case nil: return nil
		default: return "gamecontroller.fill"
		}
	}
	
	// MARK: Content
	
	@ViewBuilder
	private var matchInfo: some View {
		let matchesFilter = filter.accepts(match, details: matchDetails)
		
		if match.mapID == nil {
			dodgedRow
		} else if !matchesFilter {
			filteredOutRow
		} else if let mapID = match.mapID {
			TransparentNavigationLink {
				MatchDetailsContainer(matchID: match.id, userID: userID)
			} label: {
				card(for: mapID)
			}
		}
	}
	
	private func card(for mapID: MapID) -> some View {
		VStack(spacing: 0) {
			if matchDetails != nil {
				header
				banner(for: mapID)
				statsFooter
			} else {
				notDownloadedHeader
				placeholderBanner(for: mapID)
				downloadHint
			}
		}
		.background(ReconTheme.background)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.stroke(ReconTheme.border, lineWidth: 1)
		)
	}
	
	// MARK: Header
	
	private var header: some View {
		HStack(alignment: .center, spacing: 10) {
			CompetitiveTierImage(tier: match.tierAfterUpdate, time: match.startTime)
				.frame(width: 30, height: 30)
			
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					if let platformIcon {
						Image(systemName: platformIcon)
							.font(.system(size: 13, weight: .semibold))
							.foregroundColor(.white.opacity(0.85))
					}
					
					if let matchDetails {
						matchDetails.matchInfo.queueLabel
							.font(.system(.headline, design: .rounded))
							.foregroundColor(.white)
							.lineLimit(1)
					}
				}
				
				timestamp
			}
			
			Spacer(minLength: 8)
			
			rankInfo
		}
		.padding(.horizontal, cardPadding)
		.padding(.vertical, 12)
	}
	
	private var notDownloadedHeader: some View {
		HStack(alignment: .center, spacing: 10) {
			VStack(alignment: .leading, spacing: 3) {
				Text("Not Downloaded", comment: "Match List: match details have not been fetched yet")
					.font(.system(.headline, design: .rounded))
					.foregroundColor(.white)
				timestamp
			}
			
			Spacer(minLength: 8)
			
			rankInfo
		}
		.padding(.horizontal, cardPadding)
		.padding(.vertical, 12)
	}
	
	private var timestamp: some View {
		HStack(spacing: 5) {
			match.startTime.listTimestamp()
			
			if let matchDetails,
			   let length = Self.durationFormatter.string(from: matchDetails.matchInfo.gameLength) {
				Text(verbatim: "·")
				Text(verbatim: length)
			}
		}
		.font(.system(.caption, design: .rounded))
		.foregroundColor(ReconTheme.secondary)
		.lineLimit(1)
	}
	
	private static let durationFormatter = DateComponentsFormatter() <- {
		$0.unitsStyle = .abbreviated
		$0.allowedUnits = [.minute]
	}
	
	@ViewBuilder
	private var rankInfo: some View {
		if match.isRanked {
			VStack(alignment: .trailing, spacing: 2) {
				rrLabel
				
				if let tierName {
					Text(tierName)
						.font(.system(.caption2, design: .rounded).weight(.medium))
						.foregroundColor(ReconTheme.secondary)
						.lineLimit(1)
				}
				
				if match.performanceBonus != 0 {
					Text("WP: +\(match.performanceBonus)", comment: "Match List: shown with a match's RR change when the player got a performance bonus")
						.font(.system(.caption2, design: .rounded).weight(.medium))
						.monospacedDigit()
						.foregroundColor(ReconTheme.victory)
				}
				if match.afkPenalty != 0 {
					Text("AFK: \(match.afkPenalty)", comment: "Match List: shown with a match's RR change when the player got an AFK Penalty")
						.font(.system(.caption2, design: .rounded).weight(.medium))
						.monospacedDigit()
						.foregroundColor(ReconTheme.defeat)
				}
			}
		}
	}
	
	private var tierName: String? {
		seasons?.currentTierInfo(number: match.tierAfterUpdate, at: match.startTime)?.name
	}
	
	private var rrLabel: some View {
		let change = match.ratingEarned
		return Text(change > 0 ? "+\(change) RR" : change < 0 ? "\(change) RR" : "= RR")
			.font(.system(.caption, design: .rounded).weight(.bold))
			.monospacedDigit()
			.foregroundColor(outcome.accent)
			.padding(.horizontal, 8)
			.padding(.vertical, 3)
			.background(Capsule().fill(outcome.accent.opacity(0.15)))
			.overlay(Capsule().stroke(outcome.accent.opacity(0.35), lineWidth: 1))
	}
	
	// MARK: Banner
	
	private func banner(for mapID: MapID) -> some View {
		ZStack(alignment: .topTrailing) {
			MapImage.wideImage(mapID)
				.aspectRatio(contentMode: .fill)
			
			LinearGradient(
				colors: [.black.opacity(0.65), .black.opacity(0.2), .clear],
				startPoint: .leading,
				endPoint: .trailing
			)
			
			LinearGradient(
				colors: [.clear, .clear, .black.opacity(0.35)],
				startPoint: .top,
				endPoint: .bottom
			)
			
			HStack(spacing: 4) {
				if let agentID = myself?.agentID {
					agentArt(agentID)
					
					VStack(alignment: .leading, spacing: 6) {
						AgentLabel(agent: agentID)
							.font(.system(.title3, design: .rounded).weight(.bold))
							.foregroundColor(.white)
							.lineLimit(1)
						
						mapChip(for: mapID)
					}
					.layoutPriority(1)
				} else {
					mapChip(for: mapID)
						.padding(.leading, cardPadding)
				}
				
				Spacer(minLength: 0)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
			
			resultPill
				.padding(10)
		}
		.frame(maxWidth: .infinity)
		.frame(height: bannerHeight)
		.clipped()
		.overlay(alignment: .bottom) {
			Rectangle()
				.fill(ReconTheme.border)
				.frame(height: 1)
		}
	}
	
	private func agentArt(_ agentID: Agent.ID) -> some View {
		AgentImage.killfeedPortrait(agentID)
			.aspectRatio(contentMode: .fill)
			.frame(width: bannerAgentWidth, height: bannerHeight)
			.clipped()
			.mask(
				LinearGradient(
					colors: [.black, .black, .clear],
					startPoint: .leading,
					endPoint: .trailing
				)
			)
	}
	
	private func mapChip(for mapID: MapID) -> some View {
		HStack(spacing: 5) {
			MapImage.LabelText(mapID: mapID)
			
			if isTeamMVP {
				Text(verbatim: "|")
					.foregroundColor(.white.opacity(0.6))
				Text("Team MVP", comment: "Match List: player had the highest combat score on their team")
					.fontWeight(.bold)
			}
		}
		.font(.system(.caption2, design: .rounded).weight(.semibold))
		.foregroundColor(.white)
		.lineLimit(1)
		.padding(.horizontal, 9)
		.padding(.vertical, 4)
		.background(Capsule().fill(Color.black.opacity(0.35)))
	}
	
	private var resultPill: some View {
		Text(outcome.title)
			.font(.system(.caption2, design: .rounded).weight(.heavy))
			.textCase(.uppercase)
			.foregroundColor(.white)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background(Capsule().fill(outcome.accent))
			.shadow(color: .black.opacity(0.3), radius: 4, y: 1)
	}
	
	private func placeholderBanner(for mapID: MapID) -> some View {
		ZStack {
			MapImage.wideImage(mapID)
				.aspectRatio(contentMode: .fill)
			
			Color.black.opacity(0.35)
			
			MapImage.LabelText(mapID: mapID)
				.font(.system(.title3, design: .rounded).weight(.semibold))
				.foregroundColor(.white)
				.padding(.horizontal, 18)
				.padding(.vertical, 8)
				.background(Capsule().fill(Color.black.opacity(0.4)))
				.overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
		}
		.frame(maxWidth: .infinity)
		.frame(height: bannerHeight)
		.clipped()
	}
	
	// MARK: Footer
	
	private var statsFooter: some View {
		HStack(alignment: .center, spacing: 12) {
			if let stats = myself?.stats {
				footerStat(label: "K / D / A", value: "\(stats.kills) / \(stats.deaths) / \(stats.assists)")
				
				footerSeparator
				
				footerStat(label: "ACS", value: "\(acs(for: stats))")
					.accessibilityLabel(Text("Average combat score", comment: "Match List: ACS stat"))
				
				if let matchDetails, !matchDetails.teams.isEmpty {
					footerSeparator
					footerScore(for: matchDetails)
				}
			} else {
				Spacer(minLength: 0)
			}
			
			Spacer(minLength: 4)
			
			Image(systemName: "chevron.right")
				.font(.system(.caption, design: .rounded).weight(.semibold))
				.foregroundColor(ReconTheme.secondary)
		}
		.padding(.horizontal, cardPadding)
		.padding(.vertical, 11)
	}
	
	private func footerStat(label: LocalizedStringKey, value: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(label)
				.font(.system(size: 9, weight: .semibold, design: .rounded))
				.foregroundColor(ReconTheme.secondary)
			
			Text(verbatim: value)
				.font(.system(.subheadline, design: .rounded).weight(.semibold))
				.monospacedDigit()
				.foregroundColor(.white)
				.lineLimit(1)
		}
	}
	
	private var footerSeparator: some View {
		Rectangle()
			.fill(ReconTheme.border)
			.frame(width: 1, height: 24)
	}
	
	private func acs(for stats: Player.Stats) -> Int {
		stats.roundsPlayed > 0 ? stats.score / stats.roundsPlayed : 0
	}
	
	/// Score as seen from the player's own team, or a multi-team summary for nonstandard modes.
	@ViewBuilder
	private func footerScore(for matchDetails: MatchDetails) -> some View {
		if matchDetails.teams.count == 2 {
			let ownTeam = matchDetails.teams.first(where: { $0.id == myself?.teamID })
			let enemyTeam = matchDetails.teams.first(where: { $0.id != myself?.teamID })
			
			footerStat(
				label: "Score",
				value: "\(ownTeam?.pointCount ?? 0) – \(enemyTeam?.pointCount ?? 0)"
			)
		} else {
			VStack(alignment: .leading, spacing: 2) {
				Text("Score")
					.font(.system(size: 9, weight: .semibold, design: .rounded))
					.foregroundColor(ReconTheme.secondary)
				
				ScoreSummaryView(teams: matchDetails.teams, ownTeamID: myself?.teamID)
					.font(.system(.subheadline, design: .rounded).weight(.semibold))
					.monospacedDigit()
			}
		}
	}
	
	private var downloadHint: some View {
		HStack {
			Text("Swipe to the left or tap to download.", comment: "Match List: match details have not been fetched yet")
				.font(.system(.footnote, design: .rounded))
				.foregroundColor(ReconTheme.secondary)
			
			Spacer(minLength: 4)
			
			Image(systemName: "chevron.right")
				.font(.system(.caption, design: .rounded).weight(.semibold))
				.foregroundColor(ReconTheme.secondary)
		}
		.padding(.horizontal, cardPadding)
		.padding(.vertical, 12)
	}
	
	// MARK: Secondary states
	
	private var dodgedRow: some View {
		HStack {
			Text("Match Dodged", comment: "Match List: shown when a match didn't get past Agent Select (because someone dodged/left)")
				.font(.system(.subheadline, design: .rounded).weight(.medium))
				.foregroundColor(ReconTheme.secondary)
			Spacer()
			match.startTime.relativeText()
				.font(.system(.caption2, design: .rounded))
				.foregroundColor(ReconTheme.secondary.opacity(0.8))
		}
		.matchCard(.draw)
	}
	
	/// Compact row for matches hidden by the current filter.
	private var filteredOutRow: some View {
		TransparentNavigationLink {
			MatchDetailsContainer(matchID: match.id, userID: userID)
		} label: {
			HStack {
				match.startTime.relativeText()
				Spacer()
				if let matchDetails {
					matchDetails.matchInfo.queueLabel
				} else {
					Text("Unfetched", comment: "Shown when a match does not match the filter and its details have not been fetched.")
				}
			}
			.font(.system(.caption, design: .rounded))
			.foregroundColor(ReconTheme.secondary)
			.matchCard(.draw)
		}
	}
}

extension MatchCell {
	init(match: CompetitiveUpdate, userID: User.ID, filter: MatchListFilter) {
		self.init(
			match: match, userID: userID, filter: filter,
			matchDetails: .init(id: match.id)
		)
	}
}

// MARK: - Relative Date Formatting

extension Date {
	private static let startDateFormatter = DateFormatter() <- {
		$0.dateStyle = .short
	}
	private static let startTimeFormatter = DateFormatter() <- {
		$0.timeStyle = .short
	}
	private static let relativeStartTimeFormatter = DateComponentsFormatter() <- {
		$0.unitsStyle = .abbreviated
		$0.maximumUnitCount = 2
		$0.allowedUnits = [.day, .hour, .minute]
	}
	
	func relativeText() -> some View {
		HStack {
			let relativeCutoff = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
			if self > relativeCutoff {
				let formatter = Self.relativeStartTimeFormatter
				Text("\(formatter.string(from: self, to: .now)!) ago", comment: "Used for matches less than a day ago.")
					.foregroundStyle(.secondary)
			} else {
				Text(self, formatter: Self.startDateFormatter)
				Text(self, formatter: Self.startTimeFormatter)
					.foregroundStyle(.secondary)
			}
		}
	}
	
	/// Absolute date and time, e.g. “17/11/26 · 1:40 AM”.
	func listTimestamp() -> Text {
		let date = Text(self, formatter: Self.startDateFormatter)
		let separator = Text(verbatim: " · ")
		let time = Text(self, formatter: Self.startTimeFormatter)
		return date + separator + time
	}
}
