import SwiftUI
import ValorantAPI
import HandyOperators

struct MatchDetailsView: View {
	enum Tab: String, CaseIterable, Identifiable {
		case summary = "Summary"
		case scoreboard = "Scoreboard"
		case rounds = "Rounds"
		case duels = "Duels"
		case performance = "Performance"
		case economy = "Economy"
		
		var id: String { rawValue }
	}
	
	let data: MatchViewData
	private let analytics: MatchAnalytics
	
	@State private var activeTab: Tab = .summary
	@State private var focusedPlayerID: Player.ID
	@State private var highlight = PlayerHighlightInfo()
	@State private var groupedByTeam = true
	@State private var scoreboardSort: MatchScoreboardSort = .acs
	@State private var isRefreshingProfiles = false
	@State private var isShowingShareSheet = false
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	
	init(data: MatchViewData) {
		self.data = data
		self.analytics = MatchAnalytics(details: data.details)
		let initialFocus = data.myself?.id
			?? data.details.players.first(where: { $0.teamID != .neutral })?.id
			?? data.details.players[0].id
		self._focusedPlayerID = State(initialValue: initialFocus)
	}
	
	private var focusedPlayer: Player {
		data.players[focusedPlayerID]
			?? data.myself
			?? data.details.players[0]
	}
	
	private var focusedData: MatchViewData {
		if focusedPlayer.id == data.myself?.id { return data }
		return MatchViewData(details: data.details, userID: focusedPlayer.id)
	}
	
