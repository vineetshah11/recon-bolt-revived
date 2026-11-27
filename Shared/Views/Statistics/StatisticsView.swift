import SwiftUI
import ValorantAPI
import UserDefault
import HandyOperators

@available(iOS 16.0, *)
struct StatisticsView: View {
	enum DateRangeFilter: String, CaseIterable, Identifiable {
		case allTime = "All Time"
		case last7Days = "Last 7 Days"
		case last30Days = "Last 30 Days"
		case last90Days = "Last 90 Days"
		var id: String { rawValue }
		
		var cutoffDate: Date? {
			switch self {
			case .allTime: return nil
			case .last7Days: return Date().addingTimeInterval(-7 * 24 * 60 * 60)
			case .last30Days: return Date().addingTimeInterval(-30 * 24 * 60 * 60)
			case .last90Days: return Date().addingTimeInterval(-90 * 24 * 60 * 60)
			}
		}
	}
	
	var user: User
	var matchList: MatchList
	
	@State var statistics: Statistics?
	@State var fetchedMatches: [MatchDetails] = []
	@LocalData var summary: CareerSummary?
	@State private var rankedPreview: RankedAnalysis?
	
	init(
		user: User,
		matchList: MatchList,
		statistics: Statistics? = nil
	) {
		self.user = user
		self.matchList = matchList
		self._statistics = .init(initialValue: statistics)
		self._summary = .init(id: user.id)
	}
	
	@UserDefault.State("StatisticsView.excludedQueues")
	var excludedQueues: Set<QueueID> = [
		.deathmatch,
		.gauntlet,
		.spikeRush,
		.custom,
		.escalation,
		.snowballFight
	]
	
	@UserDefault.State("StatisticsView.excludedAgents")
	var excludedAgents: Set<Agent.ID> = []
	
	@State private var excludedMaps: Set<MapID> = []
	@State private var dateRange: DateRangeFilter = .allTime
	@State private var selectedSeasonID: Season.ID? = nil
	@State private var showingFilters = false
	@State private var showingMatchLoader = false
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	
	private var hasActiveFilters: Bool {
		!excludedMaps.isEmpty || dateRange != .allTime || selectedSeasonID != nil || !excludedAgents.isEmpty
	}
	
	private var filteredMatchIDs: Set<Match.ID> {
		Set(filteredMatches.map(\.id))
	}
	
	private var filteredMatches: [MatchDetails] {
		let cutoff = dateRange.cutoffDate
		return fetchedMatches.filter { match in
			guard !excludedQueues.contains(match.matchInfo.queueID ?? .custom) else { return false }
			guard !excludedMaps.contains(match.matchInfo.mapID) else { return false }
			if let cutoff, match.matchInfo.gameStart < cutoff { return false }
			if let selectedSeasonID, match.matchInfo.seasonID != selectedSeasonID { return false }
			guard let player = match.players.firstElement(withID: user.id) else { return false }
			guard player.agentID.map(excludedAgents.contains(_:)) != true else { return false }
			return true
		}
	}
	
