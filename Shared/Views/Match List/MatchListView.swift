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
	@State private var isShowingShareSheet = false
	@State private var agentMastery: AgentMastery? = nil
	@UserDefault.State("MatchListView.filter") var filter = MatchListFilter()
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	@Environment(\.location) private var location
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@EnvironmentObject private var bookmarkList: BookmarkList
	@EnvironmentObject private var goalStore: SeasonGoalStore
	@EnvironmentObject private var progressTimelineStore: ProgressTimelineStore
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var settings: AppSettings
	@EnvironmentObject private var socialManager: SocialManager
	
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
	
	private var cachedMatchDetails: [MatchDetails] {
		shownMatches.prefix(40).compactMap {
			LocalDataProvider.shared.matchDetailsManager.loadedObject(for: $0.id)
		}
	}
	
	private var detailsByID: [Match.ID: MatchDetails] {
		Dictionary(uniqueKeysWithValues: cachedMatchDetails.map { ($0.id, $0) })
	}
	
	var body: some View {
		let currentAct = seasons?.currentAct()
		let prevAct = assets?.seasons.actBefore(currentAct)
		let mastery = AgentMasteryCalculator.buildFromRiot(
			agentMastery,
			userID: userID,
			matches: cachedMatchDetails,
			assets: assets,
			contractsDetails: nil,
			currentAct: currentAct,
			previousAct: prevAct
		)
		let accolades = AccoladesCalculator.compute(
			userID: userID,
			matches: cachedMatchDetails,
			act: currentAct,
			seasons: seasons
		)
		let sessions = SessionRecapBuilder.buildSessions(
			userID: userID,
			matches: shownMatches,
			detailsByID: detailsByID
		)
		
		ScrollView {
			LazyVStack(spacing: 14) {
				VStack(spacing: 0) {
					PlayerIdentityCell(user: user, identity: identity)
					CompetitiveSummaryCell(summary: summary, showThisActFooter: false)
						.padding(.horizontal, 12)
						.buttonStyle(.plain)
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				.clipped()
				
				CareerSummaryCollapsibleCard(summary: summary)
				
				AgentMasterySummaryBox(summaries: mastery, actEndDate: currentAct?.timeSpan.end)
				
				AccoladesSummaryBox(userID: userID, matches: cachedMatchDetails, report: accolades)
				
				if userID == accountManager.activeAccount?.id,
				   let activeGoal = goalStore.goal(for: userID, actID: currentAct?.id),
				   activeGoal.showsOnProfile {
					let trajectory = SeasonGoalStore.compute(
						goal: activeGoal,
						summary: summary,
						matchList: matchList,
						currentAct: currentAct,
						seasons: seasons
					)
					SeasonGoalProgressModule(goal: activeGoal, trajectory: trajectory, currentAct: currentAct)
				}
				
				HStack(spacing: 12) {
					NavigationLink {
						SessionRecapView(userID: userID, sessions: sessions)
					} label: {
						VStack(alignment: .leading, spacing: 6) {
							HStack(spacing: 6) {
								Image(systemName: "clock.badge.checkmark")
									.foregroundStyle(Color.accentColor)
								Text("Session Recap")
									.font(.subheadline.weight(.semibold))
							}
							if let latest = sessions.first {
								Text(latest.startTime.formatted(.dateTime.day().month(.abbreviated)))
									.font(.caption)
									.foregroundStyle(.secondary)
								HStack(spacing: 4) {
									Text("\(latest.items.count) matches")
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
				
				VStack(alignment: .leading, spacing: 10) {
					Text("Matches", comment: "Match List: section")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.secondary)
						.padding(.leading, 4)
						.padding(.top, 4)
					
					LazyVStack(spacing: settings.isCompactListStyle ? 4 : 12) {
						ForEach(shownMatches) { match in
							MatchCell(
								match: match,
								userID: userID,
								filter: filter,
								inList: false,
								isCompact: settings.isCompactListStyle
							)
						}
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
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				if !shouldAnonymize(userID) {
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
				
				Button {
					isEditingFilter = true
				} label: {
					Label(
						String(localized: "Edit Filter", comment: "Match List: accessibility label"),
						systemImage: "line.horizontal.3.decrease.circle"
					)
					.symbolVariant(filter.isActive ? .fill : .none)
				}
				
				if !shouldAnonymize(userID) {
					Button {
						isShowingShareSheet = true
					} label: {
						Label(
							String(localized: "Share Profile", comment: "Match List: accessibility label"),
							systemImage: "square.and.arrow.up"
						)
					}
				}
			}
		}
		.refreshable { await refresh() }
		.sheet(isPresented: $isEditingFilter) {
			MatchListFilterEditor(filter: $filter)
		}
		.sheet(isPresented: $isShowingShareSheet) {
			ProfileShareSheet(user: user, identity: identity, summary: summary)
		}
		.withLocalData($user, id: userID, shouldAutoUpdate: true)
		.withLocalData($matchList, id: userID, shouldAutoUpdate: true)
		.withLocalData($summary, id: userID, shouldAutoUpdate: true)
		.withLocalData($identity, id: userID, shouldAutoUpdate: true)
		.valorantLoadTask(id: userID) { client in
			agentMastery = try? await client.getAgentMastery(userID: userID)
		}
		.onAppear {
			cacheLoadedIdentityToSocial()
			recordProgressIfOwnAccount()
		}
		.onChange(of: identity?.cardID) { _ in
			cacheLoadedIdentityToSocial()
		}
		.onChange(of: cachedMatchDetails.count) { _ in
			cacheLoadedIdentityToSocial()
		}
		.onChange(of: identity?.accountLevel) { _ in
			recordProgressIfOwnAccount()
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
	
	private func cacheLoadedIdentityToSocial() {
		let fallbackMatch = cachedMatchDetails.lazy.compactMap { match -> (Player.Identity, Date)? in
			guard let pIdentity = match.players.first(where: { $0.id == userID })?.identity else { return nil }
			return (pIdentity, match.matchInfo.gameStart)
		}.first
		guard let resolvedIdentity = identity ?? fallbackMatch?.0 else { return }
		let updateTime = identity != nil ? Date() : (fallbackMatch?.1 ?? .distantPast)
		let currentActID = seasons?.currentAct()?.id
		let tier = summary?.competitiveInfo?.inSeason(currentActID)?.competitiveTier
			?? summary?.competitiveInfo?.bySeason?.values.first(where: { $0.competitiveTier >= 3 })?.competitiveTier
		socialManager.cacheIdentity(resolvedIdentity, competitiveTier: tier, asOf: updateTime)
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
			agentMastery = try? await $0.getAgentMastery(userID: userID)
		}
		_ = await (matchListUpdate, summaryUpdate, identityUpdate, masteryUpdate)
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

private struct CareerSummaryCollapsibleCard: View {
	let summary: CareerSummary?
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@State private var isExpanded = false
	
	var body: some View {
		let bySeason = summary?.competitiveInfo?.bySeason ?? [:]
		let currentAct = seasons?.currentAct()
		let pastOrCurrentActs: [Act] = (assets?.seasons.actsInOrder ?? [])
			.filter { act in
				if let current = currentAct {
					return act.timeSpan.start <= current.timeSpan.start
				}
				return act.timeSpan.start <= Date()
			}
			.reversed()
		let previewActs = Array(pastOrCurrentActs.prefix(3))
		let chartActs = Array(pastOrCurrentActs.prefix(8).reversed())
		let playedActsCount = bySeason.values.filter { $0.gameCount > 0 || $0.competitiveTier > 0 }.count
		let lifetimePeak = summary?.peakRank(seasons: seasons)
		let maxPlottedTier = chartActs.compactMap { bySeason[$0.id]?.competitiveTier }.filter { $0 >= 3 }.max() ?? 0
		let peakTier = max(lifetimePeak?.rank ?? 0, maxPlottedTier)
		
		let thisActInfo = currentAct.flatMap { bySeason[$0.id] }
		let thisActWins = thisActInfo?.winCountIncludingPlacements ?? 0
		let thisActGames = thisActInfo?.gameCount ?? 0
		
		let allTotals = bySeason.values.reduce((wins: 0, games: 0)) { acc, item in
			(acc.wins + item.winCountIncludingPlacements, acc.games + item.gameCount)
		}
		
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

// MARK: - Share Profile Sheet

private struct ProfileShareSheet: View {
	let user: User?
	let identity: Player.Identity?
	let summary: CareerSummary?
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.dismiss) private var dismiss
	
	@State private var renderedImage: UIImage?
	@State private var showsRiotID = true
	@State private var didCopy = false
	
	private static let cardWidth: CGFloat = 360
	private let accent = Color(red: 0.518, green: 0.176, blue: 0.784)
	
	var body: some View {
		NavigationView {
			ScrollView {
				VStack(spacing: 16) {
					cardPreview
					
					showRiotIDToggle
					
					if let renderedImage {
						ShareLink(
							item: Image(uiImage: renderedImage),
							preview: SharePreview("Player Profile", image: Image(uiImage: renderedImage))
						) {
							shareButtonLabel("Share Profile Card")
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
			.navigationTitle("Share Profile")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
		.task(id: showsRiotID) {
			await renderCard()
		}
	}
	
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
				.overlay { ProgressView("Rendering profile…") }
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
		.tint(accent)
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func shareButtonLabel(_ title: String) -> some View {
		Label(title, systemImage: "square.and.arrow.up")
			.font(.headline)
			.foregroundStyle(.white)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 15)
			.background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func copyButtonLabel(_ title: String, systemImage: String) -> some View {
		Label(title, systemImage: systemImage)
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(accent)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 13)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: Renderable Card
	
	private var profileName: String {
		user?.gameName ?? "Player"
	}
	
	private var profileTag: String {
		user?.tagLine ?? ""
	}
	
	@MainActor
	private func renderCard() async {
		let renderer = ImageRenderer(
			content: card(showsRiotID: showsRiotID)
				.environment(\.assets, assets)
				.environment(\.colorScheme, .dark)
		)
		renderer.scale = 3.0
		if let image = renderer.uiImage {
			renderedImage = image
		}
	}
	
	private func card(showsRiotID: Bool) -> some View {
		let act = seasons?.currentAct()
		let currentInfo = summary?.competitiveInfo?.inSeason(act?.id)
		let currentTier = currentInfo?.competitiveTier ?? 0
		let currentTierInfo = seasons?.tierInfo(number: currentTier, in: act)
		let currentIcon = currentTierInfo?.icon?.load()
		
		let peakRank = summary?.peakRank(seasons: seasons)
		let peakTierInfo = peakRank.flatMap { seasons?.tierInfo($0) }
		let peakIcon = peakTierInfo?.rankTriangleUpwards?.load()
		
		let totals = (summary?.competitiveInfo?.bySeason ?? [:]).values
			.reduce((wins: 0, games: 0)) { ($0.wins + $1.winCountIncludingPlacements, $0.games + $1.gameCount) }
		let games = currentInfo.map(\.gameCount) ?? totals.games
		let wins = currentInfo.map(\.winCountIncludingPlacements) ?? totals.wins
		let winRate = games > 0 ? Int((Double(wins) / Double(games) * 100).rounded()) : 0
		
		let cardID = identity?.cardID
		let cardArt = cardID.flatMap { assets?.playerCards[$0]?.smallArt }?.load()
		let title = identity.flatMap { assets?.playerTitles[$0.titleID]?.titleText }
		
		return VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .top, spacing: 12) {
				VStack(alignment: .leading, spacing: 4) {
					Text("PLAYER PROFILE")
						.font(.system(size: 9, weight: .heavy))
						.tracking(1.4)
						.foregroundStyle(.white.opacity(0.45))
					
					HStack(spacing: 2) {
						Text(profileName)
							.font(.title3.bold())
							.foregroundStyle(.white)
							.lineLimit(1)
						if showsRiotID, !profileTag.isEmpty {
							Text("#\(profileTag)")
								.font(.subheadline)
								.foregroundStyle(.white.opacity(0.5))
								.lineLimit(1)
						}
					}
					
					if let title {
						Text(title)
							.font(.caption)
							.foregroundStyle(.white.opacity(0.55))
							.lineLimit(1)
					}
				}
				
				Spacer(minLength: 0)
				
				VStack(spacing: 1) {
					Text("\(identity?.accountLevel ?? 0)")
						.font(.title2.bold().monospacedDigit())
						.foregroundStyle(.white)
					Text("LEVEL")
						.font(.system(size: 9, weight: .heavy))
						.tracking(1)
						.foregroundStyle(.white.opacity(0.45))
				}
			}
			
			HStack(alignment: .top, spacing: 12) {
				Group {
					if let cardArt {
						Image(uiImage: cardArt)
							.resizable()
							.scaledToFill()
					} else {
						Color.white.opacity(0.08)
					}
				}
				.frame(width: 100, height: 100)
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
				
				VStack(spacing: 8) {
					rankBlock(
						title: "CURRENT RANK",
						icon: currentIcon,
						name: currentTierInfo?.name ?? "Unranked",
						detail: currentInfo.map { "\($0.adjustedRankedRating) RR" },
						season: act?.id
					)
					
					rankBlock(
						title: "LIFETIME PEAK",
						icon: peakIcon,
						name: peakTierInfo?.name ?? "Unranked",
						detail: nil,
						season: peakRank?.season
					)
				}
			}
			
			HStack(spacing: 0) {
				profileStat("\(games)", label: "GAMES")
				profileStat("\(wins)", label: "WINS")
				profileStat("\(winRate) %", label: "WIN RATE")
			}
			.padding(.vertical, 12)
			.background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			
			HStack {
				Text("Vantage")
					.font(.caption2.weight(.bold))
					.foregroundStyle(.white.opacity(0.4))
				Spacer()
			}
		}
		.padding(18)
		.frame(width: Self.cardWidth)
		.background(
			LinearGradient(
				stops: [
					.init(color: Color(red: 0.62, green: 0.19, blue: 0.86), location: 0),
					.init(color: Color(red: 0.42, green: 0.14, blue: 0.68), location: 0.4),
					.init(color: Color(red: 0.19, green: 0.07, blue: 0.35), location: 0.75),
					.init(color: Color(red: 0.06, green: 0.06, blue: 0.09), location: 1)
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			),
			in: RoundedRectangle(cornerRadius: 20, style: .continuous)
		)
	}
	
	private func rankBlock(
		title: String,
		icon: UIImage?,
		name: String,
		detail: String?,
		season: Act.ID?
	) -> some View {
		HStack(spacing: 9) {
			Group {
				if let icon {
					Image(uiImage: icon)
						.resizable()
						.scaledToFit()
				} else {
					Circle().fill(Color.white.opacity(0.1))
				}
			}
			.frame(width: 34, height: 34)
			
			VStack(alignment: .leading, spacing: 1) {
				Text(title)
					.font(.system(size: 8, weight: .heavy))
					.tracking(0.8)
					.foregroundStyle(.white.opacity(0.45))
				Text(name)
					.font(.subheadline.bold())
					.foregroundStyle(.white)
					.lineLimit(1)
				.minimumScaleFactor(0.8)
				HStack(spacing: 4) {
					if let detail {
						Text(detail)
							.font(.caption2)
							.foregroundStyle(.white.opacity(0.55))
					}
					SeasonLabel(season: season)
						.font(.caption2)
				}
			}
			
			Spacer(minLength: 0)
		}
		.padding(8)
		.background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
	}
	
	private func profileStat(_ value: String, label: String) -> some View {
		VStack(spacing: 3) {
			Text(value)
				.font(.title3.bold().monospacedDigit())
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
		.environmentObject(SocialManager())
	}
}
#endif
