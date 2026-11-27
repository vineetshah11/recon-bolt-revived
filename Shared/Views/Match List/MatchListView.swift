import SwiftUI
import ValorantAPI
import HandyOperators
import UserDefault

struct MatchListView: View {
	let userID: User.ID
	
	@LocalData var user: User?
	@LocalData var matchList: MatchList?
	@LocalData var summary: CareerSummary?
	@LocalData var identity: Player.Identity?
	@State var isEditingFilter = false
	@State private var agentMastery: AgentMastery? = nil
	@State private var showingProfileShare = false
	@State private var masteryFetchTick = 0
	@State private var matchCacheTick = 0
	@State private var cachedDetailsSnapshot: [MatchDetails] = []
	@State private var computedMastery: [AgentMasterySummary] = []
	@State private var computedLatestSession: SessionRecapBuilder.LatestSessionPreview? = nil
	@State private var computedGoalTrajectory: SeasonGoalTrajectory? = nil
	@State private var computedMapRatings: [MapRatingReport] = []
	@State private var lastComputedKey: CareerComputeKey? = nil
	@State private var lastSyncedAccoladesKey: AccoladesSyncKey? = nil
	@State private var lastMasteryFetchDate: Date? = nil
	@ObservedObject private var filterStore = MatchListFilterStore.shared
	
	private struct AccoladesSyncKey: Equatable {
		var userID: User.ID
		var matchIDs: [Match.ID]
	}
	
