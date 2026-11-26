import SwiftUI
import SwiftUIMissingPieces
import HandyOperators
import ValorantAPI

struct MatchCell: View {
	let match: CompetitiveUpdate
	let userID: User.ID
	let filter: MatchListFilter
	var inList: Bool = true
	var isCompact: Bool = false
	
	@LocalData var matchDetails: MatchDetails?
	@AppStorage("MatchList.autoDownload") private var autoDownloadMatches = true
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	
	var body: some View {
		matchInfo
			.if(inList) { view in
				view
					.listRowInsets(EdgeInsets(top: isCompact ? 3 : 6, leading: 16, bottom: isCompact ? 3 : 6, trailing: 16))
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
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
			}
			.if(!inList) { view in
				view.contextMenu {
					if matchDetails == nil {
						AsyncButton {
							await load {
								try await $0.fetchMatchDetails(for: match.id)
							}
						} label: {
							Label(String(localized: "Fetch Details", comment: "Match List: accessibility label"), systemImage: "arrow.down")
						}
					}
				}
			}
			.id(match.id)
			.withLocalData($matchDetails, id: match.id)
			.task(id: match.id) {
				guard autoDownloadMatches, matchDetails == nil, match.mapID != nil else { return }
				guard await !LocalDataProvider.shared.matchDetailsManager.hasCachedFile(for: match.id) else { return }
				await load { client in
					_ = try? await client.fetchMatchDetails(for: match.id)
				}
			}
	}
	
