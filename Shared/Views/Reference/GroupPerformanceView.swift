import SwiftUI
import ValorantAPI

// MARK: - Formatting Helpers

private enum GroupFormatters {
	static func percentText(_ fraction: Double) -> String {
		let pct = Int((fraction * Double(100)).rounded())
		return "\(pct)%"
	}
	
	static func kdText(_ kd: Double) -> String {
		String(format: "%.2f", kd)
	}
	
	static func deltaPercentText(_ deltaPoints: Double) -> String {
		let rounded = Int(deltaPoints.rounded())
		if rounded > 0 { return "+\(rounded)%" }
		return "\(rounded)%"
	}
	
	static func deltaColor(_ deltaPoints: Double) -> Color {
		let rounded = Int(deltaPoints.rounded())
		if rounded > 0 { return .valorantBlue }
		if rounded < 0 { return .valorantRed }
		return .secondary
	}
	
	static func winRateColor(_ fraction: Double, decided: Int) -> Color {
		guard decided > 0 else { return .secondary }
		if fraction >= Double(0.55) { return .valorantBlue }
		if fraction <= Double(0.45) { return .valorantRed }
		return .primary
	}
	
	static func rrText(_ rr: Int) -> String {
		rr >= 0 ? "+\(rr) RR" : "\(rr) RR"
	}
	
	static func durationText(_ seconds: TimeInterval) -> String {
		let totalMinutes = Int((seconds / Double(60)).rounded())
		let hours = totalMinutes / 60
		let minutes = totalMinutes % 60
		if hours > 0 {
			return "\(hours)h \(minutes)m"
		}
		return "\(minutes)m"
	}
}

// MARK: - Main Group Performance View

struct GroupPerformanceView: View {
	let userID: User.ID
	var isOwnAccount: Bool = true
	var subjectDisplayName: String? = nil
	var initialMatches: [CompetitiveUpdate] = []
	
	@LocalData var matchList: MatchList?
	@ObservedObject private var cacheStore = GroupPerformanceCacheStore.shared
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	
	@State private var viewMode: GroupViewMode = .players
	@State private var selectedActID: Season.ID? = nil
	@State private var queueScope: GroupPerformanceQueueScope = .allTeamModes
	@State private var sortOrder: GroupPerformanceSort = .matches
	@State private var stackFilter: StackSizeFilter = .all
	@State private var onlyMultiMatchSquads = true
	@State private var searchText = ""
	@State private var showAllFriends = false
	@State private var showAllRandoms = false
	@State private var showAllSquads = false
	
	@State private var report: GroupPerformanceReport?
	@State private var friendHintsSnapshot: [User.ID: GroupFriendHint] = [:]
	@State private var resolvedNamesByID: [User.ID: ResolvedPlayerName] = [:]
	@State private var resolvedNamesVersion = 0
	@State private var attemptedNameFetchIDs: Set<User.ID> = []
	@State private var isResolvingNames = false
	@State private var uncachedMatchIDs: [Match.ID] = []
	@State private var unavailableSyncIDs: Set<Match.ID> = []
	@State private var isSyncingMatches = false
	@State private var syncedProgress: (done: Int, total: Int)?
	@State private var syncTask: Task<Void, Never>?
	@State private var isLoadingOlder = false
	@State private var showingCustomGroupBuilder = false
	@Namespace private var modeNamespace
	
	init(
		userID: User.ID,
		isOwnAccount: Bool = true,
		subjectDisplayName: String? = nil,
		initialMatches: [CompetitiveUpdate] = []
	) {
		self.userID = userID
		self.isOwnAccount = isOwnAccount
		self.subjectDisplayName = subjectDisplayName
		self.initialMatches = initialMatches
		self._matchList = .init(id: userID)
	}
	
	private struct ComputeKey: Equatable {
		var revision: Int
		var selectedActID: Season.ID?
		var queueScope: GroupPerformanceQueueScope
		var sortOrder: GroupPerformanceSort
		var friendHints: [User.ID: GroupFriendHint]
		var resolvedNamesVersion: Int
		var isOwnAccount: Bool
		var matchCount: Int
		var latestMatchID: Match.ID?
	}
	
	private struct SyncCheckKey: Equatable {
		var matchCount: Int
		var latestMatchID: Match.ID?
		var revision: Int
		var isBackfilling: Bool
		var selectedActID: Season.ID?
		var queueScope: GroupPerformanceQueueScope
		var unavailableCount: Int
	}
	
	private struct MatchListSyncKey: Equatable {
		var count: Int
		var firstID: Match.ID?
		var lastID: Match.ID?
	}
	
	private var activeMatches: [CompetitiveUpdate] {
		let loaded = matchList?.matches ?? []
		return loaded.isEmpty ? initialMatches : loaded
	}
	
	private var unresolvedNetworkIDs: [User.ID] {
		guard let report else { return [] }
		var seen: Set<User.ID> = []
		var ids: [User.ID] = []
		
		func collect(_ id: User.ID, hasResolvedName: Bool) {
			guard !hasResolvedName,
				  !attemptedNameFetchIDs.contains(id),
				  resolvedNamesByID[id] == nil,
				  seen.insert(id).inserted else { return }
			ids.append(id)
		}
		
		for player in report.friends {
			collect(player.id, hasResolvedName: player.hasResolvedName)
		}
		for player in report.randoms {
			collect(player.id, hasResolvedName: player.hasResolvedName)
		}
		for mate in report.allSelectableTeammates {
			collect(mate.id, hasResolvedName: mate.hasResolvedName)
		}
		for squad in report.squads {
			for member in squad.members {
				collect(member.id, hasResolvedName: member.hasResolvedName)
			}
		}
		return ids.sorted { $0.description < $1.description }
	}
	