	@AppStorage("MatchList.isCompact")
	private var isCompactListStyle = false
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.progressTimelineStoreRef) private var progressTimelineStore
	@EnvironmentObject private var goalStore: SeasonGoalStore
	@EnvironmentObject private var accountManager: AccountManager
	
	private var shownMatches: [CompetitiveUpdate] {
		matchList?.matches ?? []
	}
	
	private var currentSeasonProgressKey: String {
		guard let currentAct = seasons?.currentAct(),
			  let info = summary?.competitiveInfo?.inSeason(currentAct.id) else {
			return ""
		}
		return "\(info.competitiveTier)-\(info.adjustedRankedRating)-\(info.leaderboardRank)"
	}
	
	private struct CareerComputeKey: Equatable {
		var userID: User.ID
		var matchIDs: [Match.ID]
		var totalMatchCount: Int
		var cacheTick: Int
		var masteryTick: Int
		var currentActID: Act.ID?
		var summarySeasonCount: Int
		var summaryLatestID: Match.ID?
		var activeGoal: SeasonGoal?
		var assetsVersion: AssetVersion?
	}
	
	var body: some View {
		let currentAct = seasons?.currentAct()
		let prevAct = assets?.seasons.actBefore(currentAct)
		let activeGoal: SeasonGoal? = {
			guard userID == accountManager.activeAccount?.id else { return nil }
			let goal = goalStore.goal(for: userID, actID: currentAct?.id)
			return (goal?.showsOnProfile == true) ? goal : nil
		}()
		let computeKey = CareerComputeKey(
			userID: userID,
			matchIDs: shownMatches.prefix(40).map(\.id),
			totalMatchCount: shownMatches.count,
			cacheTick: matchCacheTick,
			masteryTick: masteryFetchTick,
			currentActID: currentAct?.id,
			summarySeasonCount: summary?.competitiveInfo?.bySeason?.count ?? 0,
			summaryLatestID: summary?.latestUpdate?.id,
			activeGoal: activeGoal,
			assetsVersion: assets?.version
		)
		
		ScrollView {
			LazyVStack(spacing: isCompactListStyle ? 4 : 12) {
				VStack(spacing: 14) {
					VStack(spacing: 0) {
						PlayerIdentityCell(user: user, identity: identity)
						CompetitiveSummaryCell(summary: summary, showThisActFooter: false)
							.padding(.horizontal, 12)
							.buttonStyle(.plain)
					}
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
					.clipped()
					
					CareerSummaryCollapsibleCard(summary: summary)
					
					AgentMasterySummaryBox(summaries: computedMastery, actEndDate: currentAct?.timeSpan.end)
					
					AccoladesSummaryBox(
						userID: userID,
						knownMatchIDs: shownMatches.map(\.id)
					)
					
					MapRatingSummaryBox(
						userID: userID,
						reports: computedMapRatings,
						allMatches: shownMatches,
						detailsSnapshot: cachedDetailsSnapshot
					)
					
					if let activeGoal, let trajectory = computedGoalTrajectory {
						SeasonGoalProgressModule(goal: activeGoal, trajectory: trajectory, currentAct: currentAct)
					}
					
					HStack(spacing: 12) {
						NavigationLink {
							SessionRecapView(
								userID: userID,
								matches: shownMatches,
								detailsByID: Dictionary(cachedDetailsSnapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
							)
						} label: {
							VStack(alignment: .leading, spacing: 6) {
								HStack(spacing: 6) {
									Image(systemName: "clock.badge.checkmark")
										.foregroundStyle(Color.accentColor)
									Text("Session Recap")
										.font(.subheadline.weight(.semibold))
								}
								if let latest = computedLatestSession {
									Text(latest.startTime.formatted(.dateTime.day().month(.abbreviated)))
										.font(.caption)
										.foregroundStyle(.secondary)
									HStack(spacing: 4) {
										Text("\(latest.matchCount) matches")
											.foregroundStyle(.secondary)
										if latest.netRRDelta != 0 {
											Text("• \(latest.netRRDelta > 0 ? "+\(latest.netRRDelta)" : "\(latest.netRRDelta)") RR")
												.foregroundStyle(latest.netRRDelta > 0 ? Color.green : Color.red)
										}
									}
									.font(.caption.monospacedDigit())
								} else {
									Text("Open matches to build")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
							.frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
							.padding(12)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.buttonStyle(.plain)
						
						NavigationLink {
							if let user, let matchList {
								StatisticsContainer(user: user, matchList: matchList)
							}
						} label: {
							VStack(alignment: .leading, spacing: 6) {
								HStack(spacing: 6) {
									Image(systemName: "chart.line.uptrend.xyaxis")
										.foregroundStyle(Color.accentColor)
									Text("View Stats")
										.font(.subheadline.weight(.semibold))
								}
								Text("Win rate, K/D & more")
									.font(.caption)
									.foregroundStyle(.secondary)
								Spacer(minLength: 0)
							}
							.frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
							.padding(12)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.buttonStyle(.plain)
						.disabled(user == nil || matchList == nil)
					}
					
					NavigationLink {
						GroupPerformanceView(
							userID: userID,
							isOwnAccount: userID == accountManager.activeAccount?.id,
							subjectDisplayName: user?.gameName,
							initialMatches: shownMatches
						)
					} label: {
						HStack(spacing: 10) {
							Image(systemName: "person.3.fill")
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(Color.accentColor)
							
							VStack(alignment: .leading, spacing: 2) {
								Text("Group Performance")
									.font(.subheadline.weight(.semibold))
									.foregroundStyle(.primary)
								Text("Friends, party synergy & stack win rates")
									.font(.caption)
									.foregroundStyle(.secondary)
									.lineLimit(1)
							}
							
							Spacer()
							
							Image(systemName: "chevron.right")
								.font(.caption2.weight(.semibold))
								.foregroundStyle(.tertiary)
						}
						.padding(12)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
					}
					.buttonStyle(.plain)
				}
				.padding(.bottom, 6)
				
				Text("Matches", comment: "Match List: section")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.leading, 4)
					.padding(.top, 4)
				
				ForEach(shownMatches) { match in
					MatchCell(
						match: match,
						userID: userID,
						filter: filterStore.filter,
						inList: false,
						isCompact: isCompactListStyle
					)
				}
				
				if matchList?.canLoadOlderMatches == true {
					AsyncButton {
						await updateMatchList(update: ValorantClient.loadOlderMatches)
					} label: {
						Label(
							String(localized: "Load Older Matches", comment: "Match List"),
							systemImage: "ellipsis"
						)
						.font(.subheadline.weight(.medium))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 12)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				if !shouldAnonymize(userID) {
					BookmarkToolbarButton(userID: userID)
				}
				
				Button {
					isEditingFilter = true
				} label: {
					Label(
						String(localized: "Edit Filter", comment: "Match List: accessibility label"),
						systemImage: "line.horizontal.3.decrease.circle"
					)
					.symbolVariant(filterStore.filter.isActive ? .fill : .none)
				}
				
				Button {
					showingProfileShare = true
				} label: {
					Label(
						String(localized: "Share Profile", comment: "Match List: accessibility label"),
						systemImage: "square.and.arrow.up"
					)
				}
			}
		}
		.refreshable { await refresh() }
		.sheet(isPresented: $isEditingFilter) {
			MatchListFilterEditor(filter: $filterStore.filter)
		}
		.sheet(isPresented: $showingProfileShare) {
			ShareProfileCardSheet(
				user: user,
				cardID: identity?.cardID,
				titleID: identity?.titleID,
				accountLevel: identity?.accountLevel ?? 0,
				summary: summary
			)
		}
		.withLocalData($user, id: userID, shouldAutoUpdate: true)
		.withLocalData($matchList, id: userID, shouldAutoUpdate: true)
		.withLocalData($summary, id: userID, shouldAutoUpdate: true)
		.withLocalData($identity, id: userID, shouldAutoUpdate: true)
		.valorantLoadTask(id: userID) { client in
			if let lastMasteryFetchDate, Date.now.timeIntervalSince(lastMasteryFetchDate) < 300 {
				return
			}
			await refreshAgentMastery(using: client)
		}
		.onReceive(
			LocalDataProvider.shared.matchDetailsManager.changePublisher
				.debounce(for: .milliseconds(250), scheduler: RunLoop.main)
		) { _ in
			let topIDs = shownMatches.prefix(40).map(\.id)
			let existingIDs = Set(cachedDetailsSnapshot.map(\.id))
			let manager = LocalDataProvider.shared.matchDetailsManager
			let hasNewRelevantDetails = topIDs.contains { id in
				!existingIDs.contains(id) && manager.loadedObject(for: id) != nil
			}
			guard hasNewRelevantDetails else { return }
			matchCacheTick += 1
			AccoladesCacheStore.shared.ingestLoadedMatches(for: userID, matchIDs: topIDs)
		}
		.task(id: computeKey) {
			guard lastComputedKey != computeKey else { return }
			let topIDs = shownMatches.prefix(40).map(\.id)
			let manager = LocalDataProvider.shared.matchDetailsManager
			var detailsByID: [Match.ID: MatchDetails] = Dictionary(minimumCapacity: topIDs.count)
			var missingDiskIDs: [Match.ID] = []
			for id in topIDs {
				if let loaded = manager.loadedObject(for: id) {
					detailsByID[id] = loaded
				} else {
					missingDiskIDs.append(id)
				}
			}
			if !missingDiskIDs.isEmpty {
				let diskLoaded = await manager.loadFromDiskOnly(for: missingDiskIDs)
				for item in diskLoaded {
					detailsByID[item.id] = item
				}
			}
			let details = topIDs.compactMap { detailsByID[$0] }
			let uid = userID
			let allUpdates = shownMatches
			let masterySnapshot = agentMastery
			let assetsSnapshot = assets
			let seasonsSnapshot = seasons
			let currentActSnapshot = currentAct
			let prevActSnapshot = prevAct
			let goalSnapshot = activeGoal
			let summarySnapshot = summary
			let matchListSnapshot = matchList
			
			let computed = await Task.detached(priority: .userInitiated) {
				PerfMonitor.measure("CareerModules.compute", warnOverMs: 2.0) {
					let detailsMap = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
					let mastery = AgentMasteryCalculator.buildFromRiot(
						masterySnapshot,
						userID: uid,
						matches: details,
						assets: assetsSnapshot,
						contractsDetails: nil,
						currentAct: currentActSnapshot,
						previousAct: prevActSnapshot
					)
					let latestSession = SessionRecapBuilder.latestSessionPreview(
						matches: allUpdates,
						detailsByID: detailsMap
					)
					let trajectory = goalSnapshot.map { goal in
						SeasonGoalStore.compute(
							goal: goal,
							summary: summarySnapshot,
							matchList: matchListSnapshot,
							currentAct: currentActSnapshot,
							seasons: seasonsSnapshot
						)
					}
					let mapRatings = MapRatingCalculator.compute(
						userID: uid,
						matches: details,
						selectedActID: nil,
						seasons: seasonsSnapshot?.collection,
						assets: assetsSnapshot
					)
					return (mastery, latestSession, trajectory, mapRatings)
				}
			}.value
			
			guard !Task.isCancelled else { return }
			lastComputedKey = computeKey
			cachedDetailsSnapshot = details
			computedMastery = computed.0
			computedLatestSession = computed.1
			computedGoalTrajectory = computed.2
			computedMapRatings = computed.3
		}
		.task(id: AccoladesSyncKey(userID: userID, matchIDs: shownMatches.map(\.id))) {
			let syncKey = AccoladesSyncKey(userID: userID, matchIDs: shownMatches.map(\.id))
			guard lastSyncedAccoladesKey != syncKey else { return }
			await AccoladesCacheStore.shared.syncMissingMatches(for: userID, matchIDs: syncKey.matchIDs)
			if !Task.isCancelled {
				lastSyncedAccoladesKey = syncKey
			}
		}
		.onAppear {
			cacheLoadedIdentityToSocial()
			recordProgressIfOwnAccount()
		}
		.onChange(of: identity?.cardID) { _ in
			cacheLoadedIdentityToSocial()
		}
		.onChange(of: identity?.accountLevel) { _ in
			recordProgressIfOwnAccount()
		}
		.onChange(of: cachedDetailsSnapshot.count) { _ in
			cacheLoadedIdentityToSocial()
		}
		.onChange(of: summary?.competitiveInfo?.bySeason?.count ?? 0) { _ in
			cacheLoadedIdentityToSocial()
			recordProgressIfOwnAccount()
		}
		.onChange(of: currentSeasonProgressKey) { _ in
			recordProgressIfOwnAccount()
		}
		.anonymizing(additionally: shouldAnonymize(userID) ? .all : .none)
		.navigationTitle(title)
	}
	
	private func recordProgressIfOwnAccount() {
		guard accountManager.storedAccounts.contains(userID) else { return }
		if let summary {
			progressTimelineStore?.record(summary: summary, seasons: seasons, for: userID)
		}
		if let identity {
			progressTimelineStore?.record(identity: identity, for: userID)
		}
	}
	
	private func cacheLoadedIdentityToSocial() {
		let fallbackMatch = cachedDetailsSnapshot.lazy.compactMap { match -> (Player.Identity, Date)? in
			guard let pIdentity = match.players.first(where: { $0.id == userID })?.identity else { return nil }
			return (pIdentity, match.matchInfo.gameStart)
		}.first
		guard let resolvedIdentity = identity ?? fallbackMatch?.0 else { return }
		let updateTime = identity != nil ? Date() : (fallbackMatch?.1 ?? .distantPast)
		let currentActID = seasons?.currentAct()?.id
		let tier = summary?.competitiveInfo?.inSeason(currentActID)?.competitiveTier
			?? summary?.competitiveInfo?.bySeason?.values.first(where: { $0.competitiveTier >= 3 })?.competitiveTier
		LocalDataProvider.onIdentityAndTierResolved?(resolvedIdentity, tier, updateTime)
	}
	
	var title: Text {
		if !shouldAnonymize(userID), let user {
			return Text(user.gameName)
		} else {
			return Text("Matches", comment: "Match List: title if name unknown/hidden")
		}
	}
	
	func refresh() async {
		async let matchListUpdate: Void = updateMatchList(update: ValorantClient.loadMatches)
		async let summaryUpdate: Void = load {
			try await $0.fetchCareerSummary(for: userID, forceFetch: true)
		}
		async let identityUpdate: Void = load {
			try await $0.fetchIdentity(for: userID, forceFetch: true)
		}
		async let masteryUpdate: Void = load {
			await refreshAgentMastery(using: $0)
		}
		_ = await (matchListUpdate, summaryUpdate, identityUpdate, masteryUpdate)
	}
	
	private func refreshAgentMastery(using client: ValorantClient) async {
		if let fetched = try? await client.getAgentMastery(userID: userID) {
			lastMasteryFetchDate = .now
			if fetched != agentMastery {
				agentMastery = fetched
				masteryFetchTick += 1
			}
		}
	}
	
	func updateMatchList(update: @escaping (ValorantClient) -> (inout MatchList) async throws -> Void) async {
		await load { try await $0.updateMatchList(for: userID, update: update($0)) }
	}
}

extension MatchListView {
	init(userID: User.ID) {
		self.init(
			userID: userID,
			user: .init(id: userID),
			matchList: .init(id: userID),
			summary: .init(id: userID),
			identity: .init(id: userID)
		)
	}
}

extension MatchListFilter: DefaultsValueConvertible {}

private struct BookmarkToolbarButton: View {
	let userID: User.ID
	
	@Environment(\.location) private var location
	@EnvironmentObject private var bookmarkList: BookmarkList
	
	var body: some View {
		Button {
			bookmarkList.toggleBookmark(for: userID, location: location!)
		} label: {
			if bookmarkList.hasBookmark(for: userID) {
				Label(
					String(localized: "Remove Bookmark", comment: "Match List: accessibility label"),
					systemImage: "bookmark.fill"
				)
			} else {
				Label(
					String(localized: "Add Bookmark", comment: "Match List: accessibility label"),
					systemImage: "bookmark"
				)
			}
		}
	}
}

private struct CareerSummaryCollapsibleCard: View {
	let summary: CareerSummary?
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@State private var isExpanded = false
	
	var body: some View {
		let bySeason = summary?.competitiveInfo?.bySeason ?? [:]
		let currentAct = seasons?.currentAct()
		let playedActsCount = bySeason.values.count(where: { $0.gameCount > 0 || $0.competitiveTier > 0 })
		
		let thisActInfo = currentAct.flatMap { bySeason[$0.id] }
		let thisActWins = thisActInfo?.winCountIncludingPlacements ?? 0
		let thisActGames = thisActInfo?.gameCount ?? 0
		
		VStack(alignment: .leading, spacing: 14) {
			HStack {
				Button {
					withAnimation(.easeInOut(duration: 0.2)) {
						isExpanded.toggle()
					}
				} label: {
					HStack(spacing: 8) {
						Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
							.font(.caption.bold())
							.foregroundStyle(Color.accentColor)
						Text("Career Summary")
							.font(.headline)
							.foregroundStyle(.primary)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				
				Spacer()
				
				TransparentNavigationLink {
					if let summary {
						CareerSummaryView(summary: summary)
					}
				} label: {
					HStack(spacing: 6) {
						if playedActsCount > 0 {
							Text("\(playedActsCount) Acts")
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
					}
					.padding(.leading, 8)
				}
				.buttonStyle(.plain)
				.disabled(summary == nil)
			}
			
			if !isExpanded {
				let previewActs: [Act] = (assets?.seasons.actsInOrder ?? [])
					.reversed()
					.filter { act in
						if let current = currentAct {
							return act.timeSpan.start <= current.timeSpan.start
						}
						return act.timeSpan.start <= Date()
					}
					.prefix(3)
					.map { $0 }
				if !previewActs.isEmpty {
					HStack(spacing: 12) {
						ForEach(previewActs) { act in
							actBadgeColumn(act: act, info: bySeason[act.id])
								.frame(maxWidth: .infinity)
						}
					}
				}
				
				if thisActGames > 0 {
					let pct = Double(thisActWins) * Double(100) / Double(thisActGames)
					HStack {
						Text("This Act")
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Spacer()
						Text(String(format: "%.1f %%", pct))
							.font(.subheadline.weight(.bold).monospacedDigit())
							.foregroundStyle(Color.valorantBlue)
						Text("\(thisActWins) / \(thisActGames)")
							.font(.subheadline.monospacedDigit())
							.foregroundStyle(.secondary)
					}
				}
			} else {
				let chartActs: [Act] = Array(
					(assets?.seasons.actsInOrder ?? [])
						.reversed()
						.filter { act in
							if let current = currentAct {
								return act.timeSpan.start <= current.timeSpan.start
							}
							return act.timeSpan.start <= Date()
						}
						.prefix(8)
						.reversed()
				)
				let lifetimePeak = summary?.peakRank(seasons: seasons)
				let maxPlottedTier = chartActs.compactMap { bySeason[$0.id]?.competitiveTier }.filter { $0 >= 3 }.max() ?? 0
				let peakTier = max(lifetimePeak?.rank ?? 0, maxPlottedTier)
				let allTotals = bySeason.values.reduce((wins: 0, games: 0)) { acc, item in
					(acc.wins + item.winCountIncludingPlacements, acc.games + item.gameCount)
				}
				
				Divider()
					.opacity(0.35)
				
				if !chartActs.isEmpty {
					rankTimelineChart(acts: chartActs, bySeason: bySeason, peakTier: peakTier)
				}
				
				if thisActGames > 0 {
					winRateProgressBlock(
						title: "This Act",
						wins: thisActWins,
						games: thisActGames,
						highlightColor: (Double(thisActWins) / Double(thisActGames)) >= Double(0.5)
							? Self.winTealColor
							: .primary
					)
				}
				
				if allTotals.games > 0 {
					winRateProgressBlock(
						title: "All Acts",
						wins: allTotals.wins,
						games: allTotals.games,
						highlightColor: .primary
					)
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func actBadgeColumn(act: Act, info: CareerSummary.SeasonInfo?) -> some View {
		VStack(spacing: 8) {
			Group {
				if let info, info.competitiveTier > 0 {
					RankInfoView(
						summary: nil,
						dataOverride: info,
						size: 44,
						lineWidth: 2.5,
						shouldShowProgress: false
					)
				} else if let info, info.gameCount > 0 {
					ZStack {
						Circle()
							.fill(Color.tertiaryGroupedBackground)
						Circle()
							.stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
						Image(systemName: "questionmark")
							.font(.subheadline.bold())
							.foregroundStyle(.secondary)
					}
					.frame(width: 40, height: 40)
				} else {
					Circle()
						.strokeBorder(
							Color.secondary.opacity(0.35),
							style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
						)
						.frame(width: 40, height: 40)
				}
			}
			.frame(height: 44)
			
			Text(shortActLabel(for: act))
				.font(.system(size: 10, weight: .medium))
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
		}
	}
	
	private static let winTealColor = Color(red: 0.37, green: 0.85, blue: 0.73)
	
	private func rankTimelineChart(
		acts: [Act],
		bySeason: [Season.ID: CareerSummary.SeasonInfo],
		peakTier: Int
	) -> some View {
		let plottedTiers = acts.compactMap { bySeason[$0.id]?.competitiveTier }.filter { $0 >= 3 }
		let minTier = max(3, min(plottedTiers.min() ?? peakTier, peakTier - 3))
		let span = max(1, peakTier - minTier)
		
		return VStack(alignment: .leading, spacing: 6) {
			if peakTier >= 3 {
				Text("Lifetime Peak")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			
			GeometryReader { geo in
				let count = max(1, acts.count)
				let columnWidth = geo.size.width / CGFloat(count)
				let peakLineY: CGFloat = 6
				let rankedTopY: CGFloat = 20
				let rankedBottomY: CGFloat = 74
				let unrankedY: CGFloat = 96
				
				let positions: [CGPoint] = acts.enumerated().map { index, act in
					let x = columnWidth * (CGFloat(index) + 0.5)
					if let info = bySeason[act.id], info.competitiveTier >= 3 {
						let normalized = CGFloat(info.competitiveTier - minTier) / CGFloat(span)
						let y = rankedBottomY - normalized * (rankedBottomY - rankedTopY)
						return CGPoint(x: x, y: y)
					} else {
						return CGPoint(x: x, y: unrankedY)
					}
				}
				
				ZStack(alignment: .topLeading) {
					if peakTier >= 3 {
						Path { path in
							path.move(to: CGPoint(x: 0, y: peakLineY))
							path.addLine(to: CGPoint(x: geo.size.width, y: peakLineY))
						}
						.stroke(
							Color.valorantRed.opacity(0.5),
							style: StrokeStyle(lineWidth: 1, dash: [3, 3])
						)
					}
					
					Path { path in
						for index in 0..<max(0, acts.count - 1) {
							let currentTier = bySeason[acts[index].id]?.competitiveTier ?? 0
							let nextTier = bySeason[acts[index + 1].id]?.competitiveTier ?? 0
							guard currentTier >= 3, nextTier >= 3 else { continue }
							path.move(to: positions[index])
							path.addLine(to: positions[index + 1])
						}
					}
					.stroke(
						Color.secondary.opacity(0.55),
						style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
					)
					
					ForEach(Array(acts.enumerated()), id: \.element.id) { index, act in
						let point = positions[index]
						let info = bySeason[act.id]
						let tier = info?.competitiveTier ?? 0
						
						if tier >= 3 {
							let tierInfo = assets?.seasons.tierInfo(number: tier, in: act.id)
							CompetitiveTierImage(tierInfo: tierInfo)
								.frame(width: 28, height: 28)
								.background(
									Circle()
										.fill(Color.secondaryGroupedBackground)
										.frame(width: 24, height: 24)
								)
								.position(point)
						} else {
							Circle()
								.strokeBorder(
									Color.secondary.opacity(0.45),
									style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
								)
								.frame(width: 16, height: 16)
								.position(point)
						}
					}
				}
			}
			.frame(height: 112)
			
			HStack(spacing: 0) {
				ForEach(acts) { act in
					VStack(spacing: 2) {
						Text(actNumeralLabel(for: act))
							.font(.caption2.weight(.semibold))
							.foregroundStyle(.secondary)
							.lineLimit(1)
						
						let ep = episodeCodeLabel(for: act)
						if !ep.isEmpty {
							Text(ep)
								.font(.caption2)
								.foregroundStyle(Color.secondary.opacity(0.55))
								.lineLimit(1)
						}
					}
					.frame(maxWidth: .infinity)
				}
			}
		}
		.padding(.vertical, 2)
	}
	
	private func winRateProgressBlock(
		title: LocalizedStringKey,
		wins: Int,
		games: Int,
		highlightColor: Color
	) -> some View {
		let ratio = games > 0 ? min(1, max(0, Double(wins) / Double(games))) : Double(0)
		let pct = ratio * Double(100)
		let formattedPct = pct.formatted(.number.precision(.fractionLength(1)))
		return VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(title)
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(formattedPct) %")
					.font(.headline.weight(.bold).monospacedDigit())
					.foregroundStyle(highlightColor)
			}
			
			GeometryReader { geo in
				HStack(spacing: 0) {
					if wins > 0 {
						Rectangle()
							.fill(Self.winTealColor)
							.frame(width: wins == games ? geo.size.width : max(6, geo.size.width * CGFloat(ratio)))
					}
					if wins < games {
						Rectangle()
							.fill(Color.valorantRed.opacity(0.9))
					}
				}
				.clipShape(Capsule())
			}
			.frame(height: 8)
			
			Text("\(wins) / \(games)")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
		}
	}
	
	private func actNumeralLabel(for act: Act) -> String {
		act.name
			.replacingOccurrences(of: "Act ", with: "", options: .caseInsensitive)
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.uppercased()
	}
	
	private func episodeCodeLabel(for act: Act) -> String {
		guard let episode = act.episode else { return "" }
		return episode.name
			.replacingOccurrences(of: "Season 20", with: "V", options: .caseInsensitive)
			.replacingOccurrences(of: "Season ", with: "V", options: .caseInsensitive)
			.replacingOccurrences(of: "Episode ", with: "E", options: .caseInsensitive)
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.uppercased()
	}
	
	private func shortActLabel(for act: Act) -> String {
		if let episode = act.episode {
			let epShort = episode.name
				.replacingOccurrences(of: "Episode ", with: "EP ", options: .caseInsensitive)
				.replacingOccurrences(of: "Season ", with: "V", options: .caseInsensitive)
				.replacingOccurrences(of: "20", with: "")
			return "\(epShort.uppercased()) // \(act.name.uppercased())"
		}
		return act.name.uppercased()
	}
}

#if DEBUG
struct MatchListView_Previews: PreviewProvider {
	static var previews: some View {
		MatchListView(
			userID: PreviewData.userID,
			user: .init(preview: PreviewData.user),
			matchList: .init(preview: PreviewData.matchList),
			summary: .init(preview: PreviewData.summary),
			identity: .init(preview: PreviewData.userIdentity)
		)
		.withToolbar()
		.environmentObject(BookmarkList())
		.environmentObject(SeasonGoalStore())
		.environmentObject(ProgressTimelineStore())
		.environmentObject(AccountManager.mocked)
		.environmentObject(AppSettings())
	}
}
#endif
