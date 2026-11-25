import SwiftUI
import ValorantAPI

struct CareerSummaryView: View {
	let summary: CareerSummary
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	
	@State private var selectedQueue: QueueID = .competitive
	@State private var hasInitializedQueue = false
	@State private var expandedPreviousActs: Set<Act.ID> = []
	@State private var isCurrentTriangleExpanded = false
	
	private static let queueOrder: [QueueID] = [
		.competitive,
		.swiftplay,
		.unrated,
		.premier,
		.teamDeathmatch,
		.spikeRush,
		.deathmatch,
		.escalation,
		.gauntlet,
		.knockout,
		.allRandomOneSite,
		.skirmish2v2,
		.replication,
		.retake,
		.snowballFight,
	]
	private static let orderedQueues = Set(queueOrder)
	private static let winGreen = Color(red: 0.24, green: 0.82, blue: 0.45)
	
	private struct EarnedRankEntry: Identifiable {
		let id: String
		let baseTier: CompetitiveTier
		let count: Int
	}
	
	private var availableQueues: [QueueID] {
		let nonEmpty = summary.infoByQueue.compactMap { queue, info -> QueueID? in
			guard let bySeason = info.bySeason, !bySeason.isEmpty else { return nil }
			return queue
		}
		
		let filtered = nonEmpty.filter { queue in
			queue != .custom && queue.rawValue != "seeding"
		}
		let source = filtered.isEmpty ? nonEmpty : filtered
		
		var ordered: [QueueID] = []
		for q in Self.queueOrder where source.contains(q) {
			ordered.append(q)
		}
		
		let extras = source.filter { q in
			!Self.orderedQueues.contains(q) && !isOtherModesQueue(q)
		}
		.sorted {
			queueDisplayName($0).localizedCaseInsensitiveCompare(queueDisplayName($1)) == .orderedAscending
		}
		ordered.append(contentsOf: extras)
		
		let otherQueues = source.filter { isOtherModesQueue($0) }
			.sorted { $0.rawValue < $1.rawValue }
		ordered.append(contentsOf: otherQueues)
		
		return ordered
	}
	
