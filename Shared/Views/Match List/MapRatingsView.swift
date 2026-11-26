import SwiftUI
import ValorantAPI

// MARK: - Badges & Shapes

private struct BeveledMapBadgeShape: Shape {
	var bevelFraction: CGFloat = 0.24
	
	func path(in rect: CGRect) -> Path {
		let bevel = min(rect.width, rect.height) * bevelFraction
		var path = Path()
		path.move(to: CGPoint(x: rect.minX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bevel))
		path.addLine(to: CGPoint(x: rect.maxX - bevel, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
		path.closeSubpath()
		return path
	}
}

private struct FourPointStarShape: Shape {
	func path(in rect: CGRect) -> Path {
		let cx = rect.midX
		let cy = rect.midY
		let rx = rect.width * 0.5
		let inner = rx * 0.28
		var path = Path()
		path.move(to: CGPoint(x: cx, y: rect.minY))
		path.addQuadCurve(to: CGPoint(x: rect.maxX, y: cy), control: CGPoint(x: cx + inner, y: cy - inner))
		path.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY), control: CGPoint(x: cx + inner, y: cy + inner))
		path.addQuadCurve(to: CGPoint(x: rect.minX, y: cy), control: CGPoint(x: cx - inner, y: cy + inner))
		path.addQuadCurve(to: CGPoint(x: cx, y: rect.minY), control: CGPoint(x: cx - inner, y: cy - inner))
		path.closeSubpath()
		return path
	}
}

struct MapTierBadgeView: View {
	let tier: MapRatingTier
	var size: CGFloat = 64
	
	private var shape: BeveledMapBadgeShape { BeveledMapBadgeShape() }
	
