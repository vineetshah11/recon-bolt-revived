import SwiftUI
import ValorantAPI

struct ScoreboardView: View {
	let data: MatchViewData
	@Binding var highlight: PlayerHighlightInfo
	
	@State private var width = 0.0
	@Environment(\.valorantLoad) private var load
	
	var body: some View {
		VStack {
			ScrollView(.horizontal, showsIndicators: false) {
				VStack(spacing: ScoreboardRowView.padding) {
					if data.isMultiTeam {
						multiTeamScoreboard
					} else {
						let sorted = data.details.players.sorted { $0.score > $1.score }
						ForEach(sorted) { player in
							ScoreboardRowView(player: player, data: data, highlight: $highlight)
						}
					}
				}
				.padding(.horizontal)
				.frame(minWidth: width)
			}
			.measured { width = $0.width }
			
			AsyncButton(action: fetchRanks) {
				Text("Update Ranks", comment: "Match Details: button")
			}
			.buttonStyle(.bordered)
		}
		.task(id: data.details.id) {
			let missingIDs = data.details.players
				.filter(\.gameName.isEmpty)
				.map(\.id)
			guard !missingIDs.isEmpty else { return }
			await load {
				try await $0.fetchUsers(for: missingIDs)
			}
		}
	}
	
	@ViewBuilder
	private var multiTeamScoreboard: some View {
		let playersByTeam = Dictionary(grouping: data.details.players, by: \.teamID)
		let hasGroupedTeams = playersByTeam.values.contains { $0.count > 1 }
		
		ForEach(Array(data.rankedTeams.enumerated()), id: \.element.id) { index, team in
			let teamPlayers = (playersByTeam[team.id] ?? []).sorted { $0.score > $1.score }
			let placementRank = team.placement ?? (index + 1)
			let placement = PlacementFormatter.ordinal(placementRank)
			let teamColor = data.relativeColor(of: team.id) ?? .valorantRed
			
			if hasGroupedTeams {
				VStack(alignment: .leading, spacing: ScoreboardRowView.padding) {
					HStack(spacing: 8) {
						Text(placement)
							.font(.subheadline.weight(.bold))
							.foregroundColor(teamColor)
						
						if let mascotAsset = team.id.gauntletMascotAssetName {
							Image.bundledAsset(mascotAsset)
								.resizable()
								.scaledToFit()
								.frame(width: 22, height: 22)
						}
						
						if let teamName = team.id.gauntletDisplayName {
							Text(verbatim: teamName)
								.font(.subheadline.weight(.semibold))
								.foregroundColor(teamColor)
						}
						
						if team.id == data.myself?.teamID {
							Text("Your Team", comment: "Scoreboard: badge on user's team in multi-team modes")
								.font(.caption.weight(.semibold))
								.foregroundColor(.valorantSelf)
						}
						
						Spacer()
						
						if team.pointCount > 0 {
							Text("\(team.pointCount) pts")
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
						} else if let health = team.health, health.starting > 0 {
							Text("\(health.ending)/\(health.starting) HP")
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
						}
					}
					.padding(.top, index == 0 ? 0 : 8)
					
					ForEach(teamPlayers) { player in
						ScoreboardRowView(player: player, data: data, highlight: $highlight)
					}
				}
			} else {
				ForEach(teamPlayers) { player in
					ScoreboardRowView(
						player: player,
						data: data,
						placement: placement,
						highlight: $highlight
					)
				}
			}
		}
	}
	
	private func fetchRanks() async {
		await load {
			for playerID in data.players.keys {
				try await $0.fetchCareerSummary(for: playerID)
			}
		}
	}
}

struct ScoreboardRowView: View {
	static let padding = 6.0
	private static let partyLetters = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
		.map { String(UnicodeScalar($0)!) }
	
	let player: Player
	let data: MatchViewData
	var placement: String? = nil
	@Binding var highlight: PlayerHighlightInfo
	