	var body: some View {
		let computeKey = ComputeKey(
			revision: cacheStore.revision,
			selectedActID: selectedActID,
			queueScope: queueScope,
			sortOrder: sortOrder,
			friendHints: isOwnAccount ? friendHintsSnapshot : [:],
			resolvedNamesVersion: resolvedNamesVersion,
			isOwnAccount: isOwnAccount,
			matchCount: activeMatches.count,
			latestMatchID: activeMatches.first?.id
		)
		let syncCheckKey = SyncCheckKey(
			matchCount: activeMatches.count,
			latestMatchID: activeMatches.first?.id,
			revision: cacheStore.revision,
			isBackfilling: cacheStore.isBackfilling,
			selectedActID: selectedActID,
			queueScope: queueScope,
			unavailableCount: unavailableSyncIDs.count
		)
		
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 16) {
				if !isOwnAccount {
					inspectedPlayerBanner
				}
				
				modePickerBar
				
				filterControlsRow
				
				if !uncachedMatchIDs.isEmpty {
					syncMissingMatchesBanner
				}
				
				if let report {
					if report.analyzedMatches == 0 {
						noAnalyzedMatchesCard
					} else if viewMode == .players {
						playersModeContent(report)
					} else {
						groupsModeContent(report)
					}
				} else {
					loadingCard
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Group Performance")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				Button {
					showingCustomGroupBuilder = true
				} label: {
					Image(systemName: "person.3.sequence.fill")
						.foregroundStyle(Color.accentColor)
				}
				.accessibilityLabel("Inspect Custom Group")
				
				Menu {
					Picker("Sort By", selection: $sortOrder) {
						ForEach(GroupPerformanceSort.allCases) { option in
							Label(option.title, systemImage: option.icon)
								.tag(option)
						}
					}
					
					if matchList?.canLoadOlderMatches == true {
						Divider()
						Button {
							loadOlderHistory()
						} label: {
							Label("Load Older Matches", systemImage: "clock.arrow.circlepath")
						}
						.disabled(isLoadingOlder)
					}
				} label: {
					Image(systemName: "arrow.up.arrow.down")
						.foregroundStyle(Color.primary)
				}
			}
		}
		.sheet(isPresented: $showingCustomGroupBuilder) {
			CustomGroupBuilderSheet(
				userID: userID,
				entries: cacheStore.cachedEntriesSnapshot(for: userID),
				rrDeltaByMatchID: buildRRDeltaMap(),
				friendHints: isOwnAccount ? friendHintsSnapshot : [:],
				resolvedNames: resolvedNamesByID,
				isOwnAccount: isOwnAccount,
				selectableTeammates: report?.allSelectableTeammates ?? [],
				selectedActID: selectedActID,
				queueScope: queueScope,
				overallWinRate: report?.overallStats.winRate ?? Double(0)
			)
		}
		.withLocalData($matchList, id: userID, shouldAutoUpdate: true)
		.background {
			if isOwnAccount {
				GroupFriendHintsObserver(friendHints: $friendHintsSnapshot)
			}
		}
		.onAppear {
			recomputeUncachedMatchIDs()
		}
		.task(id: MatchListSyncKey(
			count: activeMatches.count,
			firstID: activeMatches.first?.id,
			lastID: activeMatches.last?.id
		)) {
			let ids = activeMatches.map(\.id)
			await cacheStore.syncMissingMatches(for: userID, matchIDs: ids)
		}
		.task(id: computeKey) {
			await recomputeReport()
		}
		.task(id: unresolvedNetworkIDs) {
			await resolveMissingNamesViaAPI(unresolvedNetworkIDs)
		}
		.onChange(of: syncCheckKey) { _ in
			recomputeUncachedMatchIDs()
		}
		.onDisappear {
			syncTask?.cancel()
			syncTask = nil
		}
	}
	
	// MARK: - Top Controls
	
	private var inspectedPlayerBanner: some View {
		HStack(spacing: 8) {
			Image(systemName: "person.crop.circle.fill")
				.font(.subheadline)
				.foregroundStyle(Color.accentColor)
			
			let label = (subjectDisplayName?.isEmpty == false) ? subjectDisplayName! : "Inspected Player"
			Text("Viewing group stats for \(label)")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.primary)
				.lineLimit(1)
			
			Spacer()
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 9)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	
	private var modePickerBar: some View {
		HStack(spacing: 4) {
			ForEach(GroupViewMode.allCases) { mode in
				let isSelected = (viewMode == mode)
				Button {
					withAnimation(.easeInOut(duration: 0.18)) {
						viewMode = mode
					}
				} label: {
					HStack(spacing: 6) {
						Image(systemName: mode == .players ? "person.2.fill" : "person.3.fill")
							.font(.caption.weight(.semibold))
						Text(mode.title)
							.font(.subheadline.weight(isSelected ? .semibold : .medium))
					}
					.foregroundStyle(isSelected ? .primary : .secondary)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
					.background {
						if isSelected {
							Capsule()
								.fill(Color.secondary.opacity(0.24))
								.matchedGeometryEffect(id: "group_perf_mode_pill", in: modeNamespace)
						}
					}
					.contentShape(Capsule())
				}
				.buttonStyle(.plain)
			}
		}
		.padding(4)
		.background(Color.secondaryGroupedBackground, in: Capsule())
	}
	
	private var filterControlsRow: some View {
		HStack(spacing: 10) {
			Menu {
				Button {
					selectedActID = nil
				} label: {
					HStack {
						Text("All Acts")
						if selectedActID == nil { Image(systemName: "checkmark") }
					}
				}
				
				if let acts = seasons?.collection.actsInOrder.reversed() {
					ForEach(Array(acts.prefix(12))) { act in
						Button {
							selectedActID = act.id
						} label: {
							HStack {
								Text(act.nameWithEpisode)
								if selectedActID == act.id { Image(systemName: "checkmark") }
							}
						}
					}
				}
			} label: {
				filterPill(title: selectedActTitle, systemImage: "calendar")
			}
			
			Menu {
				ForEach(GroupPerformanceQueueScope.allCases) { scope in
					Button {
						queueScope = scope
					} label: {
						HStack {
							Text(scope.title)
							if queueScope == scope { Image(systemName: "checkmark") }
						}
					}
				}
			} label: {
				filterPill(title: queueScope.title, systemImage: "line.3.horizontal.decrease.circle")
			}
			
			Spacer()
		}
	}
	
	private func filterPill(title: String, systemImage: String) -> some View {
		HStack(spacing: 6) {
			Image(systemName: systemImage)
				.font(.caption.weight(.semibold))
				.foregroundStyle(Color.accentColor)
			Text(title)
				.font(.caption.weight(.bold))
				.lineLimit(1)
			Image(systemName: "chevron.down")
				.font(.caption2.weight(.bold))
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
		.foregroundStyle(.primary)
	}
	
	private var selectedActTitle: String {
		if let selectedActID, let act = seasons?.act(selectedActID) {
			return act.nameWithEpisode
		}
		return "All Acts"
	}
	
	private var syncMissingMatchesBanner: some View {
		HStack(spacing: 12) {
			Image(systemName: "arrow.down.circle.fill")
				.font(.title3)
				.foregroundStyle(Color.accentColor)
			
			VStack(alignment: .leading, spacing: 2) {
				if let syncedProgress {
					Text("Downloading match details (\(syncedProgress.done)/\(syncedProgress.total))…")
						.font(.caption.weight(.semibold))
				} else {
					let count = uncachedMatchIDs.count
					Text("Sync \(count) uncached match\(count == 1 ? "" : "es")")
						.font(.caption.weight(.semibold))
					Text("Download match details to discover more repeated players and stacks.")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			
			Spacer()
			
			Button {
				syncUncachedMatches()
			} label: {
				if isSyncingMatches {
					ProgressView()
						.scaleEffect(0.85)
				} else {
					Text("Load")
						.font(.caption.weight(.bold))
						.foregroundStyle(.white)
						.padding(.horizontal, 12)
						.padding(.vertical, 6)
						.background(Color.accentColor, in: Capsule())
				}
			}
			.disabled(isSyncingMatches)
		}
		.padding(12)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	// MARK: - Players Mode
	
	@ViewBuilder
	private func playersModeContent(_ report: GroupPerformanceReport) -> some View {
		overviewHeroCard(report)
		
		searchBar
		
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		let filteredFriends = filterPlayers(report.friends, query: query)
		let filteredRandoms = filterPlayers(report.randoms, query: query)
		
		friendsSection(filteredFriends, isSearching: !query.isEmpty)
		
		randomsSection(filteredRandoms, isSearching: !query.isEmpty)
		
		if filteredFriends.isEmpty && filteredRandoms.isEmpty && !query.isEmpty {
			Text("No players match \"\(query)\".")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity)
				.padding(20)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func overviewHeroCard(_ report: GroupPerformanceReport) -> some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack {
				Text("GROUP OVERVIEW")
					.font(.caption.weight(.bold))
					.tracking(0.8)
					.foregroundStyle(.secondary)
				
				Spacer()
				
				Text("\(report.analyzedMatches) \(report.analyzedMatches == 1 ? "match" : "matches")")
					.font(.caption.weight(.semibold).monospacedDigit())
					.foregroundStyle(.secondary)
					.padding(.horizontal, 9)
					.padding(.vertical, 4)
					.background(Color.tertiaryGroupedBackground, in: Capsule())
			}
			
			HStack(spacing: 10) {
				soloVsGroupTile(
					title: "SOLO",
					stats: report.soloStats,
					accent: .valorantBlue
				)
				
				soloVsGroupTile(
					title: "GROUPED",
					stats: report.groupedStats,
					accent: Color.accentColor
				)
			}
			
			if !report.stackSizes.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 8) {
						ForEach(report.stackSizes) { item in
							Button {
								if item.stackSize >= 2 {
									withAnimation(.easeInOut(duration: 0.18)) {
										stackFilter = StackSizeFilter(rawValue: min(5, item.stackSize)) ?? .all
										viewMode = .groups
									}
								}
							} label: {
								VStack(alignment: .leading, spacing: 3) {
									Text(item.label.uppercased())
										.font(.system(size: 10, weight: .bold))
										.foregroundStyle(.secondary)
									Text(GroupFormatters.percentText(item.stats.winRate))
										.font(.subheadline.weight(.bold).monospacedDigit())
										.foregroundStyle(GroupFormatters.winRateColor(item.stats.winRate, decided: item.stats.decidedMatches))
									Text("\(item.stats.matches)G · \(item.stats.recordText)")
										.font(.system(size: 10).monospacedDigit())
										.foregroundStyle(.secondary)
								}
								.padding(.horizontal, 11)
								.padding(.vertical, 8)
								.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
			
			if let best = report.bestFriendPartner {
				NavigationLink {
					PlayerSynergyDetailView(userID: userID, player: best, isOwnAccount: isOwnAccount)
				} label: {
					HStack(spacing: 10) {
						Image(systemName: "sparkles")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.yellow)
						
						VStack(alignment: .leading, spacing: 1) {
							Text("BEST DUO SYNERGY")
								.font(.system(size: 10, weight: .bold))
								.foregroundStyle(.secondary)
							Text("\(best.displayName) · \(GroupFormatters.percentText(best.stats.winRate)) WR (\(best.stats.recordText))")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.primary)
								.lineLimit(1)
						}
						
						Spacer()
						
						Image(systemName: "chevron.right")
							.font(.caption2.weight(.semibold))
							.foregroundStyle(.secondary)
					}
					.padding(11)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				.buttonStyle(.plain)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.stroke(Color.white.opacity(0.06), lineWidth: 1)
		)
	}
	
	private func soloVsGroupTile(title: String, stats: GroupCombatStats, accent: Color) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(title)
					.font(.system(size: 10, weight: .bold))
					.tracking(0.6)
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(stats.matches)G")
					.font(.caption2.weight(.semibold).monospacedDigit())
					.foregroundStyle(.secondary)
			}
			
			Text(stats.matches > 0 ? GroupFormatters.percentText(stats.winRate) : "—")
				.font(.title2.weight(.bold).monospacedDigit())
				.foregroundStyle(stats.matches > 0 ? accent : .secondary)
			
			ZStack(alignment: .leading) {
				Capsule()
					.fill(Color.secondary.opacity(0.18))
				if stats.decidedMatches > 0 {
					HorizontalFillCapsuleShape(fraction: stats.winRate, minWidth: 4)
						.fill(accent)
				}
			}
			.frame(height: 4)
			
			HStack(spacing: 6) {
				Text(stats.matches > 0 ? stats.recordText : "No matches")
					.lineLimit(1)
				Spacer()
				if stats.matches > 0 {
					Text("K/D \(GroupFormatters.kdText(stats.kd))")
						.lineLimit(1)
				}
			}
			.font(.caption2.monospacedDigit())
			.foregroundStyle(.secondary)
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private var searchBar: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.font(.subheadline)
				.foregroundStyle(.secondary)
			
			TextField("Search players or stacks", text: $searchText)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
			
			if !searchText.isEmpty {
				Button {
					searchText = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(Color.secondaryGroupedBackground, in: Capsule())
	}
	
	@ViewBuilder
	private func friendsSection(_ friends: [PlayerSynergyReport], isSearching: Bool) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(isOwnAccount ? "Friends — \(friends.count)" : "Frequent Party — \(friends.count)")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
					Text(isOwnAccount ? "Riot friends & premade teammates played with 2+ times" : "Premade teammates played with 2+ times")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				Spacer()
			}
			.padding(.horizontal, 4)
			
			if friends.isEmpty {
				if !isSearching {
					emptySectionCard(
						icon: "person.2",
						title: isOwnAccount ? "No Repeated Friends Yet" : "No Repeated Party Mates Yet",
						subtitle: isOwnAccount
							? "Play 2 or more matches with a friend or premade teammate in this filter to see synergy stats."
							: "No premade teammates with 2 or more matches appear in this filter."
					)
				}
			} else {
				let limit = (showAllFriends || isSearching) ? friends.count : 15
				let visible = Array(friends.prefix(limit))
				
				LazyVStack(spacing: 0) {
					ForEach(Array(visible.enumerated()), id: \.element.id) { index, player in
						NavigationLink {
							PlayerSynergyDetailView(userID: userID, player: player, isOwnAccount: isOwnAccount)
						} label: {
							PlayerSynergyRow(player: player, showEncounterSplit: false, isResolvingNames: isResolvingNames)
						}
						.buttonStyle(.plain)
						
						if index < visible.count - 1 || (!isSearching && friends.count > limit) {
							Divider().opacity(0.22).padding(.leading, 68)
						}
					}
					
					if !isSearching && friends.count > limit {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								showAllFriends = true
							}
						} label: {
							HStack {
								Text(isOwnAccount ? "Show All \(friends.count) Friends" : "Show All \(friends.count) Party Mates")
									.font(.subheadline.weight(.semibold))
									.foregroundStyle(Color.accentColor)
								Spacer()
								Image(systemName: "chevron.down")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
							}
							.padding(14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	@ViewBuilder
	private func randomsSection(_ randoms: [PlayerSynergyReport], isSearching: Bool) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text("Random Players — \(randoms.count)")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
					Text("Non-premade players encountered more than once")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				Spacer()
			}
			.padding(.horizontal, 4)
			
			if randoms.isEmpty {
				if !isSearching {
					emptySectionCard(
						icon: "person.wave.2",
						title: "No Repeated Random Players",
						subtitle: "Non-premade teammates or opponents you cross paths with more than once appear here."
					)
				}
			} else {
				let limit = (showAllRandoms || isSearching) ? randoms.count : 15
				let visible = Array(randoms.prefix(limit))
				
				LazyVStack(spacing: 0) {
					ForEach(Array(visible.enumerated()), id: \.element.id) { index, player in
						NavigationLink {
							PlayerSynergyDetailView(userID: userID, player: player, isOwnAccount: isOwnAccount)
						} label: {
							PlayerSynergyRow(player: player, showEncounterSplit: true, isResolvingNames: isResolvingNames)
						}
						.buttonStyle(.plain)
						
						if index < visible.count - 1 || (!isSearching && randoms.count > limit) {
							Divider().opacity(0.22).padding(.leading, 68)
						}
					}
					
					if !isSearching && randoms.count > limit {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								showAllRandoms = true
							}
						} label: {
							HStack {
								Text("Show All \(randoms.count) Random Players")
									.font(.subheadline.weight(.semibold))
									.foregroundStyle(Color.accentColor)
								Spacer()
								Image(systemName: "chevron.down")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
							}
							.padding(14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	// MARK: - Groups Mode
	
	@ViewBuilder
	private func groupsModeContent(_ report: GroupPerformanceReport) -> some View {
		customGroupCalloutButton
		
		stackSizeBreakdownCard(report)
		
		searchBar
		
		stackFilterBar(report)
		
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		let matchingSizeAndSearch = report.squads.filter { squad in
			guard stackFilter.matches(stackSize: squad.stackSize) else { return false }
			if !query.isEmpty {
				return squad.members.contains {
					$0.displayName.localizedCaseInsensitiveContains(query)
				} || squad.stackLabel.localizedCaseInsensitiveContains(query)
			}
			return true
		}
		let multiMatchAvailable = matchingSizeAndSearch.contains { $0.stats.matches >= 2 }
		let filteredSquads = (onlyMultiMatchSquads && multiMatchAvailable && query.isEmpty)
			? matchingSizeAndSearch.filter { $0.stats.matches >= 2 }
			: matchingSizeAndSearch
		
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Squads — \(filteredSquads.count)")
					.font(.subheadline.weight(.semibold))
					.padding(.horizontal, 4)
				
				Spacer()
				
				if multiMatchAvailable && query.isEmpty {
					Button {
						withAnimation(.easeInOut(duration: 0.18)) {
							onlyMultiMatchSquads.toggle()
						}
					} label: {
						Text(onlyMultiMatchSquads ? "2+ Games" : "All Stacks")
							.font(.caption.weight(.semibold))
							.foregroundStyle(Color.accentColor)
							.padding(.horizontal, 10)
							.padding(.vertical, 4)
							.background(Color.secondaryGroupedBackground, in: Capsule())
					}
					.buttonStyle(.plain)
				}
			}
			
			if filteredSquads.isEmpty {
				emptySectionCard(
					icon: "person.3",
					title: "No Matching Groups",
					subtitle: report.squads.isEmpty
						? "Queue in a duo, trio, or full stack to track combined squad performance."
						: "No squads match your current stack filter."
				)
			} else {
				let limit = (showAllSquads || !query.isEmpty) ? filteredSquads.count : 20
				let visible = Array(filteredSquads.prefix(limit))
				
				LazyVStack(spacing: 0) {
					ForEach(Array(visible.enumerated()), id: \.element.id) { index, squad in
						NavigationLink {
							SquadDetailView(userID: userID, squad: squad, isOwnAccount: isOwnAccount)
						} label: {
							SquadRow(squad: squad, isResolvingNames: isResolvingNames)
						}
						.buttonStyle(.plain)
						
						if index < visible.count - 1 || (query.isEmpty && filteredSquads.count > limit) {
							Divider().opacity(0.22).padding(.leading, 14)
						}
					}
					
					if query.isEmpty && filteredSquads.count > limit {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								showAllSquads = true
							}
						} label: {
							HStack {
								Text("Show All \(filteredSquads.count) Squads")
									.font(.subheadline.weight(.semibold))
									.foregroundStyle(Color.accentColor)
								Spacer()
								Image(systemName: "chevron.down")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
							}
							.padding(14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	private var customGroupCalloutButton: some View {
		Button {
			showingCustomGroupBuilder = true
		} label: {
			HStack(spacing: 12) {
				ZStack {
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.fill(Color.accentColor.opacity(0.16))
						.frame(width: 44, height: 44)
					Image(systemName: "person.3.sequence.fill")
						.font(.system(size: 18, weight: .semibold))
						.foregroundStyle(Color.accentColor)
				}
				
				VStack(alignment: .leading, spacing: 2) {
					Text("Inspect Custom Group")
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.primary)
					Text("Pick a specific duo, trio, or full stack to check combined stats")
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(2)
						.multilineTextAlignment(.leading)
				}
				
				Spacer(minLength: 4)
				
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
			)
			.contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.buttonStyle(.plain)
	}
	
	private func stackSizeBreakdownCard(_ report: GroupPerformanceReport) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("BY PARTY SIZE")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
			
			VStack(spacing: 10) {
				ForEach(report.stackSizes) { item in
					let accent: Color = item.stackSize == 1 ? .valorantBlue : Color.accentColor
					VStack(spacing: 5) {
						HStack {
							Text(item.label)
								.font(.subheadline.weight(.semibold))
							Text("\(item.stats.matches)G · \(item.stats.recordText)")
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
							Spacer()
							Text(GroupFormatters.percentText(item.stats.winRate))
								.font(.subheadline.weight(.bold).monospacedDigit())
								.foregroundStyle(GroupFormatters.winRateColor(item.stats.winRate, decided: item.stats.decidedMatches))
						}
						
						ZStack(alignment: .leading) {
							Capsule()
								.fill(Color.secondary.opacity(0.18))
							if item.stats.decidedMatches > 0 {
								HorizontalFillCapsuleShape(fraction: item.stats.winRate, minWidth: 4)
									.fill(accent)
							}
						}
						.frame(height: 5)
						
						HStack(spacing: 12) {
							Text("K/D \(GroupFormatters.kdText(item.stats.kd))")
							Text("ACS \(Int(item.stats.avgACS.rounded()))")
							Text("HS \(Int(item.stats.hsPercent.rounded()))%")
							if item.stats.rankedMatches > 0 {
								Spacer()
								Text(GroupFormatters.rrText(item.stats.netRR))
									.foregroundStyle(item.stats.netRR >= 0 ? Color.valorantBlue : Color.valorantRed)
							}
						}
						.font(.caption2.monospacedDigit())
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, alignment: .leading)
					}
					.padding(10)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func stackFilterBar(_ report: GroupPerformanceReport) -> some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(StackSizeFilter.allCases) { option in
					let selected = (stackFilter == option)
					Button {
						withAnimation(.easeInOut(duration: 0.15)) {
							stackFilter = option
						}
					} label: {
						Text(option.label)
							.font(.caption.weight(.semibold))
							.foregroundStyle(selected ? .white : .primary)
							.padding(.horizontal, 12)
							.padding(.vertical, 7)
							.background(
								selected ? Color.accentColor : Color.secondaryGroupedBackground,
								in: Capsule()
							)
					}
					.buttonStyle(.plain)
				}
			}
		}
	}
	
	// MARK: - Empty / Loading Cards
	
	private var loadingCard: some View {
		VStack(spacing: 12) {
			ProgressView()
			Text("Analyzing group performance…")
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(32)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var noAnalyzedMatchesCard: some View {
		VStack(spacing: 10) {
			Image(systemName: "person.3")
				.font(.system(size: 36, weight: .light))
				.foregroundStyle(.secondary)
			Text("No Analyzed Matches Yet")
				.font(.headline.weight(.bold))
			Text(uncachedMatchIDs.isEmpty
				 ? "No matches match your current Act and mode filters."
				 : "Tap Load above to download match details and analyze repeated teammates.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			
			if selectedActID != nil || queueScope != .allTeamModes {
				Button("Reset Filters") {
					selectedActID = nil
					queueScope = .allTeamModes
				}
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(Color.accentColor)
				.padding(.top, 4)
			}
		}
		.frame(maxWidth: .infinity)
		.padding(24)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func emptySectionCard(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
		VStack(spacing: 8) {
			Image(systemName: icon)
				.font(.title2)
				.foregroundStyle(.secondary)
			Text(title)
				.font(.subheadline.weight(.semibold))
			Text(subtitle)
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(20)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	// MARK: - Data & Helpers
	
	private func filterPlayers(_ players: [PlayerSynergyReport], query: String) -> [PlayerSynergyReport] {
		guard !query.isEmpty else { return players }
		return players.filter {
			$0.displayName.localizedCaseInsensitiveContains(query)
			|| ($0.friendNote?.localizedCaseInsensitiveContains(query) ?? false)
		}
	}
	
	private func buildRRDeltaMap() -> [Match.ID: Int] {
		var map: [Match.ID: Int] = [:]
		for match in activeMatches where match.isRanked {
			map[match.id] = match.ratingEarned
		}
		return map
	}
	
	private func recomputeUncachedMatchIDs() {
		guard !cacheStore.isBackfilling else { return }
		let selectedAct = selectedActID.flatMap { seasons?.act($0) }
		uncachedMatchIDs = activeMatches
			.filter { match in
				guard match.mapID != nil else { return false }
				if let selectedAct, !selectedAct.timeSpan.contains(match.startTime) {
					return false
				}
				guard queueScope.acceptsUpdate(match) else { return false }
				return !cacheStore.hasCachedSummary(for: userID, matchID: match.id)
					&& !unavailableSyncIDs.contains(match.id)
			}
			.map(\.id)
	}
	
	private func recomputeReport() async {
		let entries = cacheStore.cachedEntriesSnapshot(for: userID)
		let rrMap = buildRRDeltaMap()
		let ownAccount = isOwnAccount
		let hints = ownAccount ? friendHintsSnapshot : [:]
		let actFilter = selectedActID
		let scope = queueScope
		let sort = sortOrder
		
		var mergedNames = resolvedNamesByID
		var missingIDs: Set<User.ID> = []
		for entry in entries {
			for participant in entry.participants {
				guard participant.gameName.isEmpty,
					  mergedNames[participant.id] == nil,
					  (hints[participant.id]?.gameName.isEmpty ?? true) else { continue }
				missingIDs.insert(participant.id)
			}
		}
		
		var resolvedNewLocalName = false
		if !missingIDs.isEmpty {
			let cachedUsers = await LocalDataProvider.shared.userManager.cachedObjects(for: missingIDs)
			for user in cachedUsers where !user.gameName.isEmpty {
				mergedNames[user.id] = ResolvedPlayerName(gameName: user.gameName, tagLine: user.tagLine)
				resolvedNewLocalName = true
			}
			
			let history = UsernameHistoryStore.shared.recordsByPlayer
			for id in missingIDs where mergedNames[id] == nil {
				if let latest = history[id]?.last, !latest.gameName.isEmpty {
					mergedNames[id] = ResolvedPlayerName(gameName: latest.gameName, tagLine: latest.tagLine)
					resolvedNewLocalName = true
				}
			}
		}
		
		if resolvedNewLocalName {
			resolvedNamesByID = mergedNames
		}
		let namesSnapshot = mergedNames
		
		let computed = await Task.detached(priority: .userInitiated) {
			GroupPerformanceCalculator.compute(
				entries: entries,
				rrDeltaByMatchID: rrMap,
				friendHints: hints,
				resolvedNames: namesSnapshot,
				isOwnAccount: ownAccount,
				selectedActID: actFilter,
				queueScope: scope,
				sort: sort
			)
		}.value
		
		guard !Task.isCancelled else { return }
		report = computed
	}
	
	private func resolveMissingNamesViaAPI(_ ids: [User.ID]) async {
		let pendingIDs = ids.filter { !attemptedNameFetchIDs.contains($0) && resolvedNamesByID[$0] == nil }
		guard !pendingIDs.isEmpty else { return }
		
		isResolvingNames = true
		defer { isResolvingNames = false }
		
		let chunkSize = 40
		let collector = NameFetchCollector()
		await load { client in
			for start in stride(from: 0, to: pendingIDs.count, by: chunkSize) {
				if Task.isCancelled { break }
				let end = min(start + chunkSize, pendingIDs.count)
				let chunk = Array(pendingIDs[start..<end])
				do {
					let users = try await client.getUsers(for: chunk)
					collector.users.append(contentsOf: users)
					collector.succeededIDs.formUnion(chunk)
				} catch {
					// Ignore per-chunk failure so other chunks still proceed and failed batches can retry later.
				}
			}
		}
		
		guard !Task.isCancelled else { return }
		
		let nonEmptyUsers = collector.users.filter { !$0.gameName.isEmpty }
		if !nonEmptyUsers.isEmpty {
			LocalDataProvider.shared.userManager.store(nonEmptyUsers, asOf: .now)
		}
		
		var didUpdateNames = false
		for user in nonEmptyUsers {
			UsernameHistoryStore.record(user)
			resolvedNamesByID[user.id] = ResolvedPlayerName(gameName: user.gameName, tagLine: user.tagLine)
			didUpdateNames = true
		}
		
		// Mark succeeded chunks only after requests settle so `.task(id: unresolvedNetworkIDs)` does not self-cancel mid-flight.
		attemptedNameFetchIDs.formUnion(collector.succeededIDs)
		if didUpdateNames {
			resolvedNamesVersion += 1
		}
	}
	
	private func syncUncachedMatches() {
		let toFetch = Array(uncachedMatchIDs.prefix(40))
		guard !toFetch.isEmpty, !isSyncingMatches else { return }
		
		syncTask?.cancel()
		syncTask = Task {
			isSyncingMatches = true
			syncedProgress = (0, toFetch.count)
			defer {
				isSyncingMatches = false
				syncedProgress = nil
				syncTask = nil
			}
			
			await load { client in
				let maxConcurrent = 3
				var completedCount = 0
				
				await withTaskGroup(of: (Match.ID, Bool).self) { group in
					var nextIndex = 0
					
					func enqueueNext() {
						guard nextIndex < toFetch.count, !Task.isCancelled else { return }
						let matchID = toFetch[nextIndex]
						nextIndex += 1
						group.addTask {
							try? await client.fetchMatchDetails(for: matchID)
							let loaded = await MainActor.run {
								LocalDataProvider.shared.matchDetailsManager.loadedObject(for: matchID) != nil
							}
							return (matchID, loaded)
						}
					}
					
					for _ in 0..<min(maxConcurrent, toFetch.count) {
						enqueueNext()
					}
					
					while let (matchID, success) = await group.next() {
						completedCount += 1
						if !success {
							unavailableSyncIDs.insert(matchID)
						}
						syncedProgress = (completedCount, toFetch.count)
						enqueueNext()
					}
				}
			}
			
			if !Task.isCancelled {
				let ids = activeMatches.map(\.id)
				await cacheStore.syncMissingMatches(for: userID, matchIDs: ids)
				recomputeUncachedMatchIDs()
			}
		}
	}
	
	private func loadOlderHistory() {
		guard !isLoadingOlder else { return }
		isLoadingOlder = true
		Task {
			defer { isLoadingOlder = false }
			await load { client in
				try? await client.updateMatchList(for: userID) { list in
					try await client.loadOlderMatches(for: &list)
				}
			}
		}
	}
}

// MARK: - Equatable Row Components

private struct PlayerSynergyRow: View, Equatable {
	let player: PlayerSynergyReport
	let showEncounterSplit: Bool
	let isResolvingNames: Bool
	
	static func == (lhs: PlayerSynergyRow, rhs: PlayerSynergyRow) -> Bool {
		lhs.player == rhs.player
			&& lhs.showEncounterSplit == rhs.showEncounterSplit
			&& (lhs.player.hasResolvedName ? true : lhs.isResolvingNames == rhs.isResolvingNames)
	}
	
	private var roleBadge: (text: String, color: Color) {
		if player.isRiotFriend {
			return ("FRIEND", .valorantBlue)
		} else if player.isPremade {
			return ("PARTY", Color.accentColor)
		} else if player.teammateMatches > 0 && player.opponentMatches > 0 {
			return ("MIXED", .orange)
		} else if player.teammateMatches > 0 {
			return ("ALLY", .valorantBlue)
		} else {
			return ("ENEMY", .valorantRed)
		}
	}
	
	private var recordSubtitle: String {
		let base = "\(player.stats.matches)G · \(player.stats.recordText)"
		if showEncounterSplit && player.teammateMatches > 0 && player.opponentMatches > 0 {
			return "\(base) · \(player.teammateMatches)A/\(player.opponentMatches)E"
		} else if !showEncounterSplit && player.opponentMatches > 0 {
			return "\(base) · \(player.opponentMatches) vs"
		}
		return base
	}
	
	var body: some View {
		let stats = player.stats
		let wrColor = GroupFormatters.winRateColor(stats.winRate, decided: stats.decidedMatches)
		let badge = roleBadge
		
		HStack(alignment: .center, spacing: 10) {
			VStack(spacing: 5) {
				GroupAvatarTile(cardID: player.cardID, size: 44)
				
				ZStack(alignment: .leading) {
					Capsule()
						.fill(Color.secondary.opacity(0.18))
					if stats.decidedMatches > 0 {
						HorizontalFillCapsuleShape(fraction: stats.winRate, minWidth: 4)
							.fill(wrColor == .primary ? Color.accentColor : wrColor)
					}
				}
				.frame(width: 44, height: 4)
			}
			.frame(width: 44)
			
			VStack(alignment: .leading, spacing: 4) {
				nameLine
					.frame(maxWidth: .infinity, alignment: .leading)
				
				HStack(spacing: 6) {
					badgePill(badge.text, color: badge.color)
					
					Text(recordSubtitle)
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.minimumScaleFactor(0.85)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				
				HStack(spacing: 4) {
					Text("K/D \(GroupFormatters.kdText(stats.kd))")
						.frame(maxWidth: .infinity, alignment: .leading)
					Text("ACS \(Int(stats.avgACS.rounded()))")
						.frame(maxWidth: .infinity, alignment: .leading)
					Text("HS \(Int(stats.hsPercent.rounded()))%")
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.font(.caption2.monospacedDigit())
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
			}
			
			VStack(alignment: .trailing, spacing: 4) {
				Text(GroupFormatters.percentText(stats.winRate))
					.font(.subheadline.weight(.bold).monospacedDigit())
					.foregroundStyle(wrColor)
					.lineLimit(1)
				
				let roundedDelta = Int(player.winRateDeltaVsOverall.rounded())
				if roundedDelta != 0 {
					let dColor = GroupFormatters.deltaColor(player.winRateDeltaVsOverall)
					Text(GroupFormatters.deltaPercentText(player.winRateDeltaVsOverall))
						.font(.system(size: 10, weight: .bold).monospacedDigit())
						.foregroundStyle(dColor)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(dColor.opacity(0.14), in: Capsule())
						.fixedSize()
				} else {
					Text("0%")
						.font(.system(size: 10, weight: .bold).monospacedDigit())
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.hidden()
				}
				
				Text(stats.rankedMatches > 0 ? GroupFormatters.rrText(stats.netRR) : "— RR")
					.font(.caption2.weight(.semibold).monospacedDigit())
					.foregroundStyle(
						stats.rankedMatches > 0
							? (stats.netRR >= 0 ? Color.valorantBlue : Color.valorantRed)
							: Color.secondary.opacity(0.45)
					)
					.lineLimit(1)
			}
			.frame(width: 64, alignment: .trailing)
			
			Image(systemName: "chevron.right")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.tertiary)
				.frame(width: 8)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 11)
		.contentShape(Rectangle())
	}
	
	@ViewBuilder
	private var nameLine: some View {
		if player.hasResolvedName {
			(Text(player.gameName)
				.font(.subheadline.weight(.bold))
				.foregroundColor(.primary)
			+ Text(player.tagLine.isEmpty ? "" : " #\(player.tagLine)")
				.font(.caption)
				.foregroundColor(.secondary))
			.lineLimit(1)
			.minimumScaleFactor(0.88)
			.truncationMode(.tail)
		} else if isResolvingNames {
			Text("Loading name…")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.lineLimit(1)
		} else {
			Text("Unknown Player")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}
	
	private func badgePill(_ text: String, color: Color) -> some View {
		Text(text)
			.font(.system(size: 9, weight: .heavy))
			.foregroundStyle(color)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.frame(minWidth: 48)
			.background(color.opacity(0.14), in: Capsule())
			.fixedSize()
	}
}

private struct SquadRow: View, Equatable {
	let squad: SquadPerformanceReport
	let isResolvingNames: Bool
	
	static func == (lhs: SquadRow, rhs: SquadRow) -> Bool {
		lhs.squad == rhs.squad
			&& (lhs.squad.members.allSatisfy(\.hasResolvedName) ? true : lhs.isResolvingNames == rhs.isResolvingNames)
	}
	
	private var hasNamedMember: Bool {
		squad.members.contains(where: \.hasResolvedName)
	}
	
	private var squadDisplayNames: String {
		if !hasNamedMember && isResolvingNames {
			return "Loading teammates…"
		}
		return squad.namesSummary
	}
	
	var body: some View {
		let stats = squad.stats
		let wrColor = GroupFormatters.winRateColor(stats.winRate, decided: stats.decidedMatches)
		
		HStack(alignment: .center, spacing: 10) {
			VStack(alignment: .leading, spacing: 6) {
				HStack(spacing: 7) {
					OverlappingSquadAvatars(members: squad.members, size: 26)
					
					Text(squad.stackLabel.uppercased())
						.font(.system(size: 9, weight: .heavy))
						.foregroundStyle(Color.accentColor)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(Color.accentColor.opacity(0.14), in: Capsule())
						.fixedSize()
					
					Text("\(stats.matches)G · \(stats.recordText)")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.minimumScaleFactor(0.85)
				}
				
				Text(squadDisplayNames)
					.font(.subheadline.weight(.bold))
					.foregroundStyle((hasNamedMember || !isResolvingNames) ? .primary : .secondary)
					.lineLimit(2)
					.minimumScaleFactor(0.88)
					.frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
				
				HStack(spacing: 4) {
					Text("K/D \(GroupFormatters.kdText(stats.kd))")
						.frame(maxWidth: .infinity, alignment: .leading)
					Text("ACS \(Int(stats.avgACS.rounded()))")
						.frame(maxWidth: .infinity, alignment: .leading)
					Text("HS \(Int(stats.hsPercent.rounded()))%")
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.font(.caption2.monospacedDigit())
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
			}
			
			VStack(alignment: .trailing, spacing: 4) {
				Text(GroupFormatters.percentText(stats.winRate))
					.font(.subheadline.weight(.bold).monospacedDigit())
					.foregroundStyle(wrColor)
					.lineLimit(1)
				
				Text(stats.rankedMatches > 0 ? GroupFormatters.rrText(stats.netRR) : "— RR")
					.font(.caption2.weight(.semibold).monospacedDigit())
					.foregroundStyle(
						stats.rankedMatches > 0
							? (stats.netRR >= 0 ? Color.valorantBlue : Color.valorantRed)
							: Color.secondary.opacity(0.45)
					)
					.lineLimit(1)
				
				Text(squad.lastPlayed.formatted(.dateTime.day().month(.abbreviated)))
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.frame(width: 64, alignment: .trailing)
			
			Image(systemName: "chevron.right")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.tertiary)
				.frame(width: 8)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.contentShape(Rectangle())
	}
}

// MARK: - Player Synergy Detail View

private struct PlayerSynergyDetailView: View {
	let userID: User.ID
	let player: PlayerSynergyReport
	let isOwnAccount: Bool
	
	@Environment(\.assets) private var assets
	@State private var showAllMatches = false
	
	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 16) {
				heroCard
				
				statsGridCard(
					title: isOwnAccount
						? (player.teammateMatches > 0 ? "YOUR PERFORMANCE TOGETHER" : "YOUR PERFORMANCE IN ENCOUNTERS")
						: (player.teammateMatches > 0 ? "PERFORMANCE TOGETHER" : "ENCOUNTER PERFORMANCE"),
					stats: player.stats
				)
				
				if player.teammateMatches > 0 {
					partnerPerformanceCard
				}
				
				if player.opponentMatches > 0 && player.teammateMatches > 0 {
					opponentComparisonCard
				}
				
				if !player.mapStats.isEmpty {
					mapsCard(player.mapStats)
				}
				
				sharedMatchesCard(player.recentMatches)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle(player.hasResolvedName ? player.gameName : "Player Stats")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private var heroCard: some View {
		let stats = player.stats
		return VStack(alignment: .leading, spacing: 14) {
			HStack(spacing: 12) {
				GroupAvatarTile(cardID: player.cardID, size: 54)
				
				VStack(alignment: .leading, spacing: 4) {
					if player.hasResolvedName {
						(Text(player.gameName)
							.font(.title3.weight(.bold))
							.foregroundColor(.primary)
						+ Text(player.tagLine.isEmpty ? "" : " #\(player.tagLine)")
							.font(.subheadline)
							.foregroundColor(.secondary))
						.lineLimit(1)
						.minimumScaleFactor(0.85)
					} else {
						Text("Unknown Player")
							.font(.title3.weight(.bold))
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					
					HStack(spacing: 6) {
						if isOwnAccount && player.isRiotFriend {
							tagChip("Riot Friend", color: .valorantBlue)
						}
						if player.isPremade {
							tagChip("\(player.partyMatches) Party", color: Color.accentColor)
						}
						if player.opponentMatches > 0 {
							tagChip("\(player.opponentMatches) Enemy", color: .secondary)
						}
					}
				}
				
				Spacer()
				
				if let tier = player.competitiveTier, tier >= 3 {
					CompetitiveTierImage(tier: tier, time: .now)
						.frame(width: 38, height: 38)
				}
			}
			
			if isOwnAccount, let note = player.friendNote, !note.isEmpty {
				HStack(spacing: 6) {
					Image(systemName: "text.quote")
						.font(.caption)
						.foregroundStyle(Color.accentColor)
					Text(note)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
			}
			
			HStack(alignment: .firstTextBaseline) {
				Text(GroupFormatters.percentText(stats.winRate))
					.font(.system(size: 34, weight: .bold).monospacedDigit())
					.foregroundStyle(GroupFormatters.winRateColor(stats.winRate, decided: stats.decidedMatches))
				
				Text(stats.recordText)
					.font(.headline.monospacedDigit())
					.foregroundStyle(.secondary)
				
				Spacer()
				
				let deltaRounded = Int(player.winRateDeltaVsOverall.rounded())
				if deltaRounded != 0 {
					let dColor = GroupFormatters.deltaColor(player.winRateDeltaVsOverall)
					Text("\(GroupFormatters.deltaPercentText(player.winRateDeltaVsOverall)) vs avg")
						.font(.caption.weight(.bold).monospacedDigit())
						.foregroundStyle(dColor)
						.padding(.horizontal, 9)
						.padding(.vertical, 5)
						.background(dColor.opacity(0.14), in: Capsule())
				}
			}
			
			NavigationLink {
				MatchListView(userID: player.id)
			} label: {
				HStack {
					Label("View Full Profile", systemImage: "person.crop.circle")
						.font(.subheadline.weight(.semibold))
					Spacer()
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				.foregroundStyle(Color.accentColor)
				.padding(12)
				.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			}
			.buttonStyle(.plain)
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func tagChip(_ title: String, color: Color) -> some View {
		Text(title)
			.font(.caption2.weight(.semibold))
			.foregroundStyle(color)
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.background(color.opacity(0.14), in: Capsule())
	}
	
	private func statsGridCard(title: String, stats: GroupCombatStats) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(title)
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
			
			LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
				kpiTile("K/D", value: GroupFormatters.kdText(stats.kd))
				kpiTile("ACS", value: "\(Int(stats.avgACS.rounded()))")
				kpiTile("ADR", value: "\(Int(stats.avgADR.rounded()))")
				kpiTile("HS %", value: "\(Int(stats.hsPercent.rounded()))%")
				kpiTile("PLAYTIME", value: GroupFormatters.durationText(stats.totalPlaytime))
				kpiTile(
					"NET RR",
					value: stats.rankedMatches > 0 ? GroupFormatters.rrText(stats.netRR) : "—",
					color: stats.rankedMatches > 0 ? (stats.netRR >= 0 ? .valorantBlue : .valorantRed) : .secondary
				)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func kpiTile(_ label: String, value: String, color: Color = .primary) -> some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(label)
				.font(.system(size: 10, weight: .bold))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.headline.weight(.bold).monospacedDigit())
				.foregroundStyle(color)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(10)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	
	private var partnerPerformanceCard: some View {
		let pStats = player.partnerStats
		return VStack(alignment: .leading, spacing: 12) {
			Text(isOwnAccount ? "THEIR PERFORMANCE WITH YOU" : "TEAMMATE PERFORMANCE")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
			
			HStack(spacing: 10) {
				kpiTile("K/D", value: GroupFormatters.kdText(pStats.kd))
				kpiTile("ACS", value: "\(Int(pStats.avgACS.rounded()))")
				kpiTile("HS %", value: "\(Int(pStats.hsPercent.rounded()))%")
			}
			
			if !player.topPartnerAgents.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 8) {
						ForEach(player.topPartnerAgents.prefix(4)) { agentStat in
							HStack(spacing: 7) {
								AgentImage.icon(agentStat.id, teamID: nil)
									.frame(width: 26, height: 26)
									.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
								VStack(alignment: .leading, spacing: 1) {
									AgentLabel(agent: agentStat.id)
										.font(.caption.weight(.semibold))
									Text("\(agentStat.matches)G · \(GroupFormatters.kdText(agentStat.kd)) K/D")
										.font(.caption2.monospacedDigit())
										.foregroundStyle(.secondary)
								}
							}
							.padding(.horizontal, 10)
							.padding(.vertical, 7)
							.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
						}
					}
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var opponentComparisonCard: some View {
		let opp = player.opponentStats
		return VStack(alignment: .leading, spacing: 10) {
			Text("WHEN PLAYING AGAINST THEM")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
			
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text("\(opp.matches) \(opp.matches == 1 ? "Match" : "Matches") Against")
						.font(.subheadline.weight(.bold))
					Text("\(opp.recordText) · K/D \(GroupFormatters.kdText(opp.kd)) · ACS \(Int(opp.avgACS.rounded()))")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
				Spacer()
				Text(GroupFormatters.percentText(opp.winRate))
					.font(.title3.weight(.bold).monospacedDigit())
					.foregroundStyle(GroupFormatters.winRateColor(opp.winRate, decided: opp.decidedMatches))
			}
			.padding(12)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func mapsCard(_ mapStats: [GroupMapStat]) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("MAPS TOGETHER")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
			
			VStack(spacing: 8) {
				ForEach(mapStats.prefix(8)) { mapStat in
					HStack(spacing: 10) {
						MapImage.splash(mapStat.id, bucket: .icon)
							.aspectRatio(contentMode: .fill)
							.frame(width: 48, height: 32)
							.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
						
						VStack(alignment: .leading, spacing: 2) {
							Text(assets?.maps[mapStat.id]?.displayName ?? mapStat.id.rawValue)
								.font(.subheadline.weight(.semibold))
							Text("\(mapStat.matches)G · \(mapStat.wins)W–\(mapStat.losses)L · K/D \(GroupFormatters.kdText(mapStat.kd))")
								.font(.caption2.monospacedDigit())
								.foregroundStyle(.secondary)
						}
						
						Spacer()
						
						Text(GroupFormatters.percentText(mapStat.winRate))
							.font(.subheadline.weight(.bold).monospacedDigit())
							.foregroundStyle(GroupFormatters.winRateColor(mapStat.winRate, decided: mapStat.wins + mapStat.losses))
					}
					.padding(8)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func sharedMatchesCard(_ matches: [GroupSharedMatchEntry]) -> some View {
		let limit = showAllMatches ? matches.count : 30
		let visible = Array(matches.prefix(limit))
		return VStack(alignment: .leading, spacing: 10) {
			Text("SHARED MATCHES (\(matches.count))")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			LazyVStack(spacing: 0) {
				ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
					NavigationLink {
						MatchDetailsContainer(matchID: entry.id, userID: userID)
					} label: {
						SharedMatchEntryRow(entry: entry, mapName: assets?.maps[entry.mapID]?.displayName ?? entry.mapID.rawValue, queueName: entry.queueID.flatMap { assets?.queues[$0]?.name })
					}
					.buttonStyle(.plain)
					
					if index < visible.count - 1 || matches.count > limit {
						Divider().opacity(0.22).padding(.leading, 62)
					}
				}
				
				if matches.count > limit {
					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							showAllMatches = true
						}
					} label: {
						HStack {
							Text("Show All \(matches.count) Matches")
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(Color.accentColor)
							Spacer()
							Image(systemName: "chevron.down")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
						}
						.padding(14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
}

// MARK: - Squad Detail View

private struct SquadDetailView: View {
	let userID: User.ID
	let squad: SquadPerformanceReport
	let isOwnAccount: Bool
	
	@Environment(\.assets) private var assets
	@State private var showAllMatches = false
	
	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 16) {
				heroCard
				
				kpisCard
				
				rosterCard
				
				if !squad.mapStats.isEmpty {
					mapsCard
				}
				
				matchesCard
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("\(squad.stackLabel) Stats")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private var heroCard: some View {
		let stats = squad.stats
		return VStack(alignment: .leading, spacing: 14) {
			HStack(spacing: 12) {
				OverlappingSquadAvatars(members: squad.members, size: 42)
				
				VStack(alignment: .leading, spacing: 3) {
					HStack(spacing: 6) {
						Text(squad.stackLabel.uppercased())
							.font(.system(size: 10, weight: .heavy))
							.foregroundStyle(Color.accentColor)
							.padding(.horizontal, 7)
							.padding(.vertical, 2)
							.background(Color.accentColor.opacity(0.14), in: Capsule())
						
						if squad.isCustomSuperset {
							Text("INCLUDES SELECTED")
								.font(.system(size: 9, weight: .bold))
								.foregroundStyle(.secondary)
								.padding(.horizontal, 6)
								.padding(.vertical, 2)
								.background(Color.tertiaryGroupedBackground, in: Capsule())
						}
					}
					
					Text(squad.namesSummary)
						.font(.headline.weight(.bold))
						.lineLimit(2)
				}
			}
			
			HStack(alignment: .firstTextBaseline) {
				Text(GroupFormatters.percentText(stats.winRate))
					.font(.system(size: 36, weight: .bold).monospacedDigit())
					.foregroundStyle(GroupFormatters.winRateColor(stats.winRate, decided: stats.decidedMatches))
				
				Text("\(stats.recordText) · \(stats.matches)G")
					.font(.headline.monospacedDigit())
					.foregroundStyle(.secondary)
				
				Spacer()
				
				let deltaRounded = Int(squad.winRateDeltaVsOverall.rounded())
				if deltaRounded != 0 {
					let dColor = GroupFormatters.deltaColor(squad.winRateDeltaVsOverall)
					Text("\(GroupFormatters.deltaPercentText(squad.winRateDeltaVsOverall)) vs avg")
						.font(.caption.weight(.bold).monospacedDigit())
						.foregroundStyle(dColor)
						.padding(.horizontal, 9)
						.padding(.vertical, 5)
						.background(dColor.opacity(0.14), in: Capsule())
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var kpisCard: some View {
		let stats = squad.stats
		return VStack(alignment: .leading, spacing: 12) {
			Text(isOwnAccount ? "YOUR STATS IN THIS GROUP" : "PLAYER STATS IN THIS GROUP")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
			
			LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
				metricBox("K/D", value: GroupFormatters.kdText(stats.kd))
				metricBox("ACS", value: "\(Int(stats.avgACS.rounded()))")
				metricBox("ADR", value: "\(Int(stats.avgADR.rounded()))")
				metricBox("HS %", value: "\(Int(stats.hsPercent.rounded()))%")
				metricBox("PLAYTIME", value: GroupFormatters.durationText(stats.totalPlaytime))
				metricBox(
					"NET RR",
					value: stats.rankedMatches > 0 ? GroupFormatters.rrText(stats.netRR) : "—",
					color: stats.rankedMatches > 0 ? (stats.netRR >= 0 ? .valorantBlue : .valorantRed) : .secondary
				)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func metricBox(_ label: String, value: String, color: Color = .primary) -> some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(label)
				.font(.system(size: 10, weight: .bold))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.headline.weight(.bold).monospacedDigit())
				.foregroundStyle(color)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(10)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	
	private var rosterCard: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("GROUP ROSTER")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
			
			VStack(spacing: 8) {
				ForEach(squad.members) { member in
					NavigationLink {
						MatchListView(userID: member.id)
					} label: {
						HStack(spacing: 10) {
							GroupAvatarTile(cardID: member.cardID, size: 40)
							
							VStack(alignment: .leading, spacing: 2) {
								if member.hasResolvedName {
									(Text(member.gameName)
										.font(.subheadline.weight(.semibold))
										.foregroundColor(.primary)
									+ Text(member.tagLine.isEmpty ? "" : " #\(member.tagLine)")
										.font(.caption)
										.foregroundColor(.secondary))
									.lineLimit(1)
									.minimumScaleFactor(0.88)
								} else {
									Text("Unknown Player")
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(.secondary)
										.lineLimit(1)
								}
								
								Text("K/D \(GroupFormatters.kdText(member.kd)) · ACS \(Int(member.avgACS.rounded())) · HS \(Int(member.hsPercent.rounded()))%")
									.font(.caption2.monospacedDigit())
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							if let agentID = member.topAgentID {
								AgentImage.icon(agentID, teamID: nil)
									.frame(width: 26, height: 26)
									.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
							}
							
							Image(systemName: "chevron.right")
								.font(.caption2.weight(.semibold))
								.foregroundStyle(.tertiary)
						}
						.padding(10)
						.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					}
					.buttonStyle(.plain)
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var mapsCard: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("MAPS WITH THIS GROUP")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
			
			VStack(spacing: 8) {
				ForEach(squad.mapStats.prefix(8)) { mapStat in
					HStack(spacing: 10) {
						MapImage.splash(mapStat.id, bucket: .icon)
							.aspectRatio(contentMode: .fill)
							.frame(width: 48, height: 32)
							.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
						
						VStack(alignment: .leading, spacing: 2) {
							Text(assets?.maps[mapStat.id]?.displayName ?? mapStat.id.rawValue)
								.font(.subheadline.weight(.semibold))
							Text("\(mapStat.matches)G · \(mapStat.wins)W–\(mapStat.losses)L · K/D \(GroupFormatters.kdText(mapStat.kd))")
								.font(.caption2.monospacedDigit())
								.foregroundStyle(.secondary)
						}
						
						Spacer()
						
						Text(GroupFormatters.percentText(mapStat.winRate))
							.font(.subheadline.weight(.bold).monospacedDigit())
							.foregroundStyle(GroupFormatters.winRateColor(mapStat.winRate, decided: mapStat.wins + mapStat.losses))
					}
					.padding(8)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var matchesCard: some View {
		let limit = showAllMatches ? squad.recentMatches.count : 30
		let visible = Array(squad.recentMatches.prefix(limit))
		return VStack(alignment: .leading, spacing: 10) {
			Text("MATCHES (\(squad.recentMatches.count))")
				.font(.caption.weight(.bold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			LazyVStack(spacing: 0) {
				ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
					NavigationLink {
						MatchDetailsContainer(matchID: entry.id, userID: userID)
					} label: {
						SharedMatchEntryRow(
							entry: entry,
							mapName: assets?.maps[entry.mapID]?.displayName ?? entry.mapID.rawValue,
							queueName: entry.queueID.flatMap { assets?.queues[$0]?.name }
						)
					}
					.buttonStyle(.plain)
					
					if index < visible.count - 1 || squad.recentMatches.count > limit {
						Divider().opacity(0.22).padding(.leading, 62)
					}
				}
				
				if squad.recentMatches.count > limit {
					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							showAllMatches = true
						}
					} label: {
						HStack {
							Text("Show All \(squad.recentMatches.count) Matches")
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(Color.accentColor)
							Spacer()
							Image(systemName: "chevron.down")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
						}
						.padding(14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
}

// MARK: - Custom Group Builder Sheet

private struct CustomGroupBuilderSheet: View {
	let userID: User.ID
	let entries: [CachedGroupMatchSummary]
	let rrDeltaByMatchID: [Match.ID: Int]
	let friendHints: [User.ID: GroupFriendHint]
	let resolvedNames: [User.ID: ResolvedPlayerName]
	let isOwnAccount: Bool
	let selectableTeammates: [SquadMemberStat]
	let selectedActID: Season.ID?
	let queueScope: GroupPerformanceQueueScope
	let overallWinRate: Double
	
	@Environment(\.dismiss) private var dismiss
	
	@State private var search = ""
	@State private var selectedIDs: Set<User.ID> = []
	@State private var exactPartyOnly = false
	@State private var computedSquad: SquadPerformanceReport?
	@State private var showingDetail = false
	
	private struct PreviewKey: Equatable {
		var selectedIDs: Set<User.ID>
		var exactPartyOnly: Bool
	}
	
	private var filteredTeammates: [SquadMemberStat] {
		let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !query.isEmpty else { return selectableTeammates }
		return selectableTeammates.filter {
			$0.displayName.localizedCaseInsensitiveContains(query)
		}
	}
	
	private var stackHeadline: String {
		let totalSize = selectedIDs.count + 1
		if selectedIDs.isEmpty {
			return "Select 1–4 teammates"
		}
		return GroupPerformanceCalculator.stackLabel(for: totalSize)
	}
	
	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 14) {
						VStack(alignment: .leading, spacing: 10) {
							Picker("Match Criteria", selection: $exactPartyOnly) {
								Text("Includes Selected").tag(false)
								Text("Exact Stack Only").tag(true)
							}
							.pickerStyle(.segmented)
							
							Text(exactPartyOnly
								 ? (isOwnAccount
									? "Matches where your party consisted of ONLY you and the selected players."
									: "Matches where their party consisted of ONLY them and the selected players.")
								 : (isOwnAccount
									? "Matches where all selected players were in your party (including larger stacks)."
									: "Matches where all selected players were in their party (including larger stacks)."))
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.padding(14)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
						
						HStack(spacing: 8) {
							Image(systemName: "magnifyingglass")
								.font(.subheadline)
								.foregroundStyle(.secondary)
							TextField("Search party teammates", text: $search)
								.textInputAutocapitalization(.never)
								.autocorrectionDisabled()
							if !search.isEmpty {
								Button {
									search = ""
								} label: {
									Image(systemName: "xmark.circle.fill")
										.foregroundStyle(.secondary)
								}
								.buttonStyle(.plain)
							}
						}
						.padding(.horizontal, 12)
						.padding(.vertical, 10)
						.background(Color.secondaryGroupedBackground, in: Capsule())
						
						if filteredTeammates.isEmpty {
							VStack(spacing: 8) {
								Image(systemName: "person.3")
									.font(.title2)
									.foregroundStyle(.secondary)
								Text("No Party Teammates Available")
									.font(.subheadline.weight(.semibold))
								Text("Sync or play matches with friends in a party to build a custom duo, trio, or full stack.")
									.font(.caption)
									.foregroundStyle(.secondary)
									.multilineTextAlignment(.center)
							}
							.frame(maxWidth: .infinity)
							.padding(24)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
						} else {
							LazyVStack(spacing: 0) {
								ForEach(Array(filteredTeammates.enumerated()), id: \.element.id) { index, mate in
									let isSelected = selectedIDs.contains(mate.id)
									let canSelectMore = selectedIDs.count < 4 || isSelected
									Button {
										withAnimation(.easeInOut(duration: 0.14)) {
											if isSelected {
												selectedIDs.remove(mate.id)
											} else if selectedIDs.count < 4 {
												selectedIDs.insert(mate.id)
											}
										}
									} label: {
										HStack(spacing: 12) {
											GroupAvatarTile(cardID: mate.cardID, size: 40)
											
											VStack(alignment: .leading, spacing: 2) {
												if mate.hasResolvedName {
													(Text(mate.gameName)
														.font(.subheadline.weight(.semibold))
														.foregroundColor(.primary)
													+ Text(mate.tagLine.isEmpty ? "" : " #\(mate.tagLine)")
														.font(.caption)
														.foregroundColor(.secondary))
													.lineLimit(1)
													.minimumScaleFactor(0.88)
												} else {
													Text("Unknown Player")
														.font(.subheadline.weight(.semibold))
														.foregroundStyle(.secondary)
														.lineLimit(1)
												}
												Text("\(mate.matches) party \(mate.matches == 1 ? "match" : "matches")")
													.font(.caption)
													.foregroundStyle(.secondary)
											}
											
											Spacer()
											
											Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
												.font(.title3)
												.foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
										}
										.padding(.horizontal, 14)
										.padding(.vertical, 10)
										.opacity(canSelectMore ? 1 : 0.45)
										.contentShape(Rectangle())
									}
									.buttonStyle(.plain)
									.disabled(!canSelectMore)
									
									if index < filteredTeammates.count - 1 {
										Divider().opacity(0.22).padding(.leading, 66)
									}
								}
							}
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
						}
					}
					.padding(16)
				}
				
				bottomPreviewBar
			}
			.background(Color.groupedBackground)
			.navigationDestination(isPresented: $showingDetail) {
				if let computedSquad {
					SquadDetailView(userID: userID, squad: computedSquad, isOwnAccount: isOwnAccount)
				}
			}
			.navigationTitle("Custom Group")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Close") { dismiss() }
				}
				
				if !selectedIDs.isEmpty {
					ToolbarItem(placement: .navigationBarTrailing) {
						Button("Clear") {
							selectedIDs.removeAll()
						}
					}
				}
			}
			.task(id: PreviewKey(selectedIDs: selectedIDs, exactPartyOnly: exactPartyOnly)) {
				await recomputePreview()
			}
		}
	}
	
	private var bottomPreviewBar: some View {
		VStack(spacing: 10) {
			Divider().opacity(0.25)
			
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(stackHeadline)
						.font(.subheadline.weight(.bold))
					if let computedSquad {
						let stats = computedSquad.stats
						Text("\(stats.matches)G · \(stats.recordText) · \(GroupFormatters.percentText(stats.winRate)) WR")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					} else if !selectedIDs.isEmpty {
						Text("No matching games found with this combination.")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else {
						Text(isOwnAccount ? "Choose friends to inspect your combined stats" : "Choose teammates to inspect combined stats")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				
				Spacer()
				
				Button {
					if computedSquad != nil {
						showingDetail = true
					}
				} label: {
					Text("View Stats")
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.white)
						.padding(.horizontal, 16)
						.padding(.vertical, 10)
						.background(
							computedSquad != nil ? Color.accentColor : Color.secondary.opacity(0.35),
							in: Capsule()
						)
				}
				.buttonStyle(.plain)
				.disabled(computedSquad == nil)
			}
			.padding(.horizontal, 16)
			.padding(.bottom, 12)
		}
		.background(.ultraThinMaterial)
	}
	
	private func recomputePreview() async {
		let ids = selectedIDs
		guard !ids.isEmpty else {
			computedSquad = nil
			return
		}
		let exact = exactPartyOnly
		let allEntries = entries
		let rrMap = rrDeltaByMatchID
		let hints = friendHints
		let names = resolvedNames
		let ownAccount = isOwnAccount
		let actID = selectedActID
		let scope = queueScope
		let baseWR = overallWinRate
		
		let result = await Task.detached(priority: .userInitiated) {
			GroupPerformanceCalculator.computeCustomSquad(
				entries: allEntries,
				rrDeltaByMatchID: rrMap,
				friendHints: hints,
				resolvedNames: names,
				isOwnAccount: ownAccount,
				selectedMemberIDs: ids,
				exactPartyOnly: exact,
				selectedActID: actID,
				queueScope: scope,
				overallWinRate: baseWR
			)
		}.value
		
		guard !Task.isCancelled else { return }
		computedSquad = result
	}
}

// MARK: - Shared UI Subviews

private struct SharedMatchEntryRow: View {
	let entry: GroupSharedMatchEntry
	let mapName: String
	let queueName: String?
	
	var body: some View {
		let outcomeColor: Color = entry.tied ? .secondary : (entry.won ? .valorantBlue : .valorantRed)
		
		HStack(spacing: 10) {
			if let agentID = entry.userAgentID {
				AgentImage.icon(agentID, teamID: nil)
					.frame(width: 38, height: 38)
					.background(Color.tertiaryGroupedBackground)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			} else {
				ZStack {
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.fill(Color.tertiaryGroupedBackground)
						.frame(width: 38, height: 38)
					Image(systemName: "map")
						.foregroundStyle(.secondary)
				}
			}
			
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(mapName)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
						.lineLimit(1)
					
					if let queueName {
						Text(queueName)
							.font(.caption2)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					
					if entry.partySize >= 2 {
						Text(GroupPerformanceCalculator.stackLabel(for: entry.partySize))
							.font(.system(size: 9, weight: .bold))
							.foregroundStyle(Color.accentColor)
							.padding(.horizontal, 5)
							.padding(.vertical, 1)
							.background(Color.accentColor.opacity(0.14), in: Capsule())
					}
				}
				
				HStack(spacing: 6) {
					Text("\(entry.userKills)/\(entry.userDeaths)/\(entry.userAssists) · \(entry.userACS) ACS")
						.monospacedDigit()
					if let pk = entry.partnerKills, let pd = entry.partnerDeaths, let pa = entry.partnerAssists {
						Text("· \(entry.wasSameTeam ? "Mate" : "Enemy") \(pk)/\(pd)/\(pa)")
							.monospacedDigit()
					}
				}
				.font(.caption2)
				.foregroundStyle(.secondary)
				.lineLimit(1)
			}
			
			Spacer(minLength: 4)
			
			VStack(alignment: .trailing, spacing: 2) {
				HStack(spacing: 5) {
					Text(entry.scoreText)
						.font(.caption.weight(.bold).monospacedDigit())
						.foregroundStyle(outcomeColor)
					if let rr = entry.rrDelta {
						Text(rr >= 0 ? "+\(rr)" : "\(rr)")
							.font(.caption2.weight(.bold).monospacedDigit())
							.foregroundStyle(rr >= 0 ? Color.valorantBlue : Color.valorantRed)
					}
				}
				
				Text(entry.gameStart.formatted(.dateTime.day().month(.abbreviated)))
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			
			Image(systemName: "chevron.right")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.tertiary)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.contentShape(Rectangle())
	}
}

private struct GroupAvatarTile: View {
	let cardID: PlayerCard.ID?
	let size: CGFloat
	
	var body: some View {
		if let cardID, !cardID.isPseudoNull {
			PlayerCardImage.small(cardID)
				.frame(width: size, height: size)
				.background(Color.tertiaryGroupedBackground)
				.clipShape(RoundedRectangle(cornerRadius: max(7, size * 0.22), style: .continuous))
		} else {
			ZStack {
				RoundedRectangle(cornerRadius: max(7, size * 0.22), style: .continuous)
					.fill(Color.tertiaryGroupedBackground)
					.frame(width: size, height: size)
				Image(systemName: "person.fill")
					.font(.system(size: size * 0.42))
					.foregroundStyle(.secondary)
			}
		}
	}
}

@MainActor
private final class NameFetchCollector {
	var users: [User] = []
	var succeededIDs: Set<User.ID> = []
}

private struct GroupFriendHintsObserver: View {
	@EnvironmentObject private var socialManager: SocialManager
	@Binding var friendHints: [User.ID: GroupFriendHint]
	
	var body: some View {
		Color.clear
			.frame(width: 0, height: 0)
			.onAppear { syncHints() }
			.onChange(of: socialManager.friends) { _ in syncHints() }
	}
	
	private func syncHints() {
		var updated: [User.ID: GroupFriendHint] = [:]
		for friend in socialManager.friends where !friend.isIncomingRequest && !friend.isOutgoingRequest {
			guard let uid = friend.resolvedUserID else { continue }
			updated[uid] = GroupFriendHint(
				userID: uid,
				gameName: friend.gameName,
				tagLine: friend.tagLine,
				cardID: friend.playerCardID,
				competitiveTier: friend.competitiveTier,
				note: friend.note
			)
		}
		if updated != friendHints {
			friendHints = updated
		}
	}
}

private struct OverlappingSquadAvatars: View {
	let members: [SquadMemberStat]
	let size: CGFloat
	
	var body: some View {
		let visible = Array(members.prefix(4))
		HStack(spacing: -(size * 0.28)) {
			ForEach(visible) { member in
				GroupAvatarTile(cardID: member.cardID, size: size)
					.overlay(
						RoundedRectangle(cornerRadius: max(7, size * 0.22), style: .continuous)
							.stroke(Color.secondaryGroupedBackground, lineWidth: 2)
					)
			}
		}
	}
}