	var body: some View {
		let isUncalibrated = (tier == .uncalibrated)
		let highlight = isUncalibrated ? Color.white.opacity(0.28) : tier.accentColor
		
		ZStack {
			shape
				.fill(
					LinearGradient(
						colors: [
							Color(red: 0.16, green: 0.19, blue: 0.24),
							Color(red: 0.08, green: 0.10, blue: 0.13)
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					)
				)
			
			// Subtle bevel corner accent at bottom-right matching in-game metallic plate
			shape
				.stroke(
					LinearGradient(
						colors: [
							.white.opacity(0.16),
							highlight.opacity(0.45),
							.white.opacity(0.28)
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					),
					lineWidth: max(1, size * 0.028)
				)
			
			HStack(spacing: size * 0.04) {
				Text(tier.letter)
					.font(.system(size: size * 0.58, weight: .black, design: .rounded))
					.foregroundStyle(
						LinearGradient(
							colors: isUncalibrated
								? [.white, .white.opacity(0.8)]
								: [.white, tier.accentColor.opacity(0.85)],
							startPoint: .top,
							endPoint: .bottom
						)
					)
					.minimumScaleFactor(0.5)
				
				if tier.starCount > 0 {
					VStack(spacing: size * 0.045) {
						ForEach(0..<tier.starCount, id: \.self) { _ in
							FourPointStarShape()
								.fill(tier.accentColor)
								.frame(width: size * 0.18, height: size * 0.18)
						}
					}
					.padding(.bottom, size * 0.1)
				}
			}
		}
		.frame(width: size, height: size)
	}
}

// MARK: - Precision Ruler

struct MapRankRulerView: View {
	let report: MapRatingReport
	
	private struct ThresholdMarker: Identifiable {
		let score: Int
		let tier: MapRatingTier
		var id: Int { score }
	}
	
	private var windowBounds: (min: Int, max: Int) {
		let halfSpan = 85
		let low = max(0, min(500 - halfSpan * 2, report.score - halfSpan))
		let high = min(500, low + halfSpan * 2)
		return (low, high)
	}
	
	private var visibleThresholds: [ThresholdMarker] {
		let bounds = windowBounds
		return MapRatingTier.orderedCalibratedTiers
			.filter { $0.minimumScore > 0 && $0.minimumScore >= bounds.min + 8 && $0.minimumScore <= bounds.max - 8 }
			.map { ThresholdMarker(score: $0.minimumScore, tier: report.isCalibrating ? .uncalibrated : $0) }
	}
	
	var body: some View {
		let bounds = windowBounds
		let span = CGFloat(max(1, bounds.max - bounds.min))
		
		VStack(spacing: 6) {
			GeometryReader { geo in
				let width = geo.size.width
				let scoreX = width * CGFloat(report.score - bounds.min) / span
				
				ZStack(alignment: .bottomLeading) {
					// Threshold badges above the ruler track (e.g. ? 260, ? 315, ? 355)
					ForEach(visibleThresholds) { marker in
						let xPos = width * CGFloat(marker.score - bounds.min) / span
						VStack(spacing: 3) {
							HStack(spacing: 3) {
								MapTierBadgeView(tier: marker.tier, size: 15)
								Text("\(marker.score)")
									.font(.caption2.weight(.semibold))
									.monospacedDigit()
									.foregroundStyle(.secondary)
							}
							Rectangle()
								.fill(Color.white.opacity(0.35))
								.frame(width: 1, height: 10)
						}
						.position(x: min(max(24, xPos), width - 24), y: 16)
					}
					
					// Fine graduation ticks
					Path { path in
						let firstTick = ((bounds.min + 4) / 5) * 5
						for value in stride(from: firstTick, through: bounds.max, by: 5) {
							let x = width * CGFloat(value - bounds.min) / span
							let isMajor = value % 20 == 0
							let h: CGFloat = isMajor ? 10 : 5
							path.move(to: CGPoint(x: x, y: geo.size.height))
							path.addLine(to: CGPoint(x: x, y: geo.size.height - h))
						}
					}
					.stroke(Color.white.opacity(0.22), lineWidth: 1)
					
					// Baseline
					Rectangle()
						.fill(Color.white.opacity(0.18))
						.frame(height: 1)
					
					// Active score needle
					let clampedScoreX = min(max(2, scoreX), width - 2)
					Rectangle()
						.fill(
							LinearGradient(
								colors: [
									report.tier == .uncalibrated ? .white : report.tier.accentColor,
									.white
								],
								startPoint: .top,
								endPoint: .bottom
							)
						)
						.frame(width: 2.5, height: 26)
						.shadow(color: (report.tier == .uncalibrated ? Color.white : report.tier.accentColor).opacity(0.8), radius: 5)
						.position(x: clampedScoreX, y: geo.size.height - 13)
				}
			}
			.frame(height: 46)
		}
	}
}

// MARK: - Info Sheet (Matches In-Game Reference)

struct MapRatingInfoSheet: View {
	@Environment(\.dismiss) private var dismiss
	
	private let showcaseTiers: [(tier: MapRatingTier, subTiers: [MapRatingTier], range: String)] = [
		(.c3, [.c1, .c2, .c3], "0 – 199"),
		(.b3, [.b1, .b2, .b3], "200 – 354"),
		(.a3, [.a1, .a2, .a3], "355 – 469"),
		(.s, [.s], "470 – 500"),
	]
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 22) {
					sectionBlock(
						title: "MAP RANK",
						body: "Map Rank measures how your mastery evolves over time on each map. Recent matches weigh more heavily than older games, and your best match of the current Act grants an in-Act rating bonus."
					)
					
					sectionBlock(
						title: "RANK & STATS",
						body: "Your rating ranges from 0 to 500 and is driven by four core pillars: Overall Win Rate, Attack Win Rate, Defense Win Rate, and Performance Score (0–500). Complete 5 matches on a map to finish calibration."
					)
					
					VStack(alignment: .leading, spacing: 10) {
						Text("TIERS")
							.font(.title3.weight(.black))
							.tracking(0.6)
						
						Text("Ranks are divided into four tiers: C, B, A, and S. Tiers C through A include 1 to 3 stars as sub-tiers.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
						
						LazyVGrid(
							columns: [GridItem(.flexible()), GridItem(.flexible())],
							spacing: 12
						) {
							ForEach(showcaseTiers, id: \.tier) { item in
								VStack(spacing: 10) {
									MapTierBadgeView(tier: item.tier, size: 70)
									
									HStack(spacing: 6) {
										ForEach(item.subTiers, id: \.self) { sub in
											MapTierBadgeView(tier: sub, size: 24)
										}
									}
									
									Text(item.range)
										.font(.caption.weight(.semibold))
										.monospacedDigit()
										.foregroundStyle(.secondary)
								}
								.frame(maxWidth: .infinity)
								.padding(.vertical, 14)
								.background(
									Color.secondaryGroupedBackground,
									in: RoundedRectangle(cornerRadius: 16, style: .continuous)
								)
							}
						}
						.padding(.top, 4)
					}
					
					HStack(alignment: .top, spacing: 10) {
						Image(systemName: "info.circle.fill")
							.foregroundStyle(Color.accentColor)
						Text("Riot keeps live Map Rating server values private to the in-game client. Recon Bolt computes these ratings from your cached Competitive & Premier match details using all four official pillars and recency decay.")
							.font(.caption)
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
					.padding(14)
					.background(
						Color.secondaryGroupedBackground,
						in: RoundedRectangle(cornerRadius: 14, style: .continuous)
					)
				}
				.padding(18)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Map Rank Explained")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Done") {
						dismiss()
					}
				}
			}
		}
	}
	
	private func sectionBlock(title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title)
				.font(.title3.weight(.black))
				.tracking(0.6)
			Text(body)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
	}
}

// MARK: - Profile Summary Box (MatchListView)

struct MapRatingSummaryBox: View {
	var userID: User.ID
	var reports: [MapRatingReport]
	var allMatches: [CompetitiveUpdate] = []
	var detailsSnapshot: [MatchDetails] = []
	
	@State private var isExpanded = true
	@Environment(\.assets) private var assets
	
	private var playedReports: [MapRatingReport] {
		reports.filter(\.hasPlayed)
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
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
						Text("Map Ranks")
							.font(.headline)
							.foregroundStyle(.primary)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				
				Spacer()
				
				NavigationLink {
					MapRatingsView(
						userID: userID,
						initialMatches: allMatches,
						initialDetails: detailsSnapshot
					)
				} label: {
					HStack(spacing: 4) {
						Text("\(playedReports.count) maps")
							.font(.caption.weight(.medium))
							.foregroundStyle(.secondary)
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
					}
				}
				.buttonStyle(.plain)
			}
			
