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
	@State private var menuAgentIcons: [Player.ID: UIImage] = [:]
	@State private var isRefreshingProfiles = false
	@State private var refreshProfilesTask: Task<Void, Never>?
	@State private var isShowingShareSheet = false
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	
	private final class MenuIconCache: @unchecked Sendable {
		static let shared = MenuIconCache()
		let cache = NSCache<NSString, UIImage>() <- {
			$0.countLimit = 64
		}
	}
	
	private struct MenuIconTaskKey: Equatable {
		var matchID: Match.ID
		var version: AssetVersion?
	}
	
	@MainActor
	private final class AnalyticsCache {
		static let shared = AnalyticsCache()
		private var entries: [Match.ID: (roundCount: Int, playerCount: Int, analytics: MatchAnalytics)] = [:]
		private var order: [Match.ID] = []
		
		func analytics(for details: MatchDetails) -> MatchAnalytics {
			let rCount = details.roundResults.count
			let pCount = details.players.count
			if let cached = entries[details.id], cached.roundCount == rCount, cached.playerCount == pCount {
				return cached.analytics
			}
			let built = MatchAnalytics(details: details)
			entries[details.id] = (rCount, pCount, built)
			order.removeAll { $0 == details.id }
			order.append(details.id)
			while order.count > 6 {
				let oldest = order.removeFirst()
				entries.removeValue(forKey: oldest)
			}
			return built
		}
	}
	
	init(data: MatchViewData) {
		self.data = data
		self.analytics = AnalyticsCache.shared.analytics(for: data.details)
		let initialFocus = data.myself?.id
			?? data.details.players.first(where: { $0.teamID != .neutral })?.id
			?? data.details.players.first?.id
			?? Player.ID()
		self._focusedPlayerID = State(initialValue: initialFocus)
	}
	
	private var focusedPlayer: Player? {
		data.players[focusedPlayerID]
			?? data.myself
			?? data.details.players.first
	}
	
	private func resolvedFocusedData(for focusedPlayer: Player) -> MatchViewData {
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
		if let focusedPlayer {
			mainContent(for: focusedPlayer)
		} else {
			Text("Match data unavailable.")
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.background(Color.groupedBackground)
		}
	}
	
	@ViewBuilder
	private func mainContent(for focusedPlayer: Player) -> some View {
		let focusedData = resolvedFocusedData(for: focusedPlayer)
		ScrollView {
			LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
				if activeTab == .summary {
					MatchHeroBanner(
						data: focusedData,
						analytics: analytics,
						focusedPlayer: focusedPlayer
					)
					.padding(.horizontal, 16)
				}
				
				Section {
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
							roundsTab(focusedData: focusedData)
							
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
					.padding(.top, 4)
				} header: {
					tabBar
						.padding(.vertical, 6)
						.background(Color.groupedBackground)
				}
			}
			.padding(.top, 8)
			.padding(.bottom, 24)
		}
		.background(Color.groupedBackground)
		.safeAreaInset(edge: .bottom) {
			focusedPlayerFloatingBar(for: focusedPlayer)
		}
		.navigationTitle(activeTab == .summary ? Text("Match Details", comment: "Match Details: title") : Text(""))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if activeTab != .summary {
				ToolbarItem(placement: .principal) {
					compactHeaderTitle(for: focusedPlayer)
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
				data: resolvedFocusedData(for: focusedPlayer),
				analytics: analytics,
				focusedPlayer: focusedPlayer,
				resolvedUsers: resolvedUsers
			)
		}
		.task(id: data.details.id) {
			await ensurePlayerNamesLoaded()
		}
		.task(id: MenuIconTaskKey(matchID: data.details.id, version: assets?.version)) {
			await prepareMenuAgentIcons()
		}
		.onDisappear {
			refreshProfilesTask?.cancel()
			refreshProfilesTask = nil
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
	private func compactHeaderTitle(for focusedPlayer: Player) -> some View {
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
	private func roundsTab(focusedData: MatchViewData) -> some View {
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
	
	private func focusedPlayerFloatingBar(for focusedPlayer: Player) -> some View {
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
				refreshProfilesTask?.cancel()
				refreshProfilesTask = Task { await refreshAllProfiles() }
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
							if let uiIcon = menuAgentIcons[player.id] {
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
	
	private func prepareMenuAgentIcons() async {
		let players = data.details.players
		let assets = self.assets
		var specs: [(playerID: Player.ID, cacheKey: String, bundledName: String?, assetImage: AssetImage?)] = []
		specs.reserveCapacity(players.count)
		for player in players {
			if player.agentID == .abilityDraftAgent {
				let name = player.teamID.gauntletRoboAssetName(
					isOVariant: data.isGauntletOVariant(for: player),
					isKillfeed: false
				) ?? "gauntlet/robo_grey_x"
				specs.append((player.id, "bundled:\(name)", name, nil))
			} else if let aid = player.agentID, let asset = assets?.agents[aid]?.displayIcon {
				specs.append((player.id, "asset:\(asset.url.absoluteString)", nil, asset))
			}
		}
		
		let resolved = await Task.detached(priority: .userInitiated) { () -> [Player.ID: UIImage] in
			var result: [Player.ID: UIImage] = [:]
			result.reserveCapacity(specs.count)
			for spec in specs {
				let nsKey = spec.cacheKey as NSString
				if let cached = MenuIconCache.shared.cache.object(forKey: nsKey) {
					result[spec.playerID] = cached
					continue
				}
				let source: UIImage?
				if let bundledName = spec.bundledName {
					source = UIImage.bundledAsset(named: bundledName)
				} else if let assetImage = spec.assetImage {
					source = assetImage.load()
				} else {
					source = nil
				}
				guard let source else { continue }
				let side: CGFloat = 22
				let size = CGSize(width: side, height: side)
				let renderer = UIGraphicsImageRenderer(size: size)
				let rendered = renderer.image { _ in
					UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).addClip()
					source.draw(in: CGRect(origin: .zero, size: size))
				}.withRenderingMode(.alwaysOriginal)
				MenuIconCache.shared.cache.setObject(rendered, forKey: nsKey)
				result[spec.playerID] = rendered
			}
			return result
		}.value
		
		guard !Task.isCancelled else { return }
		menuAgentIcons = resolved
	}
	
	private func syncCachedUsers() async {
		let incognitoIDs = data.details.players.filter(\.gameName.isEmpty).map(\.id)
		guard !incognitoIDs.isEmpty else { return }
		let cachedUsers = await LocalDataProvider.shared.userManager.cachedObjects(for: incognitoIDs)
		var updated = resolvedUsers
		var changed = false
		for cached in cachedUsers where !cached.gameName.isEmpty {
			if updated[cached.id]?.gameName != cached.gameName || updated[cached.id]?.tagLine != cached.tagLine {
				updated[cached.id] = cached
				changed = true
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
			LocalDataProvider.shared.userManager.store(fetched, asOf: .now)
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
				LocalDataProvider.shared.userManager.store(fetched, asOf: .now)
			}
			await withTaskGroup(of: Void.self) { group in
				var nextIndex = 0
				let maxConcurrent = 4
				for _ in 0..<min(maxConcurrent, ids.count) {
					let playerID = ids[nextIndex]
					nextIndex += 1
					group.addTask {
						guard !Task.isCancelled else { return }
						try? await client.fetchCareerSummary(for: playerID, forceFetch: true)
					}
				}
				for await _ in group {
					if Task.isCancelled { break }
					if nextIndex < ids.count {
						let nextID = ids[nextIndex]
						nextIndex += 1
						group.addTask {
							guard !Task.isCancelled else { return }
							try? await client.fetchCareerSummary(for: nextID, forceFetch: true)
						}
					}
				}
			}
		}
		guard !Task.isCancelled else { return }
		await syncCachedUsers()
	}
}

// MARK: - Share Match Summary Sheet

private struct MatchShareSheet: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedPlayer: Player
	var resolvedUsers: [Player.ID: User] = [:]
	
	@LocalData private var summary: CareerSummary?
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.configs) private var configs
	@Environment(\.location) private var location
	@Environment(\.dismiss) private var dismiss
	@Environment(\.imageManager) private var imageManager
	
	@State private var showRiotID = true
	@State private var preloadedImages: [AssetImage: UIImage] = [:]
	@State private var renderedImage: UIImage?
	@State private var isRendering = true
	@State private var didCopyImage = false
	
	init(
		data: MatchViewData,
		analytics: MatchAnalytics,
		focusedPlayer: Player,
		resolvedUsers: [Player.ID: User] = [:]
	) {
		self.data = data
		self.analytics = analytics
		self.focusedPlayer = focusedPlayer
		self.resolvedUsers = resolvedUsers
		self._summary = LocalData(id: focusedPlayer.id)
	}
	
	private var agentAsset: AssetImage? {
		focusedPlayer.agentID.flatMap { assets?.agents[$0]?.displayIcon }
	}
	
	private var tierIconAsset: AssetImage? {
		guard let summary else { return nil }
		let act = seasons?.currentAct()
		let info = summary.competitiveInfo?.inSeason(act?.id)
		let tier = info?.competitiveTier ?? 0
		if tier == 0, let peak = summary.peakRankInfo(seasons: seasons) {
			return peak.icon
		}
		return seasons?.tierInfo(number: tier, in: act)?.icon
	}
	
	private struct RenderKey: Equatable {
		let showRiotID: Bool
		let hasSummary: Bool
		let version: AssetVersion?
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 18) {
					matchCardCanvas(images: preloadedImages, clipCorners: true)
						.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
						.shadow(color: .black.opacity(0.45), radius: 22, y: 10)
					
					SettingsCard {
						Toggle("Show Riot ID", isOn: $showRiotID)
							.padding(.horizontal, 16)
							.padding(.vertical, 12)
					}
					
					ShareCardActionButtons(
						renderedImage: renderedImage,
						isPreparing: isRendering,
						shareTitle: "Share Match Card",
						previewTitle: "VALORANT Match",
						didCopyImage: $didCopyImage
					)
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Share Match")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.tint)
					}
				}
			}
			.withLocalData($summary, id: focusedPlayer.id)
			.task(id: RenderKey(showRiotID: showRiotID, hasSummary: summary != nil, version: assets?.version)) {
				await prepareAndRender()
			}
		}
	}
	
	private func matchCardCanvas(images: [AssetImage: UIImage], clipCorners: Bool) -> some View {
		let info = data.details.matchInfo
		let mapName = assets?.maps[info.mapID]?.displayName ?? "Map"
		let agentName = focusedPlayer.agentID.flatMap { assets?.agents[$0]?.displayName }
		let stats = analytics.byPlayer[focusedPlayer.id]
		let comparison = analytics.lobbyComparison(for: focusedPlayer.id)
		let ownTeam = data.details.teams.first(where: { $0.id == focusedPlayer.teamID })
		let enemyTeam = data.details.teams.first(where: { $0.id != focusedPlayer.teamID })
		let highlights = (stats?.highlights ?? []).filter { !$0.isNegative }.prefix(4)
		
		let outcome: (title: String, color: Color) = {
			guard let own = ownTeam, let enemy = enemyTeam else {
				return ("MATCH", .white.opacity(0.7))
			}
			if own.roundsWon > enemy.roundsWon {
				return ("VICTORY", Color(red: 0.24, green: 0.85, blue: 0.50))
			} else if own.roundsWon < enemy.roundsWon {
				return ("DEFEAT", Color(red: 0.96, green: 0.34, blue: 0.42))
			} else {
				return ("DRAW", .white.opacity(0.7))
			}
		}()
		
		return VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 2) {
					info.queueLabel
						.textCase(.uppercase)
						.font(.system(size: 11, weight: .semibold))
						.tracking(1.1)
						.foregroundStyle(.white.opacity(0.48))
					
					Text(mapName)
						.font(.system(size: 18, weight: .bold))
						.foregroundStyle(.white)
				}
				
				Spacer()
				
				Text(info.gameStart.formatted(.dateTime.day().month(.wide).year()))
					.font(.system(size: 11.5, weight: .medium))
					.foregroundStyle(.white.opacity(0.48))
			}
			
			VStack(alignment: .leading, spacing: 2) {
				Text(outcome.title)
					.font(.system(size: 13, weight: .heavy))
					.tracking(0.8)
					.foregroundStyle(outcome.color)
				
				if let own = ownTeam, let enemy = enemyTeam {
					HStack(spacing: 8) {
						Text("\(own.roundsWon)")
							.foregroundStyle(.white)
						Text("–")
							.foregroundStyle(.white.opacity(0.35))
						Text("\(enemy.roundsWon)")
							.foregroundStyle(.white.opacity(0.55))
					}
					.font(.system(size: 46, weight: .heavy, design: .rounded))
					.monospacedDigit()
				}
			}
			
			HStack(spacing: 12) {
				Group {
					if let agentAsset, let ui = images[agentAsset] {
						Image(uiImage: ui)
							.resizable()
							.scaledToFill()
					} else if let aid = focusedPlayer.agentID {
						AgentImage.icon(
							aid,
							teamID: focusedPlayer.teamID,
							isOVariant: data.isGauntletOVariant(for: focusedPlayer)
						)
					} else {
						ZStack {
							Color(red: 0.21, green: 0.29, blue: 0.28)
							Image(systemName: "person.fill")
								.font(.system(size: 24))
								.foregroundStyle(.white.opacity(0.55))
						}
					}
				}
				.frame(width: 50, height: 50)
				.background(Color(red: 0.21, green: 0.29, blue: 0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.stroke(.white.opacity(0.10), lineWidth: 1)
				}
				
				VStack(alignment: .leading, spacing: 3) {
					if showRiotID {
						let name = focusedPlayer.resolvedDisplayName(using: resolvedUsers)
						let tag = focusedPlayer.resolvedTagLine(using: resolvedUsers)
						HStack(spacing: 4) {
							Text(name)
								.font(.system(size: 17, weight: .heavy))
								.foregroundStyle(.white)
							if !tag.isEmpty {
								Text("#\(tag)")
									.font(.system(size: 17, weight: .medium))
									.foregroundStyle(.white.opacity(0.45))
							}
						}
						.lineLimit(1)
						.minimumScaleFactor(0.75)
					} else {
						Text("VALORANT Player")
							.font(.system(size: 17, weight: .heavy))
							.foregroundStyle(.white)
					}
					
					if let agentName {
						Text(agentName)
							.font(.system(size: 12.5, weight: .medium))
							.foregroundStyle(.white.opacity(0.58))
					}
				}
				
				Spacer(minLength: 6)
				
				if summary != nil {
					RankInfoView(summary: summary, size: 46, lineWidth: 3.5, shouldShowProgress: true)
				}
			}
			
			if let stats {
				let acsDelta = comparison.map { Int((stats.acs - $0.avgACS).rounded()) }
				let adrDelta = comparison.map { Int((stats.adr - $0.avgADR).rounded()) }
				let hsDelta = comparison.map { Int((stats.hsPercent - $0.avgHSPercent).rounded()) }
				let kastDelta = comparison.map { Int((stats.kastPercent - $0.avgKASTPercent).rounded()) }
				
				HStack(spacing: 0) {
					statColumn(
						value: "\(stats.kills)/\(stats.deaths)/\(stats.assists)",
						label: "K/D/A",
						delta: nil,
						isPercent: false
					)
					statDivider
					statColumn(
						value: "\(Int(stats.acs.rounded()))",
						label: "ACS",
						delta: acsDelta,
						isPercent: false
					)
					statDivider
					statColumn(
						value: "\(Int(stats.adr.rounded()))",
						label: "ADR",
						delta: adrDelta,
						isPercent: false
					)
					statDivider
					statColumn(
						value: "\(Int(stats.hsPercent.rounded())) %",
						label: "HS%",
						delta: hsDelta,
						isPercent: true
					)
					statDivider
					statColumn(
						value: "\(Int(stats.kastPercent.rounded())) %",
						label: "KAST",
						delta: kastDelta,
						isPercent: true
					)
				}
				.padding(.vertical, 13)
				.padding(.horizontal, 4)
				.background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 14, style: .continuous)
						.stroke(.white.opacity(0.08), lineWidth: 1)
				}
			}
			
			if !highlights.isEmpty {
				HStack(spacing: 6) {
					ForEach(Array(highlights)) { item in
						Text(item.label)
							.font(.system(size: 9.5, weight: .bold))
							.tracking(0.5)
							.foregroundStyle(.white.opacity(0.72))
							.padding(.horizontal, 9)
							.padding(.vertical, 5)
							.background(Color.white.opacity(0.065), in: Capsule())
							.overlay {
								Capsule()
									.stroke(.white.opacity(0.09), lineWidth: 1)
							}
							.lineLimit(1)
					}
				}
			}
		}
		.padding(18)
		.padding(.bottom, 12)
		.background { ShareCardBackdrop() }
		.overlay(alignment: .bottomTrailing) {
			ShareCardWatermarkBadge()
				.padding(12)
		}
		.modifier(ShareCardChromeModifier(clipCorners: clipCorners))
	}
	
	private var statDivider: some View {
		Rectangle()
			.fill(.white.opacity(0.09))
			.frame(width: 1, height: 34)
	}
	
	private func statColumn(value: String, label: String, delta: Int?, isPercent: Bool) -> some View {
		VStack(spacing: 3) {
			Text(value)
				.font(.system(size: 14.5, weight: .bold, design: .rounded))
				.monospacedDigit()
				.foregroundStyle(.white)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
			
			Text(label)
				.font(.system(size: 9, weight: .semibold))
				.tracking(0.5)
				.foregroundStyle(.white.opacity(0.45))
			
			if let delta, delta != 0 {
				let sign = delta > 0 ? "+" : ""
				let suffix = isPercent ? " %" : ""
				Text("\(sign)\(delta)\(suffix)")
					.font(.system(size: 9.5, weight: .bold, design: .rounded))
					.monospacedDigit()
					.foregroundStyle(
						delta > 0
							? Color(red: 0.24, green: 0.85, blue: 0.50)
							: Color(red: 0.96, green: 0.34, blue: 0.42)
					)
			} else {
				Text(" ")
					.font(.system(size: 9.5, weight: .bold))
			}
		}
		.frame(maxWidth: .infinity)
	}
	
	@MainActor
	private func prepareAndRender() async {
		isRendering = true
		var loaded = preloadedImages
		var toPreload: [AssetImage] = []
		if let agentAsset, loaded[agentAsset] == nil {
			toPreload.append(agentAsset)
		}
		if let tierIconAsset, loaded[tierIconAsset] == nil {
			toPreload.append(tierIconAsset)
		}
		for asset in toPreload {
			if let cached = imageManager.cachedImage(for: asset, bucket: .icon) {
				loaded[asset] = cached
			} else if let downloaded = await imageManager.awaitImage(for: asset, bucket: .icon) {
				loaded[asset] = downloaded
			}
		}
		preloadedImages = loaded
		
		await Task.yield()
		guard !Task.isCancelled else { return }
		
		let snapshot = matchCardCanvas(images: loaded, clipCorners: false)
			.environment(\.assets, assets)
			.environment(\.configs, configs)
			.environment(\.location, location)
			.environment(\.imageManager, imageManager)
		
		renderedImage = ShareCardRenderer.render(snapshot)
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