	private var filteredUpdatesForChart: [CompetitiveUpdate] {
		let cutoff = dateRange.cutoffDate
		return matchList.matches.filter { upd in
			if let cutoff, upd.startTime < cutoff { return false }
			if let mapID = upd.mapID, excludedMaps.contains(mapID) { return false }
			return true
		}
	}
	
	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 16) {
				if filteredUpdatesForChart.contains(where: \.isRanked) {
					VStack(alignment: .leading, spacing: 8) {
						Text("Rank Rating Changes")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.secondary)
							.padding(.horizontal, 4)
						
						RankRatingChart(matches: filteredUpdatesForChart)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
							.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
					}
				}
				
				if let rankedPreview {
					NavigationLink {
						RankedAnalysisView(
							user: user,
							matchList: matchList,
							summary: summary,
							initialDetails: fetchedMatches
						)
					} label: {
						RankedAnalysisPreviewCard(analysis: rankedPreview)
					}
					.buttonStyle(.plain)
				}
				
				if let statistics {
					overviewCard(for: statistics)
					
					breakdownCard(
						title: "Playtime Breakdown",
						systemImage: "clock",
						showBaseline: true
					) {
						PlaytimeView(statistics: statistics)
					} preview: {
						PlaytimeView.overview(statistics: statistics)
					}
					
					breakdownCard(
						title: "K/D Ratio",
						systemImage: "plus.square.fill"
					) {
						KDRatioView(statistics: statistics)
					} preview: {
						KDRatioView.overview(statistics: statistics)
					}
					
					breakdownCard(
						title: "Hit Distribution",
						systemImage: "scope"
					) {
						HitDistributionView(statistics: statistics)
					} preview: {
						HitDistributionView.overview(statistics: statistics)
					}
					
					breakdownCard(
						title: "Win Rate",
						systemImage: "medal",
						showBaseline: true
					) {
						WinRateView(statistics: statistics)
					} preview: {
						WinRateView.overview(statistics: statistics)
					}
					
					breakdownCard(
						title: "Economy",
						systemImage: "creditcard.fill"
					) {
						EconomyView(statistics: statistics)
					} preview: {
						EconomyView.overview(statistics: statistics)
					}
				} else if fetchedMatches.isEmpty {
					emptyDataCard(
						title: "Download Matches for Statistics",
						subtitle: "Load your match history to analyze Win Rate, K/D Ratio, Economy, Playtime, and Rank Rating."
					)
				} else {
					emptyDataCard(
						title: "No Matches Match Filters",
						subtitle: "Adjust your queue, map, agent, season, or date filters to include more matches."
					)
				}
				
				statusFooter
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Statistics")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				Button {
					showingFilters = true
				} label: {
					Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
						.foregroundStyle(Color.accentColor)
				}
				
				Button {
					showingMatchLoader = true
				} label: {
					Image(systemName: "arrow.down.circle")
						.foregroundStyle(Color.accentColor)
				}
			}
		}
		.sheet(isPresented: $showingFilters) {
			NavigationView {
				StatisticsFilterSheet(
					availableSeasons: availableSeasons,
					excludedQueues: $excludedQueues,
					excludedMaps: $excludedMaps,
					excludedAgents: $excludedAgents,
					dateRange: $dateRange,
					selectedSeasonID: $selectedSeasonID
				)
			}
		}
		.sheet(isPresented: $showingMatchLoader) {
			NavigationView {
				Form {
					LoadingSection(matchList: matchList, fetchedMatches: $fetchedMatches)
				}
				.navigationTitle("Load Matches")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button("Done") { showingMatchLoader = false }
					}
				}
			}
		}
		.task(id: matchList.matches.count) {
			let cached = await LocalDataProvider.shared.matchDetailsManager.cachedObjects(for: matchList.matches.map(\.id))
			if !cached.isEmpty {
				fetchedMatches = cached
			}
		}
		.withLocalData($summary, id: user.id)
		.task(id: rankedPreviewKey) {
			let rankedUpdates = matchList.matches.filter { $0.isRanked && !$0.isDodge }
			guard !rankedUpdates.isEmpty else {
				rankedPreview = nil
				return
			}
			let top5IDs = Array(rankedUpdates.prefix(5).map(\.id))
			let cachedTop5 = await LocalDataProvider.shared.matchDetailsManager.cachedObjects(for: top5IDs)
			var detailsMap = Dictionary(fetchedMatches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
			for match in cachedTop5 {
				detailsMap[match.id] = match
			}
			let userID = user.id
			let updates = matchList.matches
			let summarySnapshot = summary
			let seasonsSnapshot = seasons
			let preview = await Task.detached(priority: .userInitiated) {
				RankedAnalysis(
					userID: userID,
					updates: updates,
					detailsByID: detailsMap,
					summary: summarySnapshot,
					seasons: seasonsSnapshot,
					window: .last5
				)
			}.value
			guard !Task.isCancelled else { return }
			rankedPreview = preview
		}
		.task(id: dataSourceHash) {
			if statistics != nil {
				try? await Task.sleep(for: .milliseconds(80))
				guard !Task.isCancelled else { return }
			}
			let matches = filteredMatches
			if matches.isEmpty {
				statistics = nil
				return
			}
			let updates = matchList.matches
			let userID = user.id
			let stats = await Task.detached(priority: .userInitiated) {
				Statistics(userID: userID, matches: matches, competitiveUpdates: updates)
			}.value
			guard !Task.isCancelled else { return }
			statistics = stats
		}
	}
	
	private var availableSeasons: [Season.ID] {
		let ids = Set(fetchedMatches.map(\.matchInfo.seasonID))
		return ids.sorted { lhs, rhs in
			let lDate = seasons?.act(lhs)?.timeSpan.start ?? Date.distantPast
			let rDate = seasons?.act(rhs)?.timeSpan.start ?? Date.distantPast
			return lDate > rDate
		}
	}
	
	private var rankedPreviewKey: Int {
		(Hasher() <- {
			$0.combine(matchList.matches.prefix(10).map(\.id))
			$0.combine(fetchedMatches.count)
			$0.combine(summary?.competitiveInfo?.bySeason?.count ?? 0)
			$0.combine(seasons?.currentAct()?.id)
		}).finalize()
	}
	
	var dataSourceHash: Int {
		(Hasher() <- {
			$0.combine(fetchedMatches.map(\.id))
			$0.combine(excludedQueues)
			$0.combine(excludedMaps)
			$0.combine(excludedAgents)
			$0.combine(dateRange)
			$0.combine(selectedSeasonID)
		}).finalize()
	}
	
	// MARK: - Cards
	
	private func overviewCard(for statistics: Statistics) -> some View {
		let ov = statistics.overview
		return NavigationLink {
			StatisticsOverviewView(statistics: statistics)
		} label: {
			VStack(alignment: .leading, spacing: 12) {
				HStack(spacing: 8) {
					Image(systemName: "chart.bar.fill")
						.foregroundStyle(Color.accentColor)
					Text("Overview")
						.font(.headline.weight(.bold))
						.foregroundStyle(.primary)
					Spacer()
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				
				LazyVGrid(
					columns: [
						GridItem(.flexible(), spacing: 10),
						GridItem(.flexible(), spacing: 10),
					],
					spacing: 10
				) {
					previewTile(
						icon: "medal",
						title: "Win Rate",
						value: String(format: "%.1f %%", ov.winRate),
						trendUp: ov.wins + ov.losses > 0 ? (ov.winRate >= Double(50)) : nil
					)
					previewTile(
						icon: "plus.square.fill",
						title: "K/D",
						value: String(format: "%.2f", ov.kdRatio),
						trendUp: ov.totalKills + ov.totalDeaths > 0 ? (ov.kdRatio >= Double(1.0)) : nil
					)
					previewTile(
						icon: "scope",
						title: "HS %",
						value: String(format: "%.1f %%", ov.hsPercent),
						trendUp: nil
					)
					previewTile(
						icon: "chart.line.uptrend.xyaxis",
						title: "Ø RR",
						value: ov.avgRRChange.map { String(format: "%+.1f", $0) } ?? "—",
						trendUp: ov.avgRRChange.map { $0 >= 0 }
					)
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.buttonStyle(.plain)
	}
	
	private func previewTile(icon: String, title: String, value: String, trendUp: Bool?) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 5) {
				Image(systemName: icon)
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
				Text(title)
					.font(.caption.weight(.medium))
					.foregroundStyle(.secondary)
			}
			
			HStack(alignment: .firstTextBaseline) {
				Text(value)
					.font(.title3.weight(.bold).monospacedDigit())
					.foregroundStyle(.primary)
				Spacer()
				if let trendUp {
					Image(systemName: trendUp ? "arrow.up" : "arrow.down")
						.font(.caption.weight(.bold))
						.foregroundStyle(trendUp ? Color.green : Color.valorantRed)
				}
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func breakdownCard<Destination: View, Preview: View>(
		title: LocalizedStringKey,
		systemImage: String,
		showBaseline: Bool = false,
		@ViewBuilder destination: @escaping () -> Destination,
		@ViewBuilder preview: @escaping () -> Preview
	) -> some View {
		NavigationLink {
			destination()
		} label: {
			VStack(alignment: .leading, spacing: 12) {
				HStack(spacing: 8) {
					Image(systemName: systemImage)
						.foregroundStyle(Color.accentColor)
					Text(title)
						.font(.headline.weight(.bold))
						.foregroundStyle(.primary)
					Spacer()
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				
				preview()
					.chartLegend(.hidden)
					.chartXAxis(.hidden)
					.chartYAxis(.hidden)
					.overlay(alignment: .bottom) {
						if showBaseline {
							Color.primary.opacity(0.1).frame(height: 1)
						}
					}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.buttonStyle(.plain)
	}
	
	private func emptyDataCard(title: String, subtitle: String) -> some View {
		VStack(spacing: 12) {
			Image(systemName: "chart.bar.xaxis")
				.font(.system(size: 38, weight: .light))
				.foregroundStyle(Color.accentColor)
			Text(title)
				.font(.headline.weight(.bold))
			Text(subtitle)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			Button {
				showingMatchLoader = true
			} label: {
				Text("Load Matches")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.white)
					.padding(.horizontal, 18)
					.padding(.vertical, 10)
					.background(Color.accentColor, in: Capsule())
			}
			.buttonStyle(.plain)
		}
		.frame(maxWidth: .infinity)
		.padding(24)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	@ViewBuilder
	private var statusFooter: some View {
		HStack {
			if let statistics {
				let allowed = statistics.matches.count
				let excluded = fetchedMatches.count - allowed
				Text("Analyzing \(allowed) match(es)\(excluded > 0 ? " (\(excluded) filtered)" : "")")
			} else {
				Text("\(fetchedMatches.count) of \(matchList.matches.count) cached matches")
			}
			Spacer()
			Button("Manage Matches") {
				showingMatchLoader = true
			}
			.foregroundStyle(Color.accentColor)
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 4)
	}
	
	// MARK: - Filter Sheet
	
	private struct StatisticsFilterSheet: View {
		var availableSeasons: [Season.ID]
		@Binding var excludedQueues: Set<QueueID>
		@Binding var excludedMaps: Set<MapID>
		@Binding var excludedAgents: Set<Agent.ID>
		@Binding var dateRange: DateRangeFilter
		@Binding var selectedSeasonID: Season.ID?
		
		@Environment(\.dismiss) private var dismiss
		@Environment(\.assets) private var assets
		@Environment(\.seasons) private var seasons
		
		var body: some View {
			Form {
				Section("Date Range") {
					Picker("Period", selection: $dateRange) {
						ForEach(DateRangeFilter.allCases) { option in
							Text(option.rawValue).tag(option)
						}
					}
				}
				
				if !availableSeasons.isEmpty {
					Section("Act / Season") {
						Picker("Season", selection: $selectedSeasonID) {
							Text("All Acts").tag(nil as Season.ID?)
							ForEach(availableSeasons, id: \.self) { seasonID in
								let act = seasons?.act(seasonID)
								Text(act?.nameWithEpisode ?? act?.name ?? "Unknown Act")
									.tag(seasonID as Season.ID?)
							}
						}
					}
				}
				
				Section("Filters") {
					FilterPicker(
						title: String(localized: "Queues", comment: "Statistics filter: button"),
						allAllowedLabel: String(localized: "Any Queue", comment: "Statistics filter: shown when every queue is allowed"),
						allowedLabel: { String(localized: "\($0) queues selected", comment: "Statistics Filter: shown when not every queue is allowed") },
						allowAllButton: String(localized: "Allow All Queues", defaultValue: "Allow All", comment: "Statistics Filter: button to allow all queues"),
						allowNoneButton: String(localized: "Exclude All Queues", defaultValue: "Exclude All", comment: "Statistics Filter: button to exclude all queues"),
						excluded: $excludedQueues
					)
					
					FilterPicker(
						title: String(localized: "Maps", comment: "Statistics filter: button"),
						allAllowedLabel: String(localized: "Any Map"),
						allowedLabel: { "\($0) maps selected" },
						allowAllButton: String(localized: "Allow All"),
						allowNoneButton: String(localized: "Exclude All"),
						excluded: $excludedMaps
					)
					
					FilterPicker(
						title: String(localized: "Agents", comment: "Statistics filter: button"),
						allAllowedLabel: String(localized: "Any Agent", comment: "Statistics filter: shown when every agent is allowed"),
						allowedLabel: { String(localized: "\($0) agents selected", comment: "Statistics Filter: shown when not every agent is allowed") },
						allowAllButton: String(localized: "Allow All Agents", defaultValue: "Allow All", comment: "Statistics Filter: button to allow all agents"),
						allowNoneButton: String(localized: "Exclude All Agents", defaultValue: "Exclude All", comment: "Statistics Filter: button to exclude all agents"),
						excluded: $excludedAgents
					)
				}
				
				Section {
					Button("Reset All Filters", role: .destructive) {
						excludedMaps = []
						excludedAgents = []
						dateRange = .allTime
						selectedSeasonID = nil
					}
				}
			}
			.navigationTitle("Filter Statistics")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
	}
	
	private struct FilterPicker<ID: FilterableID>: View {
		var title: String
		var allAllowedLabel: String
		var allowedLabel: (Int) -> String
		var allowAllButton: String
		var allowNoneButton: String
		
		@Binding var excluded: Set<ID>
		
		@Environment(\.assets) private var assets
		
		var body: some View {
			let all = ID.knownIDs(assets: assets)
			let allowed = Set(all).subtracting(excluded)
			NavigationLink {
				List(all, id: \.self) { id in
					listRow(for: id)
				}
				.navigationTitle(title)
				.toolbar {
					ToolbarItemGroup(placement: .bottomBar) {
						Button(allowAllButton) { excluded = [] }
							.disabled(excluded.isEmpty)
						
						Button(allowNoneButton) { excluded = Set(all) }
							.disabled(allowed.isEmpty)
					}
				}
			} label: {
				HStack {
					Text(title)
					Spacer()
					Group {
						if excluded.isEmpty {
							Text(allAllowedLabel)
						} else if let allowed = allowed.onlyElement() {
							allowed.label
						} else {
							Text(allowedLabel(allowed.count))
						}
					}
					.foregroundStyle(.secondary)
				}
			}
		}
		
		func listRow(for id: ID) -> some View {
			Button {
				excluded.formSymmetricDifference([id])
			} label: {
				HStack {
					let isAllowed = !excluded.contains(id)
					
					id.icon
						.saturation(isAllowed ? 1 : 0)
						.frame(height: 40)
					
					id.label
						.tint(.primary)
						.opacity(isAllowed ? 1 : 0.5)
					
					Spacer()
					
					Image(systemName: "checkmark")
						.opacity(isAllowed ? 1 : 0)
				}
			}
		}
	}
}

extension QueueID: DefaultsValueConvertible {}

extension Agent.ID: FilterableID {
	static func knownIDs(assets: AssetCollection?) -> [Self] {
		assets?.agents
			.sorted {
				let lhsName = $0.key == .abilityDraftAgent ? "Gauntlet Robot" : $0.value.displayName
				let rhsName = $1.key == .abilityDraftAgent ? "Gauntlet Robot" : $1.value.displayName
				return lhsName < rhsName
			}
			.map(\.key) ?? []
	}
	
	var icon: some View {
		AgentImage.icon(self, teamID: nil)
	}
	
	var label: some View {
		AgentLabel(agent: self)
	}
}

#if DEBUG
@available(iOS 16.0, *)
struct StatisticsView_Previews: PreviewProvider {
	static var previews: some View {
		StatisticsView(
			user: PreviewData.user, matchList: PreviewData.matchList,
			statistics: PreviewData.statistics
		)
		.withToolbar()
	}
}
#endif