	private var availableTabs: [Tab] {
		if data.details.teams.count == 2 && !data.details.roundResults.isEmpty {
			return Tab.allCases
		}
		if !data.details.roundResults.isEmpty {
			return [.summary, .scoreboard, .rounds, .performance]
		}
		return [.summary, .scoreboard]
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				tabBar
				
				Group {
					switch activeTab {
					case .summary:
						MatchSummaryTabView(
							data: focusedData,
							analytics: analytics,
							focusedPlayer: focusedPlayer
						)
						
					case .scoreboard:
						ScoreboardView(
							data: data,
							analytics: analytics,
							focusedPlayerID: focusedPlayer.id,
							groupedByTeam: groupedByTeam,
							sort: scoreboardSort,
							highlight: $highlight,
							onSelectFocus: { newID in
								focusedPlayerID = newID
							}
						)
						
					case .rounds:
						roundsTab
						
					case .duels:
						MatchDuelsTabView(
							data: focusedData,
							analytics: analytics,
							focusedTeamID: focusedPlayer.teamID
						)
						
					case .performance:
						MatchPerformanceTabView(
							data: focusedData,
							analytics: analytics,
							focusedPlayer: focusedPlayer
						)
						
					case .economy:
						MatchEconomyTabView(
							data: focusedData,
							analytics: analytics,
							focusedPlayer: focusedPlayer
						)
					}
				}
				.padding(.horizontal, 16)
			}
			.padding(.top, 8)
			.padding(.bottom, 24)
		}
		.background(Color.groupedBackground)
		.safeAreaInset(edge: .bottom) {
			focusedPlayerFloatingBar
		}
		.navigationTitle(activeTab == .summary ? Text("Match Details", comment: "Match Details: title") : Text(""))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if activeTab != .summary {
				ToolbarItem(placement: .principal) {
					compactHeaderTitle
				}
			}
			
			ToolbarItem(placement: .primaryAction) {
				Button {
					isShowingShareSheet = true
				} label: {
					Image(systemName: "square.and.arrow.up")
						.foregroundStyle(Color.accentColor)
				}
			}
		}
		.sheet(isPresented: $isShowingShareSheet) {
			MatchShareSheet(
				data: focusedData,
				analytics: analytics,
				focusedPlayer: focusedPlayer
			)
		}
	}
	
	// MARK: - Top Tab Bar & Compact Title
	
	private var tabBar: some View {
		ScrollViewReader { proxy in
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					ForEach(availableTabs) { tab in
						let isSelected = activeTab == tab
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								activeTab = tab
							}
							withAnimation(.easeInOut(duration: 0.25)) {
								proxy.scrollTo(tab.id, anchor: .center)
							}
						} label: {
							Text(tab.rawValue)
								.font(.subheadline.weight(isSelected ? .semibold : .medium))
								.foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
								.padding(.horizontal, 14)
								.padding(.vertical, 8)
								.background(
									isSelected ? Color.secondaryGroupedBackground : Color.clear,
									in: Capsule()
								)
								.overlay(
									Capsule()
										.stroke(
											isSelected ? Color.white.opacity(0.14) : Color.clear,
											lineWidth: 1
										)
								)
						}
						.buttonStyle(.plain)
						.id(tab.id)
					}
				}
				.padding(.horizontal, 16)
			}
		}
	}
	
	@ViewBuilder
	private var compactHeaderTitle: some View {
		let info = data.details.matchInfo
		let mapName = assets?.maps[info.mapID]?.displayName ?? "Map"
		HStack(spacing: 6) {
			GameModeImage(id: info.modeID)
				.frame(width: 18, height: 18)
				.foregroundStyle(.secondary)
			
			Text(mapName)
				.font(.subheadline.weight(.bold))
			
			if data.details.teams.count == 2,
			   let ownTeam = data.details.teams.first(where: { $0.id == focusedPlayer.teamID }),
			   let enemyTeam = data.details.teams.first(where: { $0.id != focusedPlayer.teamID }) {
				HStack(spacing: 3) {
					Text("\(ownTeam.roundsWon)")
						.foregroundStyle(Color.valorantBlue)
					Text("–")
						.foregroundStyle(.secondary)
					Text("\(enemyTeam.roundsWon)")
						.foregroundStyle(Color.valorantRed)
				}
				.font(.subheadline.weight(.bold).monospacedDigit())
			}
		}
	}
	
	// MARK: - Rounds Tab
	
	@ViewBuilder
	private var roundsTab: some View {
		VStack(spacing: 16) {
			if KillBreakdownView.canDisplay(for: focusedData) {
				KillBreakdownView(data: focusedData, highlight: $highlight)
					.padding(.horizontal, -16) // KillBreakdownView handles its own horizontal insets
				
				NavigationLink {
					RoundInfoContainer(matchData: focusedData, roundNumber: 0)
				} label: {
					HStack(spacing: 14) {
						Image(systemName: "map")
							.font(.title3.weight(.semibold))
							.foregroundStyle(Color.accentColor)
							.frame(width: 30)
						
						VStack(alignment: .leading, spacing: 3) {
							Text("Details by Round", comment: "Match Details: button to view details by round")
								.font(.headline)
								.foregroundStyle(.primary)
							Text("View the map, timeline, and events for each round.")
								.font(.caption)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.leading)
						}
						
						Spacer()
						
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
					}
					.padding(14)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				}
				.buttonStyle(.plain)
			} else {
				Text("Round breakdown is not available for this game mode.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity)
					.padding(24)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
			}
		}
	}
	
	// MARK: - Floating Focused Player Bar & Menu
	
	private var focusedPlayerFloatingBar: some View {
		let menuPlayers = data.details.players
			.filter { $0.teamID != .neutral }
			.sorted { lhs, rhs in
				let lOwn = lhs.teamID == focusedPlayer.teamID
				let rOwn = rhs.teamID == focusedPlayer.teamID
				if lOwn != rOwn { return lOwn }
				return (analytics.byPlayer[lhs.id]?.acs ?? Double(lhs.score))
					> (analytics.byPlayer[rhs.id]?.acs ?? Double(rhs.score))
			}
		
		return Menu {
			if activeTab == .scoreboard {
				Button {
					withAnimation(.easeInOut(duration: 0.2)) { groupedByTeam = true }
				} label: {
					Label("Group by Team", systemImage: groupedByTeam ? "checkmark" : "person.2")
				}
				
				Button {
					withAnimation(.easeInOut(duration: 0.2)) { groupedByTeam = false }
				} label: {
					Label("Combined Lobby", systemImage: !groupedByTeam ? "checkmark" : "arrow.up.and.down")
				}
				
				Divider()
				
				Menu {
					ForEach(MatchScoreboardSort.allCases) { option in
						Button {
							scoreboardSort = option
						} label: {
							if scoreboardSort == option {
								Label(option.rawValue, systemImage: "checkmark")
							} else {
								Text(option.rawValue)
							}
						}
					}
				} label: {
					Label("Sort By", systemImage: "arrow.up.arrow.down")
				}
			}
			
			Button {
				Task { await refreshAllProfiles() }
			} label: {
				Label("Refresh Profiles", systemImage: "arrow.clockwise")
			}
			
			Menu {
				ForEach(menuPlayers) { player in
					Button {
						focusedPlayerID = player.id
					} label: {
						let name = player.gameName.isEmpty ? "Player" : player.gameName
						if player.id == focusedPlayer.id {
							Label(name, systemImage: "checkmark")
						} else {
							Text(name)
						}
					}
				}
			} label: {
				Label("Focused Player", systemImage: "scope")
			}
		} label: {
			HStack(spacing: 10) {
				Group {
					if let agentID = focusedPlayer.agentID {
						AgentImage.icon(
							agentID,
							teamID: focusedPlayer.teamID,
							isOVariant: data.isGauntletOVariant(for: focusedPlayer)
						)
					} else {
						Image(systemName: "person.fill")
							.foregroundStyle(.secondary)
					}
				}
				.frame(width: 30, height: 30)
				.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
				.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
				
				VStack(alignment: .leading, spacing: 1) {
					Text("FOCUSED PLAYER")
						.font(.system(size: 9, weight: .semibold))
						.foregroundStyle(.secondary)
					
					HStack(spacing: 0) {
						Text(focusedPlayer.gameName.isEmpty ? "Player" : focusedPlayer.gameName)
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.primary)
							.lineLimit(1)
						if !focusedPlayer.tagLine.isEmpty {
							Text("#\(focusedPlayer.tagLine)")
								.font(.subheadline)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					}
				}
				
				Spacer(minLength: 8)
				
				if activeTab == .scoreboard {
					VStack(alignment: .trailing, spacing: 1) {
						Text("SORT")
							.font(.system(size: 9, weight: .semibold))
							.foregroundStyle(.secondary)
						Text(scoreboardSort == .score ? "Score" : scoreboardSort.rawValue)
							.font(.caption.weight(.semibold))
							.foregroundStyle(.primary)
					}
				}
				
				if isRefreshingProfiles {
					ProgressView()
						.controlSize(.small)
				} else {
					Image(systemName: "chevron.up.chevron.down")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 9)
			.background(.ultraThinMaterial, in: Capsule())
			.overlay(
				Capsule()
					.stroke(Color.white.opacity(0.14), lineWidth: 1)
			)
			.shadow(color: .black.opacity(0.35), radius: 10, y: 4)
		}
		.buttonStyle(.plain)
		.padding(.horizontal, 20)
		.padding(.bottom, 6)
	}
	
	private func refreshAllProfiles() async {
		guard !isRefreshingProfiles else { return }
		isRefreshingProfiles = true
		defer { isRefreshingProfiles = false }
		await load { client in
			let ids = data.details.players.map(\.id)
			try? await client.fetchUsers(for: ids)
			for playerID in ids {
				try? await client.fetchCareerSummary(for: playerID, forceFetch: true)
			}
		}
	}
}