			if playedReports.isEmpty {
				NavigationLink {
					MapRatingsView(
						userID: userID,
						initialMatches: allMatches,
						initialDetails: detailsSnapshot
					)
				} label: {
					HStack {
						Text("Play or sync Competitive matches to view Map Ranks (0–500).")
							.font(.caption)
							.foregroundStyle(.secondary)
						Spacer()
						Image(systemName: "arrow.right.circle.fill")
							.foregroundStyle(Color.accentColor)
					}
				}
				.buttonStyle(.plain)
			} else if isExpanded {
				VStack(spacing: 8) {
					ForEach(Array(playedReports.prefix(3))) { report in
						NavigationLink {
							MapRatingsView(
								userID: userID,
								initialSelectedMapID: report.mapID,
								initialMatches: allMatches,
								initialDetails: detailsSnapshot
							)
						} label: {
							compactMapRow(report)
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func compactMapRow(_ report: MapRatingReport) -> some View {
		let mapName = assets?.maps[report.mapID]?.displayName ?? report.mapID.rawValue
		return HStack(spacing: 10) {
			MapImage.splash(report.mapID)
				.aspectRatio(contentMode: .fill)
				.frame(width: 52, height: 34)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			
			VStack(alignment: .leading, spacing: 2) {
				Text(mapName)
					.font(.subheadline.weight(.semibold))
				Text("\(report.totalMatches) matches · \(Int((report.overallWinRate * 100).rounded()))% WR")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			
			Spacer()
			
			HStack(spacing: 8) {
				VStack(alignment: .trailing, spacing: 1) {
					Text("\(report.score)")
						.font(.subheadline.weight(.bold))
						.monospacedDigit()
					Text(report.isCalibrating ? "Calib. (\(report.matchesRemainingForCalibration))" : report.tier.displayCode)
						.font(.caption2)
						.foregroundStyle(report.tier == .uncalibrated ? .secondary : report.tier.accentColor)
				}
				
				MapTierBadgeView(tier: report.tier, size: 32)
			}
		}
		.padding(8)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
	}
}

// MARK: - Full Map Ranks View

struct MapRatingsView: View {
	let userID: User.ID
	var initialSelectedMapID: MapID? = nil
	var initialMatches: [CompetitiveUpdate] = []
	var initialDetails: [MatchDetails] = []
	
	@LocalData var matchList: MatchList?
	
	@State private var loadedDetails: [Match.ID: MatchDetails] = [:]
	@State private var reports: [MapRatingReport] = []
	@State private var selectedMapID: MapID?
	@State private var selectedActID: Season.ID? = nil // nil = All Acts by default for richest data
	@State private var queueScope: MapRatingQueueScope = .competitiveAndPremier
	@State private var showingInfoSheet = false
	@State private var zoomingMinimapID: MapID?
	@State private var isSyncingMatches = false
	@State private var syncedProgress: (done: Int, total: Int)?
	@State private var unavailableSyncIDs: Set<Match.ID> = []
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	
	init(
		userID: User.ID,
		initialSelectedMapID: MapID? = nil,
		initialMatches: [CompetitiveUpdate] = [],
		initialDetails: [MatchDetails] = []
	) {
		self.userID = userID
		self.initialSelectedMapID = initialSelectedMapID
		self.initialMatches = initialMatches
		self.initialDetails = initialDetails
		self._matchList = .init(id: userID)
		self._selectedMapID = State(initialValue: initialSelectedMapID)
	}
	
	private var activeMatches: [CompetitiveUpdate] {
		let fromList = matchList?.matches ?? []
		return fromList.isEmpty ? initialMatches : fromList
	}
	
	private var uncachedEligibleIDs: [Match.ID] {
		let selectedAct = selectedActID.flatMap { seasons?.act($0) }
		return activeMatches
			.filter { match in
				guard match.mapID != nil else { return false }
				if let selectedAct, !selectedAct.timeSpan.contains(match.startTime) {
					return false
				}
				if queueScope == .competitiveAndPremier {
					return match.isRanked
				}
				return true
			}
			.map(\.id)
			.filter { loadedDetails[$0] == nil && !unavailableSyncIDs.contains($0) }
	}
	
	private var selectedReport: MapRatingReport? {
		if let selectedMapID, let exact = reports.first(where: { $0.mapID == selectedMapID }) {
			return exact
		}
		return reports.first
	}
	
	private struct ComputeKey: Equatable {
		var detailsCount: Int
		var selectedActID: Season.ID?
		var queueScope: MapRatingQueueScope
		var assetsVersion: AssetVersion?
	}
	
	var body: some View {
		let computeKey = ComputeKey(
			detailsCount: loadedDetails.count,
			selectedActID: selectedActID,
			queueScope: queueScope,
			assetsVersion: assets?.version
		)
		
		ScrollView {
			VStack(spacing: 16) {
				controlsHeaderBar
				
				if !uncachedEligibleIDs.isEmpty {
					syncMissingMatchesBanner
				}
				
				if !reports.isEmpty {
					mapSelectorCarousel
				}
				
				if let report = selectedReport {
					heroRankCard(report)
					fourPillarStatsGrid(report)
					minimapAndBestAgentsRow(report)
					if report.hasPlayed {
						extendedTacticalAnalyticsCard(report)
						matchHistoryTableCard(report)
					} else {
						unplayedMapCard(report)
					}
				} else {
					ProgressView("Calculating Map Ranks…")
						.frame(maxWidth: .infinity)
						.padding(40)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Map Ranks")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					showingInfoSheet = true
				} label: {
					Image(systemName: "info.circle")
				}
			}
		}
		.sheet(isPresented: $showingInfoSheet) {
			MapRatingInfoSheet()
		}
		.sheet(isPresented: Binding(
			get: { zoomingMinimapID != nil },
			set: { if !$0 { zoomingMinimapID = nil } }
		)) {
			if let mapID = zoomingMinimapID {
				ZoomableMinimapSheet(
					mapID: mapID,
					mapName: assets?.maps[mapID]?.displayName ?? mapID.rawValue
				)
			}
		}
		.withLocalData($matchList, id: userID, shouldAutoUpdate: true)
		.task(id: activeMatches.map(\.id)) {
			await loadCachedDetailsFromDisk()
		}
		.task(id: computeKey) {
			recomputeReports()
		}
		.onReceive(
			LocalDataProvider.shared.matchDetailsManager.changePublisher
				.debounce(for: .milliseconds(250), scheduler: RunLoop.main)
		) { _ in
			Task { await loadCachedDetailsFromDisk() }
		}
	}
	
	// MARK: - Top Controls & Sync Banner
	
	private var controlsHeaderBar: some View {
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
				HStack(spacing: 6) {
					Text(selectedActTitle)
						.font(.caption.weight(.bold))
						.textCase(.uppercase)
						.lineLimit(1)
					Image(systemName: "chevron.down")
						.font(.caption2.weight(.bold))
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 8)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
				.foregroundStyle(.primary)
			}
			
			Spacer()
			
			Picker("Queue", selection: $queueScope) {
				ForEach(MapRatingQueueScope.allCases) { scope in
					Text(scope.title).tag(scope)
				}
			}
			.pickerStyle(.segmented)
			.frame(maxWidth: 195)
		}
	}
	
	private var selectedActTitle: String {
		if let selectedActID, let act = seasons?.act(selectedActID) {
			return act.nameWithEpisode
		}
		return String(localized: "All Acts")
	}
	
	private var syncMissingMatchesBanner: some View {
		HStack(spacing: 12) {
			Image(systemName: "arrow.down.circle.fill")
				.font(.title3)
				.foregroundStyle(Color.accentColor)
			
			VStack(alignment: .leading, spacing: 2) {
				if let syncedProgress {
					Text("Downloading match history (\(syncedProgress.done)/\(syncedProgress.total))…")
						.font(.caption.weight(.semibold))
				} else {
					Text("History Sync · \(uncachedEligibleIDs.count) match detail\(uncachedEligibleIDs.count == 1 ? "" : "s") missing")
						.font(.caption.weight(.semibold))
					Text("Optional: download past match files from your history (different from the 5 placement matches needed to unlock a map tier).")
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
	
	// MARK: - Map Carousel (Matches Left Column in Game)
	
	private var mapSelectorCarousel: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 10) {
				ForEach(reports) { report in
					let isSelected = (report.mapID == selectedReport?.mapID)
					let mapName = assets?.maps[report.mapID]?.displayName ?? report.mapID.rawValue
					
					Button {
						withAnimation(.easeInOut(duration: 0.18)) {
							selectedMapID = report.mapID
						}
					} label: {
						ZStack(alignment: .bottomLeading) {
							MapImage.splash(report.mapID)
								.aspectRatio(contentMode: .fill)
								.frame(width: 148, height: 74)
								.clipped()
								.overlay(
									LinearGradient(
										colors: [
											Color.black.opacity(isSelected ? 0.25 : 0.55),
											Color.black.opacity(0.85)
										],
										startPoint: .leading,
										endPoint: .trailing
									)
								)
							
							HStack(spacing: 8) {
								VStack(alignment: .leading, spacing: 2) {
									Text(mapName)
										.font(.caption.weight(.black))
										.textCase(.uppercase)
										.foregroundStyle(.white)
										.lineLimit(1)
									
									if report.hasPlayed {
										Text("\(report.score) · \(report.totalMatches)G")
											.font(.caption2.weight(.semibold))
											.monospacedDigit()
											.foregroundStyle(.white.opacity(0.75))
									} else {
										Text("No matches")
											.font(.caption2)
											.foregroundStyle(.white.opacity(0.5))
									}
								}
								
								Spacer(minLength: 4)
								
								MapTierBadgeView(tier: report.tier, size: 32)
							}
							.padding(.horizontal, 10)
							.padding(.vertical, 8)
						}
						.frame(width: 148, height: 74)
						.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
						.overlay(
							RoundedRectangle(cornerRadius: 12, style: .continuous)
								.strokeBorder(
									isSelected ? Color(red: 0.45, green: 0.85, blue: 0.90) : Color.white.opacity(0.12),
									lineWidth: isSelected ? 2 : 1
								)
						)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.vertical, 2)
		}
	}
	
	// MARK: - Hero Rank & Ruler Card (Top Center in Game)
	
	private func heroRankCard(_ report: MapRatingReport) -> some View {
		let mapName = assets?.maps[report.mapID]?.displayName ?? report.mapID.rawValue
		
		return VStack(spacing: 16) {
			HStack(spacing: 18) {
				MapTierBadgeView(tier: report.tier, size: 92)
					.shadow(color: report.tier.accentColor.opacity(0.25), radius: 14)
				
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 6) {
						Text("RANK")
							.font(.caption.weight(.bold))
							.tracking(1.1)
							.foregroundStyle(.secondary)
						
						Button {
							showingInfoSheet = true
						} label: {
							Image(systemName: "info.circle")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					
					Text(report.hasPlayed ? "\(report.score)" : "—")
						.font(.system(size: 56, weight: .black, design: .rounded))
						.monospacedDigit()
						.foregroundStyle(.white)
						.lineLimit(1)
					
					if report.hasPlayed {
						if report.isCalibrating {
							Text("Projected tier: \(report.potentialTier.displayCode)")
								.font(.caption.weight(.semibold))
								.foregroundStyle(report.potentialTier.accentColor)
						} else if let next = report.tier.nextThreshold {
							let remainingPts = max(1, next.score - report.score)
							Text("\(remainingPts) pts to \(next.tier.displayCode)")
								.font(.caption.weight(.semibold))
								.foregroundStyle(next.tier.accentColor)
						} else {
							Text("Peak Tier Reached (S)")
								.font(.caption.weight(.semibold))
								.foregroundStyle(MapRatingTier.s.accentColor)
						}
					}
				}
				
				Spacer()
			}
			
			if report.hasPlayed {
				MapRankRulerView(report: report)
			}
			
			if report.isCalibrating {
				let playedCount = min(MapRatingReport.calibrationRequiredMatches, report.totalMatches)
				VStack(alignment: .leading, spacing: 10) {
					HStack(spacing: 12) {
						MapTierBadgeView(tier: .uncalibrated, size: 36)
						
						VStack(alignment: .leading, spacing: 3) {
							Text("Placement: \(playedCount) / \(MapRatingReport.calibrationRequiredMatches) matches played")
								.font(.caption.weight(.bold))
								.foregroundStyle(.white)
							
							Text("Play \(report.matchesRemainingForCalibration) more \(queueScope == .competitiveAndPremier ? "Competitive/Premier" : "eligible") match\(report.matchesRemainingForCalibration == 1 ? "" : "es") on \(mapName) to unlock your tier (C–S).")
								.font(.caption2)
								.foregroundStyle(.white.opacity(0.78))
								.fixedSize(horizontal: false, vertical: true)
						}
						
						Spacer(minLength: 0)
					}
					
					HStack(spacing: 6) {
						ForEach(0..<MapRatingReport.calibrationRequiredMatches, id: \.self) { index in
							Capsule()
								.fill(
									index < playedCount
									? Color.accentColor
									: Color.white.opacity(0.16)
								)
								.frame(height: 5)
						}
					}
				}
				.padding(12)
				.background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				.overlay(
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
				)
			}
		}
		.padding(18)
		.background(
			LinearGradient(
				colors: [
					Color(red: 0.08, green: 0.13, blue: 0.18),
					Color(red: 0.06, green: 0.09, blue: 0.13)
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			),
			in: RoundedRectangle(cornerRadius: 18, style: .continuous)
		)
		.overlay(
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
		)
	}
	
	// MARK: - 4 Core Stat Tiles (Top Right 2x2 in Game)
	
	private func fourPillarStatsGrid(_ report: MapRatingReport) -> some View {
		let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
		return LazyVGrid(columns: columns, spacing: 10) {
			statTile(
				title: "OVERALL WIN RATE",
				value: report.hasPlayed ? "\(Int((report.overallWinRate * 100).rounded())) %" : "—",
				accent: report.overallWinRate >= 0.5 ? Color(red: 0.25, green: 0.87, blue: 0.69) : .white
			)
			statTile(
				title: "AVG. PERF. SCORE",
				value: report.hasPlayed ? "\(report.avgPerformanceScore)" : "—",
				accent: .white
			)
			statTile(
				title: "ATTACK WIN RATE",
				value: report.hasPlayed ? "\(Int((report.attackWinRate * 100).rounded())) %" : "—",
				accent: report.attackWinRate >= 0.5 ? Color(red: 0.94, green: 0.36, blue: 0.38) : .white
			)
			statTile(
				title: "DEFENSE WIN RATE",
				value: report.hasPlayed ? "\(Int((report.defenseWinRate * 100).rounded())) %" : "—",
				accent: report.defenseWinRate >= 0.5 ? Color(red: 0.36, green: 0.72, blue: 0.92) : .white
			)
		}
	}
	
	private func statTile(title: LocalizedStringKey, value: String, accent: Color) -> some View {
		VStack(spacing: 6) {
			Text(title)
				.font(.system(size: 11, weight: .bold))
				.tracking(0.5)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
			
			Text(value)
				.font(.system(size: 28, weight: .black, design: .rounded))
				.monospacedDigit()
				.foregroundStyle(accent)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 16)
		.padding(.horizontal, 10)
		.background(
			Color.secondaryGroupedBackground,
			in: RoundedRectangle(cornerRadius: 16, style: .continuous)
		)
	}
	
	// MARK: - Minimap & Best Agents (Bottom Left & Middle in Game)
	
	private func minimapAndBestAgentsRow(_ report: MapRatingReport) -> some View {
		HStack(spacing: 10) {
			// Minimap tile with zoom button
			Button {
				zoomingMinimapID = report.mapID
			} label: {
				ZStack(alignment: .bottomTrailing) {
					MapImage.minimap(report.mapID)
						.scaledToFit()
						.padding(10)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
					
					Image(systemName: "plus.magnifyingglass")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.white)
						.frame(width: 32, height: 32)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
						.padding(8)
				}
				.frame(height: 186)
				.frame(maxWidth: .infinity)
				.background(
					Color(red: 0.08, green: 0.11, blue: 0.15),
					in: RoundedRectangle(cornerRadius: 16, style: .continuous)
				)
				.overlay(
					RoundedRectangle(cornerRadius: 16, style: .continuous)
						.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
				)
			}
			.buttonStyle(.plain)
			
			// Your Best Agents tile
			VStack(spacing: 0) {
				Text("YOUR BEST AGENTS")
					.font(.system(size: 10, weight: .bold))
					.tracking(0.5)
					.foregroundStyle(.secondary)
					.padding(.top, 10)
					.padding(.horizontal, 8)
				
				if report.bestAgents.isEmpty {
					Spacer()
					Image(systemName: "person.fill.questionmark")
						.font(.title2)
						.foregroundStyle(.secondary)
					Text("No data")
						.font(.caption)
						.foregroundStyle(.secondary)
					Spacer()
				} else {
					TabView {
						ForEach(Array(report.bestAgents.prefix(3))) { agentStat in
							bestAgentCardContent(agentStat)
						}
					}
					.tabViewStyle(.page(indexDisplayMode: report.bestAgents.count > 1 ? .automatic : .never))
				}
			}
			.frame(height: 186)
			.frame(maxWidth: .infinity)
			.background(
				Color(red: 0.08, green: 0.11, blue: 0.15),
				in: RoundedRectangle(cornerRadius: 16, style: .continuous)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
			)
		}
	}
	
	private func bestAgentCardContent(_ stat: MapAgentBestStat) -> some View {
		let agentName = assets?.agents[stat.id]?.displayName ?? "Agent"
		return ZStack(alignment: .bottomLeading) {
			AgentImage.fullPortrait(stat.id)
				.scaledToFill()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.offset(y: 6)
				.clipped()
				.overlay(
					LinearGradient(
						colors: [.clear, .black.opacity(0.82)],
						startPoint: .center,
						endPoint: .bottom
					)
				)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(agentName)
					.font(.headline.weight(.black))
					.textCase(.uppercase)
					.foregroundStyle(.white)
					.lineLimit(1)
				
				Text("\(Int((stat.winRate * 100).rounded()))% WR · \(stat.matches)G · \(String(format: "%.2f", stat.kd)) KD")
					.font(.system(size: 10, weight: .semibold))
					.monospacedDigit()
					.foregroundStyle(.white.opacity(0.8))
			}
			.padding(10)
		}
		.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		.padding(.horizontal, 6)
		.padding(.bottom, 6)
	}
	
	// MARK: - Bonus Tactical Analytics Card ("Plus d'infos qu'en jeu")
	
	private func extendedTacticalAnalyticsCard(_ report: MapRatingReport) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Label("Combat & Map Insights", systemImage: "chart.bar.xaxis")
					.font(.subheadline.weight(.bold))
				Spacer()
				if let pistolWR = report.pistolWinRate {
					Text("Pistol \(Int((pistolWR * 100).rounded()))%")
						.font(.caption.weight(.semibold))
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
			}
			
			HStack(spacing: 8) {
				miniMetric("K/D", value: String(format: "%.2f", report.avgKD))
				miniMetric("ACS", value: "\(Int(report.avgACS.rounded()))")
				miniMetric("ADR", value: "\(Int(report.avgADR.rounded()))")
				miniMetric("HS%", value: "\(Int(report.avgHSPercent.rounded()))%")
				miniMetric("KAST", value: "\(Int(report.avgKASTPercent.rounded()))%")
			}
			
			if report.recentRatingTrend.count >= 2 {
				VStack(alignment: .leading, spacing: 6) {
					HStack {
						Text("Rating Trajectory")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
						Spacer()
						Text("FK–FD: \(report.firstBloodDiff >= 0 ? "+\(report.firstBloodDiff)" : "\(report.firstBloodDiff)")")
							.font(.caption.weight(.semibold))
							.monospacedDigit()
							.foregroundStyle(report.firstBloodDiff >= 0 ? Color.green : Color.red)
					}
					
					RatingSparklineView(
						values: report.recentRatingTrend,
						accentColor: report.tier == .uncalibrated ? Color(red: 0.36, green: 0.72, blue: 0.92) : report.tier.accentColor
					)
					.frame(height: 54)
				}
				.padding(.top, 2)
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func miniMetric(_ title: String, value: String) -> some View {
		VStack(spacing: 3) {
			Text(title)
				.font(.system(size: 10, weight: .semibold))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.subheadline.weight(.bold))
				.monospacedDigit()
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 8)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
	}
	
	// MARK: - Match History Table Card (Bottom Right in Game)
	
	private func matchHistoryTableCard(_ report: MapRatingReport) -> some View {
		let bestID = report.bestMatch?.id
		let orderedMatches: [MapRatingMatchEntry] = {
			guard let best = report.bestMatch else { return report.matches }
			let others = report.matches.filter { $0.id != best.id }
			return [best] + others
		}()
		
		return VStack(alignment: .leading, spacing: 12) {
			HStack {
				Label("Match History", systemImage: "list.bullet.rectangle")
					.font(.subheadline.weight(.bold))
				Spacer()
				Text("\(report.totalMatches) match\(report.totalMatches == 1 ? "" : "es") (+\(report.actMatches) this Act)")
					.font(.caption2.weight(.semibold))
					.monospacedDigit()
					.foregroundStyle(.secondary)
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(Color.tertiaryGroupedBackground, in: Capsule())
			}
			
			VStack(spacing: 10) {
				ForEach(orderedMatches) { entry in
					matchHistoryRow(entry, isBestOfAct: entry.id == bestID)
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func matchHistoryRow(_ entry: MapRatingMatchEntry, isBestOfAct: Bool) -> some View {
		let accentBarColor: Color = entry.won
			? Color(red: 0.25, green: 0.87, blue: 0.69)
			: (entry.tied ? .secondary : Color(red: 0.96, green: 0.36, blue: 0.38))
		let rowTint: Color = entry.won
			? Color(red: 0.13, green: 0.36, blue: 0.31).opacity(0.32)
			: (entry.tied
			   ? Color.tertiaryGroupedBackground
			   : Color(red: 0.42, green: 0.14, blue: 0.17).opacity(0.32))
		let deltaText = entry.ratingDelta >= 0 ? "+\(entry.ratingDelta)" : "\(entry.ratingDelta)"
		let deltaColor: Color = entry.ratingDelta >= 0
			? Color(red: 0.25, green: 0.87, blue: 0.69)
			: Color(red: 0.96, green: 0.36, blue: 0.38)
		
		return NavigationLink {
			MatchDetailsContainer(matchID: entry.id, userID: userID)
		} label: {
			VStack(alignment: .leading, spacing: 10) {
				if isBestOfAct {
					HStack(spacing: 5) {
						Image(systemName: "star.fill")
							.font(.system(size: 9, weight: .bold))
						Text("BEST MATCH OF THE ACT")
							.font(.system(size: 10, weight: .black))
							.tracking(0.5)
						Spacer()
					}
					.foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.28))
				}
				
				HStack(spacing: 10) {
					if let agentID = entry.agentID {
						AgentImage.icon(agentID, outlineRadius: 1)
							.frame(width: 40, height: 40)
							.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
					} else {
						RoundedRectangle(cornerRadius: 9, style: .continuous)
							.fill(Color.secondaryGroupedBackground)
							.frame(width: 40, height: 40)
					}
					
					VStack(alignment: .leading, spacing: 3) {
						HStack(spacing: 6) {
							Text("\(entry.ratingAfter)")
								.font(.title3.weight(.bold))
								.foregroundStyle(.primary)
								.monospacedDigit()
							
							Text(deltaText)
								.font(.caption.weight(.bold))
								.monospacedDigit()
								.foregroundStyle(deltaColor)
								.padding(.horizontal, 6)
								.padding(.vertical, 2)
								.background(deltaColor.opacity(0.16), in: Capsule())
						}
						
						Text("\(entry.scoreText) · \(entry.kdaText) · \(entry.matchStart.formatted(.dateTime.day().month(.abbreviated)))")
							.font(.caption)
							.foregroundStyle(.secondary)
							.monospacedDigit()
							.lineLimit(1)
					}
					
					Spacer(minLength: 4)
					
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.tertiary)
				}
				
				HStack(spacing: 8) {
					matchStatChip(label: "PERF.", value: "\(entry.performanceScore)")
					matchStatChip(label: "ATK", value: "\(Int((entry.attackWinRate * 100).rounded()))%")
					matchStatChip(label: "DEF", value: "\(Int((entry.defenseWinRate * 100).rounded()))%")
				}
			}
			.padding(12)
			.padding(.leading, 4)
			.background {
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.fill(rowTint)
					.overlay(alignment: .leading) {
						Rectangle()
							.fill(accentBarColor)
							.frame(width: 4)
					}
					.overlay(
						RoundedRectangle(cornerRadius: 14, style: .continuous)
							.strokeBorder(
								isBestOfAct
								? Color(red: 0.90, green: 0.72, blue: 0.28).opacity(0.45)
								: Color.white.opacity(0.06),
								lineWidth: 1
							)
					)
					.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
		}
		.buttonStyle(.plain)
	}
	
	private func matchStatChip(label: String, value: String) -> some View {
		HStack(spacing: 4) {
			Text(label)
				.font(.system(size: 10, weight: .bold))
				.foregroundStyle(.secondary)
			Spacer(minLength: 2)
			Text(value)
				.font(.caption.weight(.bold))
				.monospacedDigit()
				.foregroundStyle(.primary)
		}
		.padding(.horizontal, 9)
		.padding(.vertical, 6)
		.frame(maxWidth: .infinity)
		.background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
	}
	
	private func unplayedMapCard(_ report: MapRatingReport) -> some View {
		let mapName = assets?.maps[report.mapID]?.displayName ?? report.mapID.rawValue
		return VStack(spacing: 8) {
			Image(systemName: "map")
				.font(.title2)
				.foregroundStyle(.secondary)
			Text("No recorded matches on \(mapName)")
				.font(.subheadline.weight(.semibold))
			Text("Play Competitive or Premier matches on this map (or sync uncached matches above) to compute your rank.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(22)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: - Data Loading & Computation
	
	private func loadCachedDetailsFromDisk() async {
		var combined = loadedDetails
		for d in initialDetails {
			combined[d.id] = d
		}
		
		let ids = activeMatches.map(\.id)
		let manager = LocalDataProvider.shared.matchDetailsManager
		for id in ids {
			if let obj = manager.loadedObject(for: id) {
				combined[id] = obj
			}
		}
		
		let missingDiskIDs = ids.filter { combined[$0] == nil }
		if !missingDiskIDs.isEmpty {
			let diskLoaded = await manager.loadFromDiskOnly(for: missingDiskIDs)
			for obj in diskLoaded {
				combined[obj.id] = obj
			}
		}
		
		loadedDetails = combined
	}
	
	private func recomputeReports() {
		let allDetails = Array(loadedDetails.values)
		let actFilter = selectedActID
		let scope = queueScope
		let uid = userID
		let seasonsSnapshot = seasons
		let assetsSnapshot = assets
		
		Task {
			let result = await Task.detached(priority: .userInitiated) {
				MapRatingCalculator.compute(
					userID: uid,
					matches: allDetails,
					selectedActID: actFilter,
					queueScope: scope,
					seasons: seasonsSnapshot?.collection,
					assets: assetsSnapshot
				)
			}.value
			
			reports = result
			if selectedMapID == nil || !result.contains(where: { $0.mapID == selectedMapID }) {
				selectedMapID = result.first?.mapID
			}
		}
	}
	
	private func syncUncachedMatches() {
		let toFetch = Array(uncachedEligibleIDs.prefix(40))
		guard !toFetch.isEmpty else { return }
		
		Task {
			isSyncingMatches = true
			syncedProgress = (0, toFetch.count)
			defer {
				isSyncingMatches = false
				syncedProgress = nil
			}
			
			await load { client in
				for (idx, matchID) in toFetch.enumerated() {
					if Task.isCancelled { break }
					try? await client.fetchMatchDetails(for: matchID)
					if let details = LocalDataProvider.shared.matchDetailsManager.loadedObject(for: matchID) {
						loadedDetails[matchID] = details
					} else {
						unavailableSyncIDs.insert(matchID)
					}
					syncedProgress = (idx + 1, toFetch.count)
				}
			}
			await loadCachedDetailsFromDisk()
		}
	}
}

// MARK: - Rating Sparkline & Zoomable Minimap

private struct RatingSparklineView: View {
	let values: [Int]
	let accentColor: Color
	
	var body: some View {
		GeometryReader { geo in
			let w = geo.size.width
			let h = geo.size.height
			let minVal = Double(max(0, (values.min() ?? 0) - 25))
			let maxVal = Double(min(500, (values.max() ?? 500) + 25))
			let span = max(20.0, maxVal - minVal)
			
			let points: [CGPoint] = values.enumerated().map { idx, val in
				let x = values.count > 1 ? w * CGFloat(idx) / CGFloat(values.count - 1) : w * 0.5
				let y = h - (h * CGFloat((Double(val) - minVal) / span))
				return CGPoint(x: x, y: y)
			}
			
			ZStack {
				if points.count >= 2 {
					Path { path in
						path.move(to: CGPoint(x: points.first!.x, y: h))
						for pt in points {
							path.addLine(to: pt)
						}
						path.addLine(to: CGPoint(x: points.last!.x, y: h))
						path.closeSubpath()
					}
					.fill(
						LinearGradient(
							colors: [accentColor.opacity(0.32), accentColor.opacity(0.02)],
							startPoint: .top,
							endPoint: .bottom
						)
					)
					
					Path { path in
						path.move(to: points[0])
						for pt in points.dropFirst() {
							path.addLine(to: pt)
						}
					}
					.stroke(accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
				}
				
				ForEach(Array(points.enumerated()), id: \.offset) { idx, pt in
					Circle()
						.fill(idx == points.count - 1 ? .white : accentColor)
						.frame(width: idx == points.count - 1 ? 6 : 4, height: idx == points.count - 1 ? 6 : 4)
						.position(pt)
				}
			}
		}
	}
}

private struct ZoomableMinimapSheet: View {
	let mapID: MapID
	let mapName: String
	
	@State private var scale: CGFloat = 1.0
	@State private var lastScale: CGFloat = 1.0
	@Environment(\.dismiss) private var dismiss
	
	var body: some View {
		NavigationStack {
			ZStack {
				Color.black.ignoresSafeArea()
				
				MapImage.minimap(mapID)
					.scaledToFit()
					.scaleEffect(scale)
					.gesture(
						MagnificationGesture()
							.onChanged { value in
								scale = min(4.0, max(1.0, lastScale * value))
							}
							.onEnded { _ in
								lastScale = scale
							}
					)
					.onTapGesture(count: 2) {
						withAnimation(.spring()) {
							scale = scale > 1.2 ? 1.0 : 2.2
							lastScale = scale
						}
					}
					.padding()
			}
			.navigationTitle("\(mapName) Minimap")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Done") { dismiss() }
				}
			}
		}
	}
}
