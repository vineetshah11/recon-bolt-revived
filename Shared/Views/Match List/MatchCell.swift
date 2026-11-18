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
			.listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
			.swipeActions(edge: .leading) {
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
	
	@ScaledMetric private var avatarSize = 46
	
	private let bannerHeight: CGFloat = 132
	private let cornerRadius: CGFloat = 16
	
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
			banner(for: mapID)
			statsSection
		}
		.background(ReconTheme.background)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.stroke(ReconTheme.border, lineWidth: 1)
		)
	}
	
	// MARK: Banner
	
	private func banner(for mapID: MapID) -> some View {
		ZStack {
			MapImage.wideImage(mapID)
				.aspectRatio(contentMode: .fill)
			
			LinearGradient(
				colors: [.black.opacity(0.5), .black.opacity(0.1), .black.opacity(0.75)],
				startPoint: .top,
				endPoint: .bottom
			)
			
			score
		}
		.frame(maxWidth: .infinity)
		.frame(height: bannerHeight)
		.clipped()
		.overlay(alignment: .top) { bannerHeader(for: mapID) }
	}
	
	private func bannerHeader(for mapID: MapID) -> some View {
		HStack(alignment: .top, spacing: 8) {
			VStack(alignment: .leading, spacing: 2) {
				MapImage.LabelText(mapID: mapID)
					.font(.system(.headline, design: .rounded))
					.foregroundColor(.white)
					.lineLimit(1)
					.minimumScaleFactor(0.6)
				
				if let matchDetails {
					matchDetails.matchInfo.queueLabel
						.font(.system(.caption2, design: .rounded).weight(.medium))
						.foregroundColor(.white.opacity(0.75))
						.lineLimit(1)
				}
			}
			
			Spacer(minLength: 8)
			
			match.startTime.relativeText()
				.font(.system(.caption2, design: .rounded))
				.foregroundColor(.white.opacity(0.8))
				.lineLimit(1)
		}
		.shadow(color: .black.opacity(0.5), radius: 3, y: 1)
		.padding(12)
	}
	
	@ViewBuilder
	private var score: some View {
		if let matchDetails {
			if matchDetails.teams.count >= 2 {
				let ownTeam = matchDetails.teams.first(where: { $0.id == myself?.teamID })
				let enemyTeam = matchDetails.teams.first(where: { $0.id != myself?.teamID })
				
				HStack(spacing: 10) {
					Text(verbatim: "\(ownTeam?.pointCount ?? 0)")
						.foregroundColor(outcome.accent)
					
					Text(verbatim: "–")
						.font(.system(size: 26, weight: .bold, design: .rounded))
						.foregroundColor(.white.opacity(0.6))
					
					Text(verbatim: "\(enemyTeam?.pointCount ?? 0)")
						.foregroundColor(.white)
				}
				.font(.system(size: 34, weight: .heavy, design: .rounded))
				.monospacedDigit()
				.shadow(color: .black.opacity(0.45), radius: 6, y: 2)
			} else {
				ScoreSummaryView(teams: matchDetails.teams, ownTeamID: myself?.teamID)
					.font(.system(size: 28, weight: .bold, design: .rounded))
					.monospacedDigit()
					.shadow(color: .black.opacity(0.45), radius: 6, y: 2)
			}
		} else {
			Text("Swipe to fetch", comment: "Match List: shown in place of the score when details haven't been fetched")
				.font(.system(.footnote, design: .rounded).weight(.medium))
				.foregroundColor(.white.opacity(0.7))
		}
	}
	
	// MARK: Stats
	
	private var statsSection: some View {
		HStack(alignment: .center, spacing: 12) {
			agentAvatar
				.offset(y: -26)
			
			VStack(alignment: .leading, spacing: 3) {
				kdaRow
				rankRow
			}
			
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
	}
	
	private var agentAvatar: some View {
		Group {
			if let agentID = myself?.agentID {
				AgentImage.icon(agentID)
					.aspectRatio(contentMode: .fill)
			} else {
				Color.white.opacity(0.08)
					.overlay {
						Image(systemName: "person.fill")
							.foregroundColor(.white.opacity(0.3))
					}
			}
		}
		.frame(width: avatarSize, height: avatarSize)
		.clipShape(Circle())
		.padding(3)
		.background(ReconTheme.background, in: Circle())
		.overlay(
			Circle()
				.stroke(outcome.accent.opacity(0.8), lineWidth: 2)
				.padding(3)
		)
	}
	
	@ViewBuilder
	private var kdaRow: some View {
		if let stats = myself?.stats {
			HStack(spacing: 5) {
				Text(verbatim: "K \(stats.kills)")
					.foregroundColor(.white)
				Text(verbatim: "/")
					.foregroundColor(ReconTheme.secondary)
				Text(verbatim: "D \(stats.deaths)")
					.foregroundColor(.white)
				Text(verbatim: "/")
					.foregroundColor(ReconTheme.secondary)
				Text(verbatim: "A \(stats.assists)")
					.foregroundColor(.white)
			}
			.font(.system(.subheadline, design: .monospaced).weight(.medium))
			.monospacedDigit()
		}
	}
	
	@ViewBuilder
	private var rankRow: some View {
		if match.isRanked {
			HStack(spacing: 5) {
				CompetitiveTierImage(tier: match.tierAfterUpdate, time: match.startTime)
					.frame(width: 18, height: 18)
				
				if let tierName {
					Text(tierName)
						.font(.system(.caption, design: .rounded).weight(.medium))
						.foregroundColor(.white.opacity(0.85))
						.lineLimit(1)
					
					Text(verbatim: "·")
						.foregroundColor(ReconTheme.secondary)
				}
				
				rrLabel
				
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
			.font(.system(.caption, design: .rounded).weight(.semibold))
			.monospacedDigit()
			.foregroundColor(outcome.accent)
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
}
