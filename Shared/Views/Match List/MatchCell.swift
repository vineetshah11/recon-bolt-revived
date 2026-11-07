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
	
	@ScaledMetric private var iconSize = 52
	
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
				HStack(spacing: 12) {
					agentIcon(mapID: mapID)
					
					VStack(alignment: .leading, spacing: 3) {
						MapImage.LabelText(mapID: mapID)
							.font(.system(.headline, design: .rounded))
							.foregroundColor(.white)
							.lineLimit(1)
							.minimumScaleFactor(0.6)
						
						if let matchDetails {
							matchDetails.matchInfo.queueLabel
								.font(.system(.caption, design: .rounded).weight(.medium))
								.foregroundColor(ReconTheme.secondary)
								.lineLimit(1)
						}
						
						match.startTime.relativeText()
							.font(.system(.caption2, design: .rounded))
							.foregroundColor(ReconTheme.secondary.opacity(0.8))
					}
					
					Spacer(minLength: 8)
					
					trailingInfo
				}
				.matchCard(outcome)
			}
		}
	}
	
	@ViewBuilder
	private func agentIcon(mapID: MapID) -> some View {
		let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
		Group {
			if let agentID = myself?.agentID {
				AgentImage.icon(agentID)
					.scaledToFill()
			} else {
				MapImage.wideImage(mapID)
					.scaledToFill()
			}
		}
		.frame(width: iconSize, height: iconSize)
		.background(Color.white.opacity(0.05))
		.clipShape(shape)
		.overlay(shape.stroke(outcome.accent.opacity(0.6), lineWidth: 1.5))
	}
	
	private var trailingInfo: some View {
		HStack(spacing: 10) {
			VStack(alignment: .trailing, spacing: 6) {
				scorePill
				
				if match.isRanked {
					rrLabel
				}
			}
			
			if match.isRanked {
				ChangeRing(match: match)
					.frame(height: 40)
					.accentColor(outcome.accent)
			}
		}
	}
	
	@ViewBuilder
	private var scorePill: some View {
		if let matchDetails {
			ScoreSummaryView(
				teams: matchDetails.teams,
				ownTeamID: myself?.teamID
			)
			.font(.system(.subheadline, design: .rounded).weight(.bold))
			.monospacedDigit()
			.padding(.horizontal, 12)
			.padding(.vertical, 5)
			.background(outcome.gradient)
			.clipShape(Capsule())
			.transition(.slide)
		} else {
			Text("Swipe to fetch", comment: "Match List: shown in place of the score when details haven't been fetched")
				.font(.system(.caption2, design: .rounded))
				.foregroundColor(ReconTheme.secondary)
				.lineLimit(1)
		}
	}
	
	private var rrLabel: some View {
		VStack(alignment: .trailing, spacing: 1) {
			let change = match.ratingEarned
			Text(change > 0 ? "+\(change) RR" : change < 0 ? "\(change) RR" : "= RR")
				.font(.system(.caption, design: .rounded).weight(.semibold))
				.monospacedDigit()
				.foregroundColor(outcome.accent)
			
			if match.performanceBonus != 0 {
				Text("WP: +\(match.performanceBonus)", comment: "Match List: shown with a match's RR change when the player got a performance bonus")
					.foregroundColor(ReconTheme.victory)
					.font(.caption2.monospacedDigit())
			}
			if match.afkPenalty != 0 {
				Text("AFK: \(match.afkPenalty)", comment: "Match List: shown with a match's RR change when the player got an AFK Penalty")
					.foregroundColor(ReconTheme.defeat)
					.font(.caption2.monospacedDigit())
			}
		}
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

// MARK: - ChangeRing

private struct ChangeRing: View {
	let match: CompetitiveUpdate
	
	var body: some View {
		ZStack {
			let before = CGFloat(match.eloBeforeUpdate) / 100
			let after = CGFloat(match.eloAfterUpdate) / 100
			let lower = min(before, after)
			let higher = max(before, after)
			let zeroPoint = lower.rounded(.down)
			
			CircularProgressView {
				CircularProgressLayer(
					end: after - zeroPoint,
					color: .gray
				)
				CircularProgressLayer(
					start: lower - zeroPoint,
					end: higher - zeroPoint,
					shouldKnockOutSurroundings: true,
					color: .accentColor
				)
			} base: { Color.gray.opacity(0.2) }
			
			CompetitiveTierImage(tier: match.tierAfterUpdate, time: match.startTime)
				.padding(8)
			
			movementIndicator
				.background(Circle().fill(Color.white).blendMode(.destinationOut))
				.alignmentGuide(.top) { $0[VerticalAlignment.center] }
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		}
		.compositingGroup()
		.padding(2)
		.aspectRatio(contentMode: .fit)
	}
	
	@ViewBuilder
	private var movementIndicator: some View {
		Group {
			if match.tierAfterUpdate > match.tierBeforeUpdate {
				Image(systemName: "chevron.up.circle.fill")
					.foregroundColor(.green)
			} else if match.tierAfterUpdate < match.tierBeforeUpdate {
				Image(systemName: "chevron.down.circle.fill")
					.foregroundColor(.red)
			}
		}
		.font(.system(size: 12))
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