	var body: some View {
		let queues = availableQueues
		let activeQueue = queues.contains(selectedQueue) ? selectedQueue : (queues.first ?? .competitive)
		let queueInfo = summary.infoByQueue[activeQueue]
		let currentAct = seasons?.currentAct()
		
		VStack(spacing: 0) {
			if !queues.isEmpty {
				queueTabBar(queues: queues, activeQueue: activeQueue)
			}
			
			ScrollView {
				VStack(spacing: 14) {
					if let currentAct {
						currentActBanner(currentAct)
					}
					
					currentActSection(
						activeQueue: activeQueue,
						queueInfo: queueInfo,
						currentAct: currentAct
					)
					
					if let allTime = allTimeTotals(for: queueInfo), allTime.games > 0 {
						allTimeStatsCard(
							wins: allTime.wins,
							games: allTime.games,
							actCount: allTime.acts
						)
					}
					
					let prevActs = previousActsList(for: queueInfo, excluding: currentAct?.id)
					if !prevActs.isEmpty {
						previousActsCard(
							activeQueue: activeQueue,
							items: prevActs
						)
					}
					
					if isOtherModesQueue(activeQueue) {
						Text("Riot counts these modes together: All Random One Site · Deathmatch · Escalation · Knockout · Replication · Retake · Skirmish: 2v2 · Snowball Fight · Spike Rush · Team Deathmatch.")
							.font(.footnote)
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 4)
							.padding(.top, 2)
					}
				}
				.padding(.horizontal, 16)
				.padding(.top, 8)
				.padding(.bottom, 20)
			}
		}
		.background(Color.groupedBackground.ignoresSafeArea())
		.navigationTitle("Career Summary")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear {
			guard !hasInitializedQueue else { return }
			hasInitializedQueue = true
			if queues.contains(.competitive) {
				selectedQueue = .competitive
			} else if let first = queues.first {
				selectedQueue = first
			}
		}
	}
	
	// MARK: - Queue Pill Bar
	
	private func queueTabBar(queues: [QueueID], activeQueue: QueueID) -> some View {
		ScrollViewReader { proxy in
			HStack(spacing: 4) {
				if queues.count > 3, let first = queues.first, activeQueue != first {
					Button {
						if let idx = queues.firstIndex(of: activeQueue), idx > 0 {
							let target = queues[idx - 1]
							withAnimation(.easeInOut(duration: 0.2)) {
								selectedQueue = target
								proxy.scrollTo(target, anchor: .center)
							}
						}
					} label: {
						chevronCap(systemName: "chevron.left")
					}
					.buttonStyle(.plain)
				}
				
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 6) {
						ForEach(queues, id: \.self) { queue in
							let isSelected = (queue == activeQueue)
							Button {
								withAnimation(.easeInOut(duration: 0.18)) {
									selectedQueue = queue
									proxy.scrollTo(queue, anchor: .center)
								}
							} label: {
								Text(queueDisplayName(queue))
									.font(.subheadline.weight(isSelected ? .semibold : .medium))
									.foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
									.padding(.horizontal, 14)
									.padding(.vertical, 7)
									.background {
										if isSelected {
											Capsule()
												.fill(Color.secondaryGroupedBackground)
												.overlay {
													Capsule()
														.stroke(Color.primary.opacity(0.14), lineWidth: 0.75)
												}
										}
									}
									.contentShape(Capsule())
							}
							.buttonStyle(.plain)
							.id(queue)
						}
					}
					.padding(.horizontal, 4)
				}
				
				if queues.count > 3, let last = queues.last, activeQueue != last {
					Button {
						if let idx = queues.firstIndex(of: activeQueue), idx + 1 < queues.count {
							let target = queues[idx + 1]
							withAnimation(.easeInOut(duration: 0.2)) {
								selectedQueue = target
								proxy.scrollTo(target, anchor: .center)
							}
						}
					} label: {
						chevronCap(systemName: "chevron.right")
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
		}
	}
	
	private func chevronCap(systemName: String) -> some View {
		ZStack {
			Circle()
				.fill(Color.secondaryGroupedBackground)
				.frame(width: 26, height: 26)
			Image(systemName: systemName)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
		}
	}
	
	// MARK: - Current Act
	
	private func currentActBanner(_ act: Act) -> some View {
		HStack {
			Text(formatActTitle(act))
				.font(.subheadline.weight(.bold))
			Spacer()
			Text("Current")
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 13)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	@ViewBuilder
	private func currentActSection(
		activeQueue: QueueID,
		queueInfo: CareerSummary.QueueInfo?,
		currentAct: Act?
	) -> some View {
		let currentInfo = currentAct.flatMap { queueInfo?.inSeason($0.id) }
		let isCompetitive = (activeQueue == .competitive)
		let hasCurrentActivity = (currentInfo?.gameCount ?? 0) > 0
			|| (isCompetitive && (currentInfo?.competitiveTier ?? 0) > 0)
		
		VStack(alignment: .leading, spacing: 14) {
			if let currentInfo, hasCurrentActivity, let currentAct {
				if isCompetitive {
					competitiveRankBlock(for: currentInfo, in: currentAct, isCurrentAct: true)
					
					let earnedRanks = computeTotalRanksEarned()
					if !earnedRanks.isEmpty {
						totalRanksEarnedBlock(earnedRanks)
					}
				}
				
				VStack(alignment: .leading, spacing: 8) {
					Text("Performance")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.secondary)
						.padding(.horizontal, 2)
					
					statsTwoColumnCard(
						wins: currentInfo.winCountIncludingPlacements,
						games: currentInfo.gameCount
					)
				}
			} else {
				let actTitle = currentAct.map(formatActTitle) ?? "this act"
				VStack(spacing: 10) {
					Image(systemName: "desktopcomputer")
						.font(.system(size: 36))
						.foregroundStyle(.secondary)
						.padding(.bottom, 2)
					
					Text("No Games Played")
						.font(.headline.weight(.bold))
					
					Text("This player hasn't played any matches in this queue during \(actTitle).")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 12)
				.padding(.horizontal, 8)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
	
	private func competitiveRankBlock(
		for info: CareerSummary.SeasonInfo,
		in act: Act,
		isCurrentAct: Bool
	) -> some View {
		let tierInfo = assets?.seasons.tierInfo(number: info.competitiveTier, in: act.id)
			?? seasons?.tierInfo(number: info.competitiveTier, in: act)
		
		return VStack(alignment: .leading, spacing: 8) {
			Text("Rank")
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 2)
			
			HStack(spacing: 0) {
				VStack(spacing: 8) {
					RankInfoView(summary: nil, dataOverride: info, size: 78, lineWidth: 4.5)
					
					Text((tierInfo?.name ?? "Unranked").uppercased())
						.font(.subheadline.weight(.bold))
						.lineLimit(1)
						.minimumScaleFactor(0.8)
					
					if info.competitiveTier >= 3 {
						HStack(spacing: 4) {
							Text("\(info.adjustedRankedRating)")
								.fontWeight(.semibold)
							Text("RR")
								.foregroundStyle(.secondary)
						}
						.font(.subheadline.monospacedDigit())
					}
					
					if info.leaderboardRank > 0 {
						LeaderboardRankView(rank: info.leaderboardRank, tierInfo: tierInfo)
					}
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 16)
				.padding(.horizontal, 8)
				
				Rectangle()
					.fill(Color.secondary.opacity(0.22))
					.frame(width: 1)
					.padding(.vertical, 18)
				
				VStack(spacing: 8) {
					if isCurrentAct {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								isCurrentTriangleExpanded.toggle()
							}
						} label: {
							VStack(spacing: 8) {
								ActRankView(
									seasonInfo: info,
									isIcon: false,
									isShowingAllWins: isCurrentTriangleExpanded
								)
								.frame(height: 112)
								
								Text(isCurrentTriangleExpanded ? "Tap to collapse" : "Tap to expand")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					} else {
						ExpandableActRankView(seasonInfo: info)
							.frame(height: 112)
						
						Text("Tap to expand")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 16)
				.padding(.horizontal, 8)
			}
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	// MARK: - Total Ranks Earned (Rank Legacy)
	
	private func totalRanksEarnedBlock(_ entries: [EarnedRankEntry]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Total Ranks Earned")
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
				Spacer()
				Text("1 per 3 Acts")
					.font(.caption2)
					.foregroundStyle(.secondary.opacity(0.7))
			}
			.padding(.horizontal, 2)
			
			Group {
				if entries.count <= 4 {
					HStack(spacing: 22) {
						ForEach(entries) { entry in
							earnedRankBadge(entry)
						}
					}
					.frame(maxWidth: .infinity)
				} else {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 20) {
							ForEach(entries) { entry in
								earnedRankBadge(entry)
							}
						}
						.padding(.horizontal, 12)
					}
				}
			}
			.padding(.vertical, 14)
			.padding(.horizontal, 10)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	private func earnedRankBadge(_ entry: EarnedRankEntry) -> some View {
		VStack(spacing: 6) {
			ZStack(alignment: .bottomTrailing) {
				CompetitiveTierImage(tierInfo: entry.baseTier)
					.frame(width: 44, height: 44)
				
				Text("\(entry.count)")
					.font(.caption2.bold().monospacedDigit())
					.foregroundStyle(.black)
					.padding(.horizontal, 5)
					.padding(.vertical, 1)
					.background(Color.white, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
					.offset(x: 4, y: 2)
			}
			
			Text(entry.baseTier.division.uppercased())
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}
	
	private func computeTotalRanksEarned() -> [EarnedRankEntry] {
		guard let assets, let bySeason = summary.competitiveInfo?.bySeason else { return [] }
		let acts = assets.seasons.actsInOrder
		
		// Partition acts chronologically into 3-act windows per Episode/Season (Acts I–III, IV–VI, etc.).
		struct WindowKey: Hashable {
			let episodeID: Season.ID
			let windowIndex: Int
		}
		var actsPerEpisodeCount: [Season.ID: Int] = [:]
		var windowActs: [WindowKey: [Act]] = [:]
		var orderedWindows: [WindowKey] = []
		
		for act in acts {
			guard let episodeID = act.episode?.id else { continue }
			let idxInEpisode = actsPerEpisodeCount[episodeID, default: 0]
			actsPerEpisodeCount[episodeID] = idxInEpisode + 1
			let key = WindowKey(episodeID: episodeID, windowIndex: idxInEpisode / 3)
			if windowActs[key] == nil {
				orderedWindows.append(key)
			}
			windowActs[key, default: []].append(act)
		}
		
		var countByDivision: [CompetitiveTier.DivisionID: Int] = [:]
		for key in orderedWindows {
			guard let block = windowActs[key] else { continue }
			var bestInWindow: RankSnapshot?
			for act in block {
				guard let info = bySeason[act.id] else { continue }
				let highestWinTier = info.winsByTier?
					.filter { $0.value > 0 }
					.keys
					.max() ?? 0
				let actPeak = max(info.competitiveTier, info.actRank, highestWinTier)
				guard actPeak >= 3 else { continue }
				let snapshot = RankSnapshot(season: act.id, rank: actPeak)
				if let currentBest = bestInWindow {
					if snapshot > currentBest {
						bestInWindow = snapshot
					}
				} else {
					bestInWindow = snapshot
				}
			}
			
			if let bestInWindow,
			   let tierInfo = assets.seasons.tierInfo(bestInWindow) {
				countByDivision[tierInfo.divisionID, default: 0] += 1
			}
		}
		
		guard !countByDivision.isEmpty else { return [] }
		
		let referenceCollection = seasons?.currentTiers()
			?? assets.seasons.competitiveTiers.values.max(by: { $0.tiers.count < $1.tiers.count })
		guard let tiers = referenceCollection?.tiers.values else { return [] }
		
		var baseTierByDivision: [CompetitiveTier.DivisionID: CompetitiveTier] = [:]
		for tier in tiers where tier.number >= 3 {
			if let existing = baseTierByDivision[tier.divisionID] {
				if tier.number < existing.number {
					baseTierByDivision[tier.divisionID] = tier
				}
			} else {
				baseTierByDivision[tier.divisionID] = tier
			}
		}
		
		return countByDivision.compactMap { divisionID, count -> EarnedRankEntry? in
			guard count > 0, let baseTier = baseTierByDivision[divisionID] else { return nil }
			return EarnedRankEntry(
				id: divisionID.rawValue,
				baseTier: baseTier,
				count: count
			)
		}
		.sorted { $0.baseTier.number < $1.baseTier.number }
	}
	
	// MARK: - All-Time Stats
	
	private func allTimeStatsCard(wins: Int, games: Int, actCount: Int) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Text("All-Time Stats")
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(actCount) \(actCount == 1 ? "Act" : "Acts")")
					.font(.subheadline.monospacedDigit())
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 2)
			
			statsTwoColumnCard(wins: wins, games: games)
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
	
	// MARK: - Previous Acts
	
	private func previousActsCard(
		activeQueue: QueueID,
		items: [(act: Act, info: CareerSummary.SeasonInfo)]
	) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Previous Acts")
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(items.count)")
					.font(.subheadline.monospacedDigit())
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 2)
			
			VStack(spacing: 10) {
				ForEach(items, id: \.act.id) { item in
					let isExpanded = expandedPreviousActs.contains(item.act.id)
					let pct = winPercentage(wins: item.info.winCountIncludingPlacements, games: item.info.gameCount)
					let formattedPct = pct.formatted(.number.precision(.fractionLength(1)))
					
					VStack(alignment: .leading, spacing: 12) {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								if isExpanded {
									expandedPreviousActs.remove(item.act.id)
								} else {
									expandedPreviousActs.insert(item.act.id)
								}
							}
						} label: {
							HStack(spacing: 10) {
								Text(formatActTitle(item.act))
									.font(.subheadline.weight(.bold))
									.foregroundStyle(.primary)
								
								Spacer()
								
								Text("\(formattedPct) %")
									.font(.subheadline.weight(.semibold).monospacedDigit())
									.foregroundStyle(pct >= Double(50) ? Self.winGreen : .primary)
								
								Image(systemName: "chevron.down")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
									.rotationEffect(.degrees(isExpanded ? 180 : 0))
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						
						if isExpanded {
							if activeQueue == .competitive && item.info.competitiveTier > 0 {
								competitiveRankBlock(for: item.info, in: item.act, isCurrentAct: false)
							}
							
							statsTwoColumnCard(
								wins: item.info.winCountIncludingPlacements,
								games: item.info.gameCount,
								cardBackground: Color.secondaryGroupedBackground.opacity(0.65)
							)
						} else if activeQueue == .competitive && item.info.competitiveTier > 0 {
							HStack {
								RankInfoView(
									summary: nil,
									dataOverride: item.info,
									size: 46,
									lineWidth: 3
								)
								
								Spacer()
								
								ActRankView(
									seasonInfo: item.info,
									isIcon: true,
									isShowingAllWins: false
								)
								.frame(width: 48, height: 48)
							}
							.padding(.top, 2)
						}
					}
					.padding(14)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
	
	// MARK: - Shared 2-Column Stats Card
	
	private func statsTwoColumnCard(
		wins: Int,
		games: Int,
		cardBackground: Color = Color.tertiaryGroupedBackground
	) -> some View {
		let pct = winPercentage(wins: wins, games: games)
		let formattedPct = pct.formatted(.number.precision(.fractionLength(1)))
		
		return HStack(spacing: 0) {
			VStack(spacing: 4) {
				Text("\(formattedPct) %")
					.font(.title3.weight(.bold).monospacedDigit())
					.foregroundStyle(pct >= Double(50) ? Self.winGreen : .primary)
				
				Text("Win Rate")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity)
			
			Rectangle()
				.fill(Color.secondary.opacity(0.22))
				.frame(width: 1, height: 34)
			
			VStack(spacing: 4) {
				HStack(spacing: 0) {
					Text("\(wins)")
						.foregroundStyle(Self.winGreen)
					Text(" / \(games)")
						.foregroundStyle(.primary)
				}
				.font(.title3.weight(.bold).monospacedDigit())
				
				Text("Wins / Games")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity)
		}
		.padding(.vertical, 14)
		.background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: - Helpers
	
	private func isOtherModesQueue(_ queue: QueueID) -> Bool {
		queue.rawValue.isEmpty || queue.rawValue == "other"
	}
	
	private func queueDisplayName(_ queue: QueueID) -> String {
		if isOtherModesQueue(queue) {
			return "Other Modes"
		}
		if let name = assets?.queues[queue]?.name, !name.isEmpty {
			return name
		}
		return queue.rawValue
			.replacingOccurrences(of: "_", with: " ")
			.capitalized
	}
	
	private func formatActTitle(_ act: Act) -> String {
		let actPart = act.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
		guard let episode = act.episode else { return actPart }
		let episodeShort = episode.name
			.replacingOccurrences(of: "Season 20", with: "V", options: .caseInsensitive)
			.replacingOccurrences(of: "Season ", with: "V", options: .caseInsensitive)
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.uppercased()
		return "\(episodeShort) – \(actPart)"
	}
	
	private func winPercentage(wins: Int, games: Int) -> Double {
		guard games > 0 else { return Double(0) }
		return Double(wins) * Double(100) / Double(games)
	}
	
	private func allTimeTotals(for queueInfo: CareerSummary.QueueInfo?) -> (wins: Int, games: Int, acts: Int)? {
		guard let bySeason = queueInfo?.bySeason else { return nil }
		var wins = 0
		var games = 0
		var acts = 0
		for info in bySeason.values where info.gameCount > 0 || info.competitiveTier > 0 {
			wins += info.winCountIncludingPlacements
			games += info.gameCount
			acts += 1
		}
		return (wins, games, acts)
	}
	
	private func previousActsList(
		for queueInfo: CareerSummary.QueueInfo?,
		excluding currentActID: Act.ID?
	) -> [(act: Act, info: CareerSummary.SeasonInfo)] {
		let acts = assets?.seasons.actsInOrder.reversed() ?? []
		return acts.compactMap { act in
			if let currentActID, act.id == currentActID {
				return nil
			}
			guard let info = queueInfo?.bySeason?[act.id],
				  info.gameCount > 0 || info.competitiveTier > 0 else {
				return nil
			}
			return (act: act, info: info)
		}
	}
}

struct ExpandableActRankView: View {
	let seasonInfo: CareerSummary.SeasonInfo
	
	@State var isExpanded = false
	
	var body: some View {
		ActRankView(seasonInfo: seasonInfo, isIcon: false, isShowingAllWins: isExpanded)
			.onTapGesture {
				withAnimation(.easeInOut(duration: 0.2)) {
					isExpanded.toggle()
				}
			}
	}
}

#if DEBUG
struct CareerSummaryView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			CareerSummaryView(summary: PreviewData.strangeSummary)
		}
		.withToolbar()
		
		NavigationStack {
			CareerSummaryView(summary: PreviewData.summary)
		}
		.withToolbar()
	}
}
#endif