	@LocalData var playerUser: User?
	@LocalData var summary: CareerSummary?
	
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	
	var body: some View {
		let divider = Rectangle()
			.frame(width: 1)
			.blendMode(.destinationOut)
		let relativeColor = data.relativeColor(of: player)
		let rowTeamColor = (data.isMultiTeam ? data.relativeColor(of: player.teamID) : nil) ?? relativeColor
		
		HStack(spacing: Self.padding) {
			if let placement {
				Text(placement)
					.font(.caption.weight(.bold))
					.monospacedDigit()
					.foregroundColor(relativeColor)
					.frame(minWidth: 32)
			}
			
			ZStack {
				if let agentID = player.agentID {
					AgentImage.icon(
						agentID,
						outlineRadius: 1,
						teamID: player.teamID,
						isOVariant: data.isGauntletOVariant(for: player)
					)
				} else {
					Image(systemName: "eye")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
			.aspectRatio(1, contentMode: .fit)
			.background(rowTeamColor.opacity(0.5))
			.compositingGroup()
			.opacity(highlight.shouldFade(player.id) ? 0.5 : 1)
			
			HStack {
				identitySection
					.foregroundColor(relativeColor)
				
				divider
				
				ZStack {
					if let score = player.stats?.score {
						let roundsPlayed = max(1, data.details.roundResults.count)
						Text(verbatim: "\(score / roundsPlayed)")
					} else {
						Text("–").foregroundStyle(.secondary)
					}
				}
				.frame(width: 60)
				
				divider
				
				KDASummaryView(player: player)
					.frame(width: 120)
				
				if !data.parties.isEmpty {
					divider
					
					partyLabel(for: player.partyID)
						.frame(width: 80)
				}
			}
			.padding(.vertical, Self.padding)
			
			relativeColor
				.frame(width: Self.padding)
		}
		.background(rowTeamColor.opacity(data.isMultiTeam ? 0.34 : 0.25))
		.frame(height: 44)
		.cornerRadius(Self.padding)
		.compositingGroup() // for the destination-out blending
		.onTapGesture {
			highlight.switchHighlight(to: player)
		}
		.withLocalData($playerUser, id: player.id)
		.withLocalData($summary, id: player.id)
	}
	
	@ViewBuilder
	var identitySection: some View {
		let resolvedName = !player.gameName.isEmpty
			? player.gameName
			: playerUser.flatMap { !$0.gameName.isEmpty ? $0.gameName : nil }
		Group {
			if shouldAnonymize(player.id) {
				Text("Player")
					.foregroundStyle(.secondary)
			} else if let resolvedName {
				Text(resolvedName)
			} else {
				Text("Player")
					.foregroundStyle(.secondary)
			}
		}
		.font(.body.weight(
			highlight.isHighlighting(player.partyID)
				.map { $0 ? .semibold : .regular }
			?? .medium
		))
		.fixedSize()
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.trailing, 4)
		
		Spacer()
		
		if player.id != data.myself?.id {
			TransparentNavigationLink {
				MatchListView(userID: player.id)
			} label: {
				Image(systemName: "person.crop.circle.fill")
					.frame(maxHeight: .infinity)
					.padding(.horizontal, 4)
			}
		}
		
		GeometryReader { geometry in
			RankInfoView(
				summary: summary,
				size: geometry.size.height,
				lineWidth: 2,
				shouldShowProgress: false,
				shouldFadeUnranked: true
			)
			.foregroundColor(nil)
		}
		.aspectRatio(1, contentMode: .fit)
	}
	
	func partyLabel(for party: Party.ID) -> some View {
		Group {
			if let partyIndex = data.parties.firstIndex(of: party) {
				let partyLetter = Self.partyLetters[partyIndex]
				let shouldEmphasize = highlight.isHighlighting(party) == true
				Text("Party \(partyLetter)", comment: "Scoreboard: party letter")
					.fontWeight(shouldEmphasize ? .medium : .regular)
			} else {
				Text("–")
			}
		}
		.opacity(highlight.shouldFade(party) ? 0.5 : 1)
	}
}

extension ScoreboardRowView {
	init(player: Player, data: MatchViewData, placement: String? = nil, highlight: Binding<PlayerHighlightInfo>) {
		self.init(
			player: player, data: data, placement: placement, highlight: highlight,
			playerUser: .init(id: player.id),
			summary: .init(id: player.id)
		)
	}
}

#if DEBUG
struct ScoreboardView_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			ScoreboardView(data: PreviewData.singleMatchData, highlight: .constant(.init()))
				.padding(.vertical)
			
			ScoreboardRowView(
				player: PreviewData.singleMatch.players[0],
				data: PreviewData.singleMatchData,
				highlight: .constant(.init())
			)
			.padding()
		}
		.fixedSize(horizontal: true, vertical: true)
		.previewLayout(.sizeThatFits)
	}
}
#endif