// MARK: - Share Match Summary Sheet

private struct MatchShareSheet: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedPlayer: Player
	
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var imageManager: ImageManager
	
	@State private var renderedImage: UIImage?
	@State private var isRendering = false
	
	var body: some View {
		NavigationView {
			ScrollView {
				VStack(spacing: 16) {
					snapshotCard(preloaded: nil)
					
					if let renderedImage {
						ShareLink(
							item: Image(uiImage: renderedImage),
							preview: SharePreview("Match Summary", image: Image(uiImage: renderedImage))
						) {
							Label("Share Image", systemImage: "square.and.arrow.up")
								.font(.headline)
								.foregroundStyle(.white)
								.frame(maxWidth: .infinity)
								.padding(.vertical, 14)
								.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
					} else if isRendering {
						ProgressView("Rendering summary...")
					}
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Share Match")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
			.task {
				await renderSnapshot()
			}
		}
	}
	
	private func snapshotCard(preloaded: [AssetImage: UIImage]?) -> some View {
		let info = data.details.matchInfo
		let mapAsset = assets?.maps[info.mapID]?.listViewIcon
		let agentAsset = focusedPlayer.agentID.flatMap { assets?.agents[$0]?.displayIcon }
		let stats = analytics.byPlayer[focusedPlayer.id]
		let mapName = assets?.maps[info.mapID]?.displayName ?? "Map"
		
		return VStack(alignment: .leading, spacing: 14) {
			ZStack(alignment: .bottomLeading) {
				Group {
					if let mapAsset, let ui = preloaded?[mapAsset] {
						Image(uiImage: ui).resizable().scaledToFill()
					} else {
						MapImage.wideImage(info.mapID).scaledToFill()
					}
				}
				.frame(height: 110)
				.frame(maxWidth: .infinity)
				.clipped()
				.overlay(Color.black.opacity(0.45))
				
				HStack(spacing: 12) {
					Group {
						if let agentAsset, let ui = preloaded?[agentAsset] {
							Image(uiImage: ui).resizable().scaledToFill()
						} else if let aid = focusedPlayer.agentID {
							AgentImage.icon(aid, teamID: focusedPlayer.teamID, isOVariant: data.isGauntletOVariant(for: focusedPlayer))
						}
					}
					.frame(width: 56, height: 56)
					.background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
					.clipShape(RoundedRectangle(cornerRadius: 10))
					
					VStack(alignment: .leading, spacing: 3) {
						Text(focusedPlayer.gameName.isEmpty ? "Player" : focusedPlayer.gameName)
							.font(.headline.bold())
							.foregroundStyle(.white)
						Text(mapName)
							.font(.caption.weight(.medium))
							.foregroundStyle(.white.opacity(0.85))
					}
					
					Spacer()
					
					if data.details.teams.count == 2,
					   let own = data.details.teams.first(where: { $0.id == focusedPlayer.teamID }),
					   let enemy = data.details.teams.first(where: { $0.id != focusedPlayer.teamID }) {
						Text("\(own.roundsWon) – \(enemy.roundsWon)")
							.font(.title2.bold().monospacedDigit())
							.foregroundStyle(.white)
					}
				}
				.padding(14)
			}
			.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			
			if let stats {
				HStack(spacing: 0) {
					shareMetric("K / D / A", "\(stats.kills)/\(stats.deaths)/\(stats.assists)")
					shareMetric("ACS", "\(Int(stats.acs.rounded()))")
					shareMetric("ADR", "\(Int(stats.adr.rounded()))")
					shareMetric("SCORE", "\(stats.performanceScore)")
				}
			}
			
			HStack {
				info.queueLabel
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Text("Recon Bolt")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func shareMetric(_ label: String, _ value: String) -> some View {
		VStack(spacing: 3) {
			Text(value)
				.font(.headline.bold().monospacedDigit())
			Text(label)
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
	}
	
	@MainActor
	private func renderSnapshot() async {
		isRendering = true
		var targets: [AssetImage] = []
		if let mapImg = assets?.maps[data.details.matchInfo.mapID]?.listViewIcon {
			targets.append(mapImg)
		}
		if let aid = focusedPlayer.agentID, let agentImg = assets?.agents[aid]?.displayIcon {
			targets.append(agentImg)
		}
		
		var loaded: [AssetImage: UIImage] = [:]
		for asset in targets {
			if let cached = asset.load() {
				loaded[asset] = cached
			} else {
				_ = try? await asset.ensureDownloaded()
				if let dl = asset.load() {
					loaded[asset] = dl
				}
			}
		}
		
		let renderer = ImageRenderer(
			content: snapshotCard(preloaded: loaded)
				.environment(\.assets, assets)
				.environmentObject(imageManager)
				.frame(width: 360)
				.preferredColorScheme(.dark)
		)
		renderer.scale = 3.0
		renderedImage = renderer.uiImage
		isRendering = false
	}
}

#if DEBUG
struct MatchDetailsView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationView {
			MatchDetailsView(
				data: PreviewData.singleMatchData
			)
		}
		.withToolbar(allowLargeTitles: false)
	}
}
#endif