	@ViewBuilder
	private var matchInfo: some View {
		let matchesFilter = filter.accepts(match, details: matchDetails)
		
		VStack(spacing: 0) {
			if !matchesFilter {
				HStack {
					match.startTime.relativeText()
					Spacer()
					if let matchDetails {
						matchDetails.matchInfo.queueLabel
					} else {
						Text("Unfetched", comment: "Shown when a match does not match the filter and its details have not been fetched.")
					}
				}
				.font(.caption)
				.padding(12)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
			} else if let mapID = match.mapID {
				let card = VStack(spacing: 0) {
					cardHeader
					cardBanner(mapID: mapID)
					cardFooter
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: isCompact ? 11 : 16, style: .continuous))
				.clipped()
				
				if inList {
					card
						.background {
							TransparentNavigationLink {
								MatchDetailsContainer(matchID: match.id, userID: userID)
							} label: {
								EmptyView()
							}
							.opacity(0)
						}
				} else {
					TransparentNavigationLink {
						MatchDetailsContainer(matchID: match.id, userID: userID)
					} label: {
						card
					}
					.buttonStyle(.plain)
				}
			} else {
				VStack(spacing: 6) {
					HStack {
						Text("Match Dodged", comment: "Match List: shown when a match didn't get past Agent Select (because someone dodged/left)")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.secondary)
						Spacer()
						if match.isRanked {
							changeInfo
						}
					}
					HStack {
						match.startTime.relativeText()
							.font(.caption)
						Spacer()
					}
				}
				.padding(12)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
			}
		}
	}
	
	private var cardHeader: some View {
		HStack(spacing: 10) {
			Group {
				if let matchDetails {
					GameModeImage(id: matchDetails.matchInfo.modeID)
						.frame(width: 24, height: 24)
						.foregroundStyle(.secondary)
				} else {
					Image(systemName: match.isRanked ? "shield.lefthalf.filled" : "gamecontroller.fill")
						.font(.title3)
						.foregroundStyle(.secondary)
						.frame(width: 24, height: 24)
				}
			}
			
			VStack(alignment: .leading, spacing: 2) {
				if let matchDetails {
					matchDetails.matchInfo.queueLabel
						.font(.subheadline.weight(.bold))
						.lineLimit(1)
				} else {
					Text(match.isRanked ? "Competitive" : "Match")
						.font(.subheadline.weight(.bold))
				}
				Text(match.startTime.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits).hour().minute()))
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.secondary)
			}
			
			Spacer()
			
			if match.isRanked {
				changeInfo
			}
		}
		.padding(.horizontal, isCompact ? 10 : 12)
		.padding(.vertical, isCompact ? 6 : 10)
	}
	
	private func cardBanner(mapID: MapID) -> some View {
		let bannerHeight: CGFloat = isCompact ? 54 : 74
		let myself = matchDetails?.players.firstElement(withID: userID)
		let agentID = myself?.agentID
		let isOVariant = (myself != nil && matchDetails != nil) ? Team.ID.isGauntletOVariant(
			for: myself!.id,
			teamID: myself!.teamID,
			in: matchDetails!.players
		) : true
		let mvpTitle = mvpBadgeTitle(for: myself)
		
		return ZStack(alignment: .leading) {
			MapImage.wideImage(mapID)
				.scaledToFill()
				.frame(maxWidth: .infinity, minHeight: bannerHeight, maxHeight: bannerHeight)
				.clipped()
				.overlay {
					LinearGradient(
						colors: [Color.black.opacity(0.68), Color.black.opacity(0.32)],
						startPoint: .leading,
						endPoint: .trailing
					)
				}
			
			HStack(spacing: isCompact ? 10 : 12) {
				if let myself, let agentID {
					// fills the whole banner height, flush with the card's leading edge
					AgentImage.icon(agentID, teamID: myself.teamID, isOVariant: isOVariant)
						.scaledToFill()
						.frame(width: bannerHeight, height: bannerHeight)
						.clipped()
				}
				
				VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
					if let agentID {
						AgentLabel(agent: agentID)
							.font(isCompact ? .subheadline.bold() : .headline.bold())
							.foregroundStyle(.white)
							.shadow(color: .black.opacity(0.6), radius: 2, y: 1)
					} else {
						MapImage.LabelText(mapID: mapID)
							.font(isCompact ? .subheadline.bold() : .headline.bold())
							.foregroundStyle(.white)
					}
					
					HStack(spacing: 6) {
						Text(assets?.maps[mapID]?.displayName ?? "Map")
							.font(.caption.weight(.medium))
							.foregroundStyle(.white.opacity(0.95))
							.padding(.horizontal, 8)
							.padding(.vertical, 2)
							.background(Color.black.opacity(0.45), in: Capsule())
						
						if let mvpTitle {
							Text(mvpTitle)
								.font(.caption2.bold())
								.foregroundStyle(mvpTitle == "Match MVP" ? .black : .white)
								.padding(.horizontal, 8)
								.padding(.vertical, 2)
								.background(
									mvpTitle == "Match MVP" ? Color.yellow : Color.black.opacity(0.55),
									in: Capsule()
								)
						}
					}
				}
				
				Spacer()
				
				if let matchDetails, let myself {
					outcomePill(matchDetails: matchDetails, myself: myself)
				}
			}
			.padding(.leading, agentID != nil ? 0 : 12)
			.padding(.trailing, 10)
		}
		.frame(height: bannerHeight)
		.clipped()
	}
	
	private var cardFooter: some View {
		HStack {
			if let matchDetails, let myself = matchDetails.players.firstElement(withID: userID) {
				HStack(spacing: 6) {
					Image(systemName: "scope")
						.font(.caption)
						.foregroundStyle(.secondary)
					KDASummaryView(player: myself)
						.font(.subheadline.monospacedDigit())
				}
				
				Spacer()
				
				if let stats = myself.stats, stats.roundsPlayed > 0 {
					let acs = stats.score / stats.roundsPlayed
					HStack(spacing: 5) {
						Image(systemName: "chart.bar.fill")
							.font(.caption2)
							.foregroundStyle(.secondary)
						Text("\(acs)")
							.font(.subheadline.monospacedDigit())
					}
				}
				
				Spacer()
				
				HStack(spacing: 6) {
					Image(systemName: "flag.checkered")
						.font(.caption2)
						.foregroundStyle(.secondary)
					ScoreSummaryView(
						teams: matchDetails.teams,
						players: matchDetails.players,
						ownTeamID: myself.teamID
					)
					.font(.subheadline.weight(.semibold))
					Image(systemName: "chevron.right")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(.secondary)
				}
			} else {
				Text("Open or swipe to fetch details.")
					.font(.caption)
					.foregroundStyle(.tertiary)
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, isCompact ? 10 : 12)
		.padding(.vertical, isCompact ? 6 : 10)
	}
	
	@ViewBuilder
	private func outcomePill(matchDetails: MatchDetails, myself: Player) -> some View {
		let winner = matchDetails.teams.first(where: \.won)
		let title: String = {
			guard let winner else { return "DRAW" }
			return winner.id == myself.teamID ? "VICTORY" : "DEFEAT"
		}()
		let bg: Color = {
			guard let winner else { return .gray }
			return winner.id == myself.teamID ? .green : Color.valorantRed
		}()
		Text(title)
			.font(.caption2.weight(.heavy))
			.foregroundStyle(.white)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background(bg, in: Capsule())
	}
	
	private func mvpBadgeTitle(for myself: Player?) -> String? {
		guard let matchDetails, let myself, let myStats = myself.stats, myStats.roundsPlayed > 0 else {
			return nil
		}
		let myACS = Double(myStats.score) / Double(myStats.roundsPlayed)
		let maxAll = matchDetails.players.compactMap { p -> Double? in
			guard let s = p.stats, s.roundsPlayed > 0 else { return nil }
			return Double(s.score) / Double(s.roundsPlayed)
		}.max() ?? 0
		if myACS >= maxAll - 0.01 {
			return "Match MVP"
		}
		let teamMax = matchDetails.players
			.filter { $0.teamID == myself.teamID }
			.compactMap { p -> Double? in
				guard let s = p.stats, s.roundsPlayed > 0 else { return nil }
				return Double(s.score) / Double(s.roundsPlayed)
			}.max() ?? 0
		if myACS >= teamMax - 0.01 {
			return "Team MVP"
		}
		return nil
	}
	
	private var changeInfo: some View {
		HStack(spacing: 8) {
			VStack(alignment: .trailing, spacing: 2) {
				HStack(spacing: 4) {
					let eloChange = match.ratingEarned
					Text(eloChange > 0 ? "+\(eloChange)" : eloChange < 0 ? "\(eloChange)" : "=")
						.foregroundStyle(changeColor)
					if match.performanceBonus != 0 {
						Text("(+\(match.performanceBonus))")
							.foregroundStyle(.yellow)
					}
					if match.afkPenalty != 0 {
						Text("(\(match.afkPenalty))")
							.foregroundStyle(.red)
					}
				}
				Text("\(match.tierProgressAfterUpdate)")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			.font(.caption.bold().monospacedDigit())
			
			ChangeRing(match: match)
				.frame(height: 38)
		}
	}
	
	private var changeColor: Color {
		match.ratingEarned > 0 ? .green : match.ratingEarned < 0 ? .red : .gray
	}
}

extension MatchCell {
	init(match: CompetitiveUpdate, userID: User.ID, filter: MatchListFilter, inList: Bool = true, isCompact: Bool = false) {
		self.init(
			match: match, userID: userID, filter: filter,
			inList: inList,
			isCompact: isCompact,
			matchDetails: .init(id: match.id)
		)
	}
}

private struct ChangeRing: View {
	let match: CompetitiveUpdate
	
	private var changeColor: Color {
		match.ratingEarned > 0 ? .green : match.ratingEarned < 0 ? .red : .gray
	}
	
	var body: some View {
		ZStack {
			// this is technically wrong for immortal+, but it's not a problem
			let before = CGFloat(match.eloBeforeUpdate) / 100
			let after = CGFloat(match.eloAfterUpdate) / 100
			let bonus = CGFloat(max(0, match.performanceBonus)) / 100
			let lower = min(before, after)
			let zeroPoint = lower.rounded(.down)
			
			CircularProgressView {
				CircularProgressLayer(
					end: after - zeroPoint,
					color: .gray
				)
				if after > before {
					if bonus > 0 {
						let bonusStart = max(before, after - bonus)
						if bonusStart > before {
							CircularProgressLayer(
								start: before - zeroPoint,
								end: bonusStart - zeroPoint,
								shouldKnockOutSurroundings: true,
								color: .green
							)
						}
						CircularProgressLayer(
							start: bonusStart - zeroPoint,
							end: after - zeroPoint,
							shouldKnockOutSurroundings: true,
							color: .yellow
						)
					} else {
						CircularProgressLayer(
							start: before - zeroPoint,
							end: after - zeroPoint,
							shouldKnockOutSurroundings: true,
							color: .green
						)
					}
				} else if after < before {
					CircularProgressLayer(
						start: after - zeroPoint,
						end: before - zeroPoint,
						shouldKnockOutSurroundings: true,
						color: .red
					)
					if bonus > 0 {
						let savedStart = max(zeroPoint, after - bonus)
						if after > savedStart {
							CircularProgressLayer(
								start: savedStart - zeroPoint,
								end: after - zeroPoint,
								shouldKnockOutSurroundings: true,
								color: .yellow
							)
						}
					}
				} else if bonus > 0 {
					let bonusStart = max(zeroPoint, after - bonus)
					if after > bonusStart {
						CircularProgressLayer(
							start: bonusStart - zeroPoint,
							end: after - zeroPoint,
							shouldKnockOutSurroundings: true,
							color: .yellow
						)
					}
				} else {
					CircularProgressLayer(
						start: lower - zeroPoint,
						end: after - zeroPoint,
						shouldKnockOutSurroundings: true,
						color: changeColor
					)
				}
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
				// promotion
				Image(systemName: "chevron.up.circle.fill")
					.foregroundColor(.green)
			} else if match.tierAfterUpdate < match.tierBeforeUpdate {
				// demotion
				Image(systemName: "chevron.down.circle.fill")
					.foregroundColor(.red)
			}
		}
		.font(.system(size: 12))
	}
}

extension Date {
	private static let startDateFormatter = DateFormatter() <- {
		$0.dateStyle = .short
	}
	private static let startTimeFormatter = DateFormatter() <- {
		$0.timeStyle = .short
	}
	private static let relativeStartTimeFormatter = DateComponentsFormatter() <- {
		// DateComponentsFormatter gives us more control than RelativeDateTimeFormatter
		$0.unitsStyle = .abbreviated
		$0.maximumUnitCount = 2
		$0.allowedUnits = [.day, .hour, .minute]
	}
	
	/// uses relative formatting for times less than a day ago
	func relativeText() -> some View {
		HStack {
			let relativeCutoff = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
			if self > relativeCutoff {
				let formatter = Self.relativeStartTimeFormatter
				Text("\(formatter.string(from: self, to: .now)!) ago", comment: "Used for matches less than a day ago. %@ is replaced by the number of hours/minutes, e.g. '3h ago'.")
					.foregroundStyle(.secondary)
			} else {
				Text(self, formatter: Self.startDateFormatter)
				Text(self, formatter: Self.startTimeFormatter)
					.foregroundStyle(.secondary)
			}
		}
	}
}

#if DEBUG
struct MatchCell_Previews: PreviewProvider {
	static let demotion = CompetitiveUpdate.example(tierChange: (6, 5), tierProgressChange: (10, 80), index: 0)
		<- { $0.afkPenalty = -7 }
	static let decrease = CompetitiveUpdate.example(tierChange: (8, 8), tierProgressChange: (60, 40), index: 1)
	static let unchanged = CompetitiveUpdate.example(tierChange: (12, 12), tierProgressChange: (50, 50), index: 2)
	static let increase = CompetitiveUpdate.example(tierChange: (8, 8), tierProgressChange: (40, 60), index: 3)
	static let promotion = CompetitiveUpdate.example(tierChange: (20, 21), tierProgressChange: (80, 10), index: 4) <- {
		$0.afkPenalty = -3
		$0.performanceBonus = 9
	}
	
	static let unranked = CompetitiveUpdate.example(tierChange: (0, 0), tierProgressChange: (0, 0), index: 5)
	
	static let jump = CompetitiveUpdate.example(tierChange: (11, 13), tierProgressChange: (90, 30), index: 6)
		<- { $0.performanceBonus = 14 }
	
	static let withinImmortal = CompetitiveUpdate.example(tierChange: (21, 21), tierProgressChange: (290, 310))
	static let promotionToRadiant = CompetitiveUpdate.example(tierChange: (21, 24), tierProgressChange: (379, 400), ratingEarned: 21)
	
	static let dodge = CompetitiveUpdate(
		id: .init(),
		mapID: nil,
		startTime: .init(timeIntervalSinceNow: -234567),
		tierBeforeUpdate: 15,
		tierAfterUpdate: 15,
		tierProgressBeforeUpdate: 44,
		tierProgressAfterUpdate: 41,
		ratingEarned: -3
	)
	
	static let allExamples = [
		demotion, decrease, unchanged, increase, promotion,
		dodge, unranked, jump, withinImmortal, promotionToRadiant,
	]
	
	static var previews: some View {
		List {
			MatchCell(
				match: allExamples.first! <- { $0.id = PreviewData.singleMatch.id },
				userID: PreviewData.userID,
				filter: .init(),
				matchDetails: .init(preview: PreviewData.singleMatch)
			)
			
			ForEach(allExamples.dropFirst()) {
				MatchCell(match: $0, userID: PreviewData.userID, filter: .init())
			}
		}
		.withToolbar(allowLargeTitles: false) // otherwise NavigationLink grays out accent colors
	}
}
#endif
