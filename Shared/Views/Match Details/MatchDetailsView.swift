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
	@State private var isCompactScoreboard = false
	@State private var scoreboardSort: MatchScoreboardSort = .acs
	@State private var resolvedUsers: [Player.ID: User] = [:]
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
							focusedPlayer: focusedPlayer,
							resolvedUsers: resolvedUsers
						)
						
					case .scoreboard:
						ScoreboardView(
							data: data,
							analytics: analytics,
							focusedPlayerID: focusedPlayer.id,
							groupedByTeam: groupedByTeam,
							isCompact: isCompactScoreboard,
							sort: scoreboardSort,
							resolvedUsers: resolvedUsers,
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
							focusedTeamID: focusedPlayer.teamID,
							resolvedUsers: resolvedUsers
						)
						
					case .performance:
						MatchPerformanceTabView(
							data: focusedData,
							analytics: analytics,
							focusedPlayer: focusedPlayer,
							resolvedUsers: resolvedUsers
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
				focusedPlayer: focusedPlayer,
				resolvedUsers: resolvedUsers
			)
		}
		.task(id: data.details.id) {
			await ensurePlayerNamesLoaded()
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
				ControlGroup {
					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							groupedByTeam.toggle()
						}
					} label: {
						Label(
							groupedByTeam ? "Combined Lobby" : "Group by Team",
							systemImage: groupedByTeam ? "person.2.fill" : "person.2"
						)
					}
					
					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							isCompactScoreboard.toggle()
						}
					} label: {
						Label(
							isCompactScoreboard ? "Standard View" : "Compact View",
							systemImage: isCompactScoreboard
								? "arrow.up.and.line.horizontal.and.arrow.down"
								: "arrow.down.and.line.horizontal.and.arrow.up"
						)
					}
				}
				
				Divider()
			}
			
			Button {
				Task { await refreshAllProfiles() }
			} label: {
				Label("Refresh Profiles", systemImage: "arrow.clockwise")
			}
			
			if activeTab == .scoreboard {
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
			
			Menu {
				ForEach(menuPlayers) { player in
					let displayName = player.resolvedDisplayName(using: resolvedUsers)
					let tag = player.resolvedTagLine(using: resolvedUsers)
					let labelText = tag.isEmpty ? displayName : "\(displayName)#\(tag)"
					let isCurrent = player.id == focusedPlayer.id
					
					Toggle(isOn: Binding(
						get: { isCurrent },
						set: { _ in focusedPlayerID = player.id }
					)) {
						Label {
							Text(labelText)
						} icon: {
							if let uiIcon = menuAgentIcon(for: player) {
								Image(uiImage: uiIcon)
							} else {
								Image(systemName: "person.fill")
							}
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
					
					let focusName = focusedPlayer.resolvedDisplayName(using: resolvedUsers)
					let focusTag = focusedPlayer.resolvedTagLine(using: resolvedUsers)
					HStack(spacing: 0) {
						Text(focusName)
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.primary)
							.lineLimit(1)
						if !focusTag.isEmpty {
							Text("#\(focusTag)")
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
		.menuOrder(.fixed)
		.buttonStyle(.plain)
		.padding(.horizontal, 20)
		.padding(.bottom, 6)
	}
	
	private func menuAgentIcon(for player: Player) -> UIImage? {
		let source: UIImage?
		if player.agentID == .abilityDraftAgent {
			let name = player.teamID.gauntletRoboAssetName(
				isOVariant: data.isGauntletOVariant(for: player),
				isKillfeed: false
			) ?? "gauntlet/robo_grey_x"
			source = UIImage.bundledAsset(named: name)
		} else if let aid = player.agentID {
			source = assets?.agents[aid]?.displayIcon.load()
		} else {
			source = nil
		}
		guard let source else { return nil }
		let side = CGFloat(22)
		let size = CGSize(width: side, height: side)
		let renderer = UIGraphicsImageRenderer(size: size)
		return renderer.image { _ in
			UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).addClip()
			source.draw(in: CGRect(origin: .zero, size: size))
		}.withRenderingMode(.alwaysOriginal)
	}
	
	private func syncCachedUsers() async {
		var updated = resolvedUsers
		var changed = false
		let manager = LocalDataProvider.shared.userManager
		for player in data.details.players where player.gameName.isEmpty {
			if let cached = await manager.cachedObject(for: player.id), !cached.gameName.isEmpty {
				if updated[player.id]?.gameName != cached.gameName || updated[player.id]?.tagLine != cached.tagLine {
					updated[player.id] = cached
					changed = true
				}
			}
		}
		if changed {
			resolvedUsers = updated
		}
	}
	
	private func ensurePlayerNamesLoaded() async {
		await syncCachedUsers()
		let missingIDs = data.details.players
			.filter { $0.gameName.isEmpty && (resolvedUsers[$0.id]?.gameName.isEmpty ?? true) }
			.map(\.id)
		guard !missingIDs.isEmpty else { return }
		await load { client in
			let fetched = try await client.getUsers(for: missingIDs)
			await LocalDataProvider.shared.userManager.store(fetched, asOf: .now)
		}
		await syncCachedUsers()
	}
	
	private func refreshAllProfiles() async {
		guard !isRefreshingProfiles else { return }
		isRefreshingProfiles = true
		defer { isRefreshingProfiles = false }
		await load { client in
			let ids = data.details.players.map(\.id)
			if let fetched = try? await client.getUsers(for: ids) {
				await LocalDataProvider.shared.userManager.store(fetched, asOf: .now)
			}
			for playerID in ids {
				try? await client.fetchCareerSummary(for: playerID, forceFetch: true)
			}
		}
		await syncCachedUsers()
	}
}

// MARK: - Share Match Summary Sheet

private struct MatchShareSheet: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedPlayer: Player
	var resolvedUsers: [Player.ID: User] = [:]
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var imageManager: ImageManager
	
	@State private var renderedImage: UIImage?
	@State private var showsRiotID = true
	@State private var didCopy = false
	
	private static let cardWidth: CGFloat = 360
	
	var body: some View {
		NavigationView {
			ScrollView {
				VStack(spacing: 16) {
					cardPreview
					
					showRiotIDToggle
					
					if let renderedImage {
						ShareLink(
							item: Image(uiImage: renderedImage),
							preview: SharePreview("Match Summary", image: Image(uiImage: renderedImage))
						) {
							shareButtonLabel("Share Match Card")
						}
						
						Button {
							UIPasteboard.general.image = renderedImage
							didCopy = true
							DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
								didCopy = false
							}
						} label: {
							copyButtonLabel(didCopy ? "Copied" : "Copy Image", systemImage: didCopy ? "checkmark" : "doc.on.doc")
						}
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
		}
		.task(id: showsRiotID) {
			await renderSnapshot()
		}
	}
	
	// MARK: - Sheet Controls
	
	@ViewBuilder
	private var cardPreview: some View {
		if let renderedImage {
			Image(uiImage: renderedImage)
				.resizable()
				.scaledToFit()
				.frame(maxWidth: .infinity)
				.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
				.shadow(color: .black.opacity(0.35), radius: 14, y: 6)
		} else {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(Color.secondaryGroupedBackground)
				.aspectRatio(0.82, contentMode: .fit)
				.overlay { ProgressView("Rendering summary…") }
		}
	}
	
	private var showRiotIDToggle: some View {
		Toggle(isOn: $showsRiotID) {
			VStack(alignment: .leading, spacing: 2) {
				Text("Show Riot ID")
					.font(.subheadline.weight(.medium))
				Text("Include your #tag in the shared image")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.tint(Color.accentColor)
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func shareButtonLabel(_ title: String) -> some View {
		Label(title, systemImage: "square.and.arrow.up")
			.font(.headline)
			.foregroundStyle(.white)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 15)
			.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func copyButtonLabel(_ title: String, systemImage: String) -> some View {
		Label(title, systemImage: systemImage)
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(Color.accentColor)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 13)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: - Renderable Card
	
	private var cardName: String {
		focusedPlayer.resolvedDisplayName(using: resolvedUsers)
	}
	
	private var cardTag: String {
		focusedPlayer.resolvedTagLine(using: resolvedUsers)
	}
	
	private func resultInfo() -> (title: String, color: Color, score: String?)? {
		guard data.details.teams.count == 2 else { return nil }
		guard let own = data.details.teams.first(where: { $0.id == focusedPlayer.teamID }),
			  let enemy = data.details.teams.first(where: { $0.id != focusedPlayer.teamID })
		else { return nil }
		
		let hasWinner = data.details.teams.contains(where: \.won)
		if !hasWinner {
			return ("DRAW", .secondary, "\(own.roundsWon) – \(enemy.roundsWon)")
		}
		return own.won
			? ("VICTORY", .green, "\(own.roundsWon) – \(enemy.roundsWon)")
			: ("DEFEAT", Color.valorantRed, "\(own.roundsWon) – \(enemy.roundsWon)")
	}
	
	private func badges(for stats: MatchAnalytics.PlayerMatchAnalytics?) -> [String] {
		guard let stats else { return [] }
		var result: [String] = []
		for count in stats.multiKills.keys.sorted(by: >) where count >= 2 {
			let occurrences = stats.multiKills[count, default: 0]
			guard occurrences > 0 else { continue }
			result.append(occurrences > 1 ? "\(count)K ×\(occurrences)" : "\(count)K")
		}
		if let biggestClutch = stats.clutchWonSizes.filter({ $0.value > 0 }).keys.max() {
			result.append("1V\(biggestClutch) CLUTCH")
		}
		if stats.kastPercent >= 80 {
			result.append("HIGH KAST")
		}
		return Array(result.prefix(4))
	}
	
	private func snapshotCard(showsRiotID: Bool, preloaded: [AssetImage: UIImage]) -> some View {
		let info = data.details.matchInfo
		let mapAsset = assets?.maps[info.mapID]?.listViewIcon
		let mapImage = mapAsset.flatMap { preloaded[$0] }
		let mapName = assets?.maps[info.mapID]?.displayName ?? "Map"
		let agentImage = focusedPlayer.agentID
			.flatMap { assets?.agents[$0]?.displayIcon }
			.flatMap { preloaded[$0] }
		let stats = analytics.byPlayer[focusedPlayer.id]
		let result = resultInfo()
		let tierInfo = seasons?.currentTierInfo(number: focusedPlayer.competitiveTier)
		let tierIcon = tierInfo?.icon.flatMap { preloaded[$0] }
		let matchBadges = badges(for: stats)
		
		return VStack(alignment: .leading, spacing: 14) {
			ZStack(alignment: .bottomLeading) {
				Group {
					if let mapImage {
						Image(uiImage: mapImage)
							.resizable()
							.scaledToFill()
					} else {
						Color(white: 0.16)
					}
				}
				.frame(width: Self.cardWidth, height: 128)
				.clipped()
				.overlay(
					LinearGradient(
						colors: [.black.opacity(0.25), .black.opacity(0.85)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
				
				VStack(alignment: .leading, spacing: 4) {
					Text(mapName)
						.font(.title2.bold())
						.foregroundStyle(.white)
					
					if let result {
						HStack(alignment: .firstTextBaseline, spacing: 8) {
							Text(result.title)
								.font(.caption.weight(.heavy))
								.foregroundStyle(result.color)
							if let score = result.score {
								Text(score)
									.font(.subheadline.weight(.bold).monospacedDigit())
									.foregroundStyle(.white.opacity(0.9))
							}
						}
					}
				}
				.padding(14)
			}
			.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			
			HStack(spacing: 12) {
				Group {
					if let agentImage {
						Image(uiImage: agentImage)
							.resizable()
							.scaledToFill()
					} else {
						Color.white.opacity(0.1)
					}
				}
				.frame(width: 54, height: 54)
				.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
				
				VStack(alignment: .leading, spacing: 3) {
					HStack(spacing: 0) {
						Text(cardName)
							.font(.headline.bold())
							.lineLimit(1)
						if showsRiotID, !cardTag.isEmpty {
							Text("#\(cardTag)")
								.font(.subheadline)
								.foregroundStyle(.white.opacity(0.5))
								.lineLimit(1)
						}
					}
					info.queueLabel
						.font(.caption)
						.foregroundStyle(.white.opacity(0.55))
				}
				
				Spacer(minLength: 0)
				
				if let tierIcon {
					Image(uiImage: tierIcon)
						.resizable()
						.scaledToFit()
						.frame(width: 44, height: 44)
				}
			}
			
			if let stats {
				HStack(spacing: 0) {
					shareMetric("\(stats.kills)/\(stats.deaths)/\(stats.assists)", "K / D / A")
					shareMetric("\(Int(stats.acs.rounded()))", "ACS")
					shareMetric("\(Int(stats.adr.rounded()))", "ADR")
					shareMetric(String(format: "%.0f%%", stats.hsPercent), "HS %")
					shareMetric(String(format: "%.0f%%", stats.kastPercent), "KAST")
				}
				.padding(.vertical, 10)
				.background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				
				if !matchBadges.isEmpty {
					HStack(spacing: 6) {
						ForEach(matchBadges, id: \.self) { badge in
							Text(badge)
								.font(.system(size: 9, weight: .bold))
								.foregroundStyle(.white.opacity(0.8))
								.lineLimit(1)
								.padding(.horizontal, 8)
								.padding(.vertical, 4)
								.background(Color.white.opacity(0.08), in: Capsule())
						}
					}
				}
			}
			
			HStack {
				Text(info.gameStart.formatted(.dateTime.day().month(.abbreviated).year()))
					.font(.caption2)
					.foregroundStyle(.white.opacity(0.45))
				Spacer()
				Text("Vantage")
					.font(.caption2.weight(.bold))
					.foregroundStyle(.white.opacity(0.45))
			}
		}
		.padding(16)
		.frame(width: Self.cardWidth)
		.background(
			LinearGradient(
				colors: [Color(red: 0.11, green: 0.11, blue: 0.14), Color(red: 0.07, green: 0.07, blue: 0.09)],
				startPoint: .top,
				endPoint: .bottom
			),
			in: RoundedRectangle(cornerRadius: 20, style: .continuous)
		)
	}
	
	private func shareMetric(_ value: String, _ label: String) -> some View {
		VStack(spacing: 3) {
			Text(value)
				.font(.headline.bold().monospacedDigit())
				.foregroundStyle(.white)
				.lineLimit(1)
				.minimumScaleFactor(0.7)
			Text(label)
				.font(.system(size: 9, weight: .semibold))
				.foregroundStyle(.white.opacity(0.5))
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity)
	}
	
	@MainActor
	private func renderSnapshot() async {
		var targets: [AssetImage] = []
		if let mapImg = assets?.maps[data.details.matchInfo.mapID]?.listViewIcon {
			targets.append(mapImg)
		}
		if let aid = focusedPlayer.agentID, let agentImg = assets?.agents[aid]?.displayIcon {
			targets.append(agentImg)
		}
		if let tierImg = seasons?.currentTierInfo(number: focusedPlayer.competitiveTier)?.icon {
			targets.append(tierImg)
		}
		
		var loaded: [AssetImage: UIImage] = [:]
		for asset in targets {
			if let cached = asset.load() {
				loaded[asset] = cached
			} else {
				_ = try? await asset.ensureDownloaded()
				if let downloaded = asset.load() {
					loaded[asset] = downloaded
				}
			}
		}
		
		let renderer = ImageRenderer(
			content: snapshotCard(showsRiotID: showsRiotID, preloaded: loaded)
				.environment(\.assets, assets)
				.environment(\.seasons, seasons)
				.environment(\.colorScheme, .dark)
				.environmentObject(imageManager)
		)
		renderer.scale = 3.0
		if let image = renderer.uiImage {
			renderedImage = image
		}
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
