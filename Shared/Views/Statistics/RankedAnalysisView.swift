import SwiftUI
import Charts
import ValorantAPI

@available(iOS 16.0, *)
struct RankedAnalysisPreviewCard: View {
	let analysis: RankedAnalysis
	
	@Environment(\.seasons) private var seasons
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 8) {
				Image(systemName: "gauge.with.dots.needle.67percent")
					.foregroundStyle(Color.accentColor)
				Text("Ranked & MMR Analysis")
					.font(.headline.weight(.bold))
					.foregroundStyle(.primary)
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			
			// Current Rank + RR bar
			HStack(spacing: 12) {
				CompetitiveTierImage(tier: analysis.currentTier)
					.frame(width: 40, height: 40)
				
				VStack(alignment: .leading, spacing: 3) {
					HStack(spacing: 6) {
						Text(analysis.currentTierName)
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.primary)
						if analysis.currentTier >= 3 {
							Text("ELO \(analysis.currentELO)")
								.font(.caption2.weight(.semibold).monospacedDigit())
								.foregroundStyle(.secondary)
								.padding(.horizontal, 6)
								.padding(.vertical, 2)
								.background(Color.tertiaryGroupedBackground, in: Capsule())
						}
					}
					
					HStack(spacing: 6) {
						Text("\(analysis.currentRR) RR")
							.font(.caption.weight(.semibold).monospacedDigit())
							.foregroundStyle(.secondary)
						if let peakName = analysis.peakRankName {
							Text("· Peak: \(peakName)")
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					}
				}
				
				Spacer()
				
				if let lastRR = analysis.lastRRChange {
					let color: Color = lastRR > 0 ? .green : (lastRR < 0 ? Color.valorantRed : .secondary)
					Text(lastRR > 0 ? "+\(lastRR) RR" : "\(lastRR) RR")
						.font(.subheadline.weight(.bold).monospacedDigit())
						.foregroundStyle(color)
				}
			}
			
			if analysis.currentTier >= 3 && !analysis.isImmortalPlus {
				let progress = Double(max(0, min(100, analysis.currentRR))) / Double(100)
				GeometryReader { geo in
					ZStack(alignment: .leading) {
						Capsule().fill(Color.tertiaryGroupedBackground)
						Capsule()
							.fill(Color.valorantBlue)
							.frame(width: max(6, geo.size.width * CGFloat(progress)))
					}
				}
				.frame(height: 5)
			}
			
			LazyVGrid(
				columns: [
					GridItem(.flexible(), spacing: 10),
					GridItem(.flexible(), spacing: 10),
				],
				spacing: 10
			) {
				mmrPreviewTile
				outlookPreviewTile
			}
			
			if let perf = analysis.lobbyPerformance {
				let pct = Int(round(perf.acsDiffPercent))
				let pctText = pct >= 0 ? "+\(pct)%" : "\(pct)%"
				Text("ACS \(Int(perf.userACS.rounded())) (\(pctText) vs lobby) · Avg #\(String(format: "%.1f", perf.avgLobbyPlace)) · \(analysis.wins)W–\(analysis.losses)L\(analysis.draws > 0 ? "–\(analysis.draws)D" : "")")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var mmrPreviewTile: some View {
		let mmr = analysis.hiddenMMR
		let color: Color = mmr.signal.isPositive == true ? .green : (mmr.signal.isPositive == false ? Color.valorantRed : .secondary)
		let rrPair: String = {
			let win = mmr.avgRRPerWin.map { String(format: "+%.0fW", $0) }
			let loss = mmr.avgRRPerLoss.map { String(format: "%.0fL", $0) }
			switch (win, loss) {
			case let (.some(w), .some(l)): return "\(w) / \(l) RR"
			case let (.some(w), nil): return "\(w) avg RR"
			case let (nil, .some(l)): return "\(l) avg RR"
			case (nil, nil): return "Last \(analysis.matches.count) ranked"
			}
		}()
		
		return VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 5) {
				Image(systemName: "waveform.path.ecg")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
				Text("Hidden MMR")
					.font(.caption.weight(.medium))
					.foregroundStyle(.secondary)
			}
			
			Text(mmr.signal.shortLabel)
				.font(.subheadline.weight(.bold))
				.foregroundStyle(color)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
			
			Text(rrPair)
				.font(.caption2.monospacedDigit())
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private var outlookPreviewTile: some View {
		let outlook = analysis.rankOutlook
		let headline: String = {
			if let est = outlook.estimatedMatchesToRankUp {
				return "~\(est) match\(est == 1 ? "" : "es")"
			}
			if analysis.matches.isEmpty { return "—" }
			return String(format: "%+.1f RR/m", outlook.avgRRPerMatch)
		}()
		let subtitle: String = {
			if let next = outlook.nextTierName, outlook.estimatedMatchesToRankUp != nil {
				return "to \(next)"
			}
			return "\(analysis.wins)W–\(analysis.losses)L\(analysis.draws > 0 ? "–\(analysis.draws)D" : "")"
		}()
		
		return VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 5) {
				Image(systemName: "arrow.up.right.circle")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
				Text("Rank Outlook")
					.font(.caption.weight(.medium))
					.foregroundStyle(.secondary)
			}
			
			Text(headline)
				.font(.subheadline.weight(.bold).monospacedDigit())
				.foregroundStyle(outlook.estimatedMatchesToRankUp != nil ? Color.primary : .secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
			
			Text(subtitle)
				.font(.caption2.monospacedDigit())
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
}

@available(iOS 16.0, *)
struct RankedAnalysisView: View {
	let user: User
	let matchList: MatchList
	var summary: CareerSummary?
	var initialDetails: [MatchDetails] = []
	private let sortedRankedUpdates: [CompetitiveUpdate]
	
	@State private var window: RankedAnalysis.Window = .last5
	@State private var detailsByID: [Match.ID: MatchDetails]
	@State private var analysis: RankedAnalysis?
	@State private var isLoadingMissing = false
	@State private var hasAutoPreloadedLast5 = false
	@State private var isShowingShareSheet = false
	@State private var showAllMatches = false
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.valorantLoad) private var load
	
	init(
		user: User,
		matchList: MatchList,
		summary: CareerSummary? = nil,
		initialDetails: [MatchDetails] = []
	) {
		self.user = user
		self.matchList = matchList
		self.summary = summary
		self.initialDetails = initialDetails
		self.sortedRankedUpdates = matchList.matches
			.filter { $0.isRanked && !$0.isDodge }
			.sorted { $0.startTime > $1.startTime }
		self._detailsByID = State(initialValue: Dictionary(
			initialDetails.map { ($0.id, $0) },
			uniquingKeysWith: { first, _ in first }
		))
	}
	
	private var windowUpdates: [CompetitiveUpdate] {
		switch window {
		case .last5: return Array(sortedRankedUpdates.prefix(5))
		case .last10: return Array(sortedRankedUpdates.prefix(10))
		case .last20: return Array(sortedRankedUpdates.prefix(20))
		case .currentAct:
			if let act = seasons?.currentAct() {
				return sortedRankedUpdates.filter { act.timeSpan.contains($0.startTime) }
			}
			return Array(sortedRankedUpdates.prefix(20))
		}
	}
	
	private var computationKey: Int {
		var hasher = Hasher()
		hasher.combine(window)
		hasher.combine(matchList.matches.count)
		hasher.combine(detailsByID.count)
		hasher.combine(summary?.competitiveInfo?.bySeason?.count ?? 0)
		hasher.combine(seasons?.currentAct()?.id)
		return hasher.finalize()
	}
	
	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 18) {
				Picker("Window", selection: $window) {
					ForEach(RankedAnalysis.Window.allCases) { option in
						Text(option.rawValue).tag(option)
					}
				}
				.pickerStyle(.segmented)
				
				if let analysis {
					if !analysis.missingDetailsIDs.isEmpty {
						missingDetailsBanner(missingIDs: analysis.missingDetailsIDs)
					}
					
					rankCard(analysis)
					
					matchAnalysisSummaryCard(analysis)
					
					if let perf = analysis.lobbyPerformance {
						performanceVsLobbyCard(perf)
					}
					
					whatToDoNextCard(analysis)
					
					if !analysis.matches.isEmpty {
						rrChartCard(analysis)
						recentMatchesCard(analysis)
					}
					
					if !analysis.agentPerformance.isEmpty {
						agentPerformanceCard(analysis.agentPerformance)
					}
				} else {
					ProgressView()
						.frame(maxWidth: .infinity, minHeight: 160)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Ranked & MMR")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if analysis != nil {
				ToolbarItem(placement: .primaryAction) {
					Button {
						isShowingShareSheet = true
					} label: {
						Image(systemName: "square.and.arrow.up")
							.foregroundStyle(Color.accentColor)
					}
				}
			}
		}
		.sheet(isPresented: $isShowingShareSheet) {
			if let analysis {
				RankedAnalysisShareSheet(user: user, analysis: analysis)
			}
		}
		.task(id: window) {
			showAllMatches = false
			await loadCachedDetailsForWindow()
			if window == .last5 && !hasAutoPreloadedLast5 {
				hasAutoPreloadedLast5 = true
				let missing = windowUpdates.map(\.id).filter { detailsByID[$0] == nil }
				if !missing.isEmpty {
					await fetchMissingDetails(Array(missing.prefix(5)))
				}
			}
		}
		.task(id: computationKey) {
			let userID = user.id
			let updates = matchList.matches
			let map = detailsByID
			let summarySnap = summary
			let seasonsSnap = seasons
			let activeWindow = window
			let computed = await Task.detached(priority: .userInitiated) {
				RankedAnalysis(
					userID: userID,
					updates: updates,
					detailsByID: map,
					summary: summarySnap,
					seasons: seasonsSnap,
					window: activeWindow
				)
			}.value
			guard !Task.isCancelled else { return }
			analysis = computed
		}
	}
	
	private func loadCachedDetailsForWindow() async {
		let ids = windowUpdates.map(\.id)
		let cached = await LocalDataProvider.shared.matchDetailsManager.cachedObjects(for: ids)
		guard !cached.isEmpty else { return }
		for m in cached {
			detailsByID[m.id] = m
		}
	}
	
	private func fetchMissingDetails(_ ids: [Match.ID]) async {
		guard !ids.isEmpty, !isLoadingMissing else { return }
		isLoadingMissing = true
		defer { isLoadingMissing = false }
		
		await load { client in
			try? await client.fetchMatchDetails(for: ids)
		}
		await loadCachedDetailsForWindow()
	}
	
	// MARK: - Sections
	
	private func missingDetailsBanner(missingIDs: [Match.ID]) -> some View {
		HStack(spacing: 12) {
			Image(systemName: "arrow.down.circle")
				.font(.title3)
				.foregroundStyle(Color.accentColor)
			
			VStack(alignment: .leading, spacing: 2) {
				Text("\(missingIDs.count) match detail\(missingIDs.count == 1 ? "" : "s") not cached")
					.font(.subheadline.weight(.semibold))
				Text("Load them to compute lobby ACS, placement, K/D, HS%, and agents.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			
			Spacer()
			
			if isLoadingMissing {
				ProgressView()
			} else {
				Button("Load") {
					Task {
						await fetchMissingDetails(missingIDs)
					}
				}
				.font(.caption.weight(.bold))
				.buttonStyle(.borderedProminent)
			}
		}
		.padding(12)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func rankCard(_ analysis: RankedAnalysis) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 12) {
				CompetitiveTierImage(tier: analysis.currentTier)
					.frame(width: 52, height: 52)
				
				VStack(alignment: .leading, spacing: 3) {
					Text(user.name)
						.font(.caption.weight(.medium))
						.foregroundStyle(.secondary)
						.lineLimit(1)
					
					Text(analysis.currentTierName)
						.font(.title3.weight(.bold))
					
					HStack(spacing: 6) {
						if analysis.currentTier >= 3 {
							Text("ELO \(analysis.currentELO)")
								.font(.caption.weight(.semibold).monospacedDigit())
								.foregroundStyle(.secondary)
						}
						if let peakName = analysis.peakRankName {
							Text("· Highest: \(peakName)")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
				}
				
				Spacer()
				
				VStack(alignment: .trailing, spacing: 4) {
					if let lastRR = analysis.lastRRChange {
						let color: Color = lastRR > 0 ? .green : (lastRR < 0 ? Color.valorantRed : .secondary)
						Text(lastRR > 0 ? "+\(lastRR) RR" : "\(lastRR) RR")
							.font(.subheadline.weight(.bold).monospacedDigit())
							.foregroundStyle(color)
							.padding(.horizontal, 9)
							.padding(.vertical, 4)
							.background(color.opacity(0.14), in: Capsule())
					}
					
					Text("\(analysis.currentRR) RR")
						.font(.caption.weight(.bold).monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
			
			if analysis.currentTier >= 3 && !analysis.isImmortalPlus {
				let progress = Double(max(0, min(100, analysis.currentRR))) / Double(100)
				VStack(alignment: .leading, spacing: 4) {
					GeometryReader { geo in
						ZStack(alignment: .leading) {
							Capsule().fill(Color.tertiaryGroupedBackground)
							Capsule()
								.fill(Color.valorantBlue)
								.frame(width: max(6, geo.size.width * CGFloat(progress)))
						}
					}
					.frame(height: 7)
					
					HStack {
						Text("Rank Progress")
						Spacer()
						Text("\(analysis.currentRR) / 100 RR")
							.monospacedDigit()
					}
					.font(.caption2)
					.foregroundStyle(.secondary)
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func matchAnalysisSummaryCard(_ analysis: RankedAnalysis) -> some View {
		let mmr = analysis.hiddenMMR
		let mmrColor: Color = mmr.signal.isPositive == true ? .green : (mmr.signal.isPositive == false ? Color.valorantRed : .secondary)
		
		return VStack(alignment: .leading, spacing: 8) {
			Text("MATCH ANALYSIS SUMMARY · \(window.rawValue.uppercased())")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(alignment: .leading, spacing: 14) {
				// Hidden MMR
				VStack(alignment: .leading, spacing: 6) {
					HStack {
						Label("Hidden MMR", systemImage: "waveform.path.ecg")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
						Spacer()
						Text(mmr.signal.shortLabel)
							.font(.caption2.weight(.bold))
							.foregroundStyle(mmrColor)
							.padding(.horizontal, 8)
							.padding(.vertical, 3)
							.background(mmrColor.opacity(0.14), in: Capsule())
					}
					
					Text(mmr.signal.headline)
						.font(.subheadline.weight(.bold))
					
					Text(mmrSubtitle(mmr))
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
					
					if mmr.avgPerformanceBonus != nil || mmr.avgLobbyTierDelta != nil {
						HStack(spacing: 8) {
							if let bonus = mmr.avgPerformanceBonus {
								Text(String(format: "Avg Bonus: +%.1f RR", bonus))
									.font(.caption2.weight(.semibold).monospacedDigit())
									.foregroundStyle(.yellow)
									.padding(.horizontal, 8)
									.padding(.vertical, 3)
									.background(Color.yellow.opacity(0.14), in: Capsule())
							}
							if let tierDelta = mmr.avgLobbyTierDelta, abs(tierDelta) >= Double(0.3) {
								let sign = tierDelta > 0 ? "+" : ""
								Text("\(sign)\(String(format: "%.1f", tierDelta)) avg lobby tier")
									.font(.caption2.weight(.semibold).monospacedDigit())
									.foregroundStyle(.secondary)
									.padding(.horizontal, 8)
									.padding(.vertical, 3)
									.background(Color.tertiaryGroupedBackground, in: Capsule())
							}
						}
					}
					
					Text("Riot doesn't publish hidden MMR; this is an estimate based on your RR gains and losses.")
						.font(.caption2)
						.foregroundStyle(.secondary.opacity(0.85))
						.italic()
				}
				
				Divider().opacity(0.25)
				
				// Rank Outlook
				VStack(alignment: .leading, spacing: 4) {
					Label("Rank Outlook", systemImage: "arrow.up.right.circle")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					
					Text(analysis.rankOutlook.summaryText)
						.font(.subheadline.weight(.medium))
				}
				
				// Form + Best Map
				LazyVGrid(
					columns: [
						GridItem(.flexible(), spacing: 10),
						GridItem(.flexible(), spacing: 10),
					],
					spacing: 10
				) {
					formTile(analysis)
					bestMapTile(analysis)
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func mmrSubtitle(_ mmr: RankedAnalysis.HiddenMMREstimate) -> String {
		var parts: [String] = []
		if let win = mmr.avgRRPerWin {
			parts.append(String(format: "+%.0f RR per win", win))
		}
		if let loss = mmr.avgRRPerLoss {
			parts.append(String(format: "−%.0f RR per loss", abs(loss)))
		}
		parts.append("RR data from \(mmr.rrSampleCount) match\(mmr.rrSampleCount == 1 ? "" : "es")")
		return parts.joined(separator: " · ")
	}
	
	private func formTile(_ analysis: RankedAnalysis) -> some View {
		let formText = "\(analysis.wins)W – \(analysis.losses)L" + (analysis.draws > 0 ? " – \(analysis.draws)D" : "")
		return VStack(alignment: .leading, spacing: 5) {
			Text("Form")
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
			Text(formText)
				.font(.subheadline.weight(.bold).monospacedDigit())
			Text(analysis.streakDescription ?? "\(Int(analysis.decidedWinRate.rounded()))% WR")
				.font(.caption2)
				.foregroundStyle(analysis.streakOutcome == .win ? Color.green : .secondary)
				.lineLimit(1)
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func bestMapTile(_ analysis: RankedAnalysis) -> some View {
		VStack(alignment: .leading, spacing: 5) {
			Text("Best Map")
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
			if let best = analysis.bestMap {
				let name = assets?.maps[best.mapID]?.displayName ?? best.mapID.rawValue
				Text(name)
					.font(.subheadline.weight(.bold))
					.lineLimit(1)
				Text("\(best.wins)/\(best.total) win\(best.total == 1 ? "" : "s") (\(Int(best.winRate.rounded()))%)")
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.secondary)
					.lineLimit(1)
			} else {
				Text("—")
					.font(.subheadline.weight(.bold))
					.foregroundStyle(.secondary)
				Text("No wins in window")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func performanceVsLobbyCard(_ perf: RankedAnalysis.LobbyPerformanceSummary) -> some View {
		let pct = Int(round(perf.acsDiffPercent))
		let pctColor: Color = pct >= 0 ? .green : Color.valorantRed
		let pctText = pct >= 0 ? "+\(pct)%" : "\(pct)%"
		
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("PERFORMANCE VS LOBBY")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(perf.detailedMatchCount) detailed")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 4)
			
			VStack(alignment: .leading, spacing: 12) {
				Text(perf.verdict.headline)
					.font(.subheadline.weight(.bold))
				
				// Prominent ACS vs Lobby Banner
				HStack {
					VStack(alignment: .leading, spacing: 2) {
						Text("ACS")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
						Text("\(Int(perf.userACS.rounded()))")
							.font(.title2.weight(.bold).monospacedDigit())
					}
					
					Spacer()
					
					VStack(alignment: .trailing, spacing: 4) {
						Text(pctText)
							.font(.caption.weight(.bold).monospacedDigit())
							.foregroundStyle(pctColor)
							.padding(.horizontal, 8)
							.padding(.vertical, 3)
							.background(pctColor.opacity(0.14), in: Capsule())
						
						Text("Lobby avg \(Int(perf.lobbyAvgACS.rounded()))")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					}
				}
				.padding(12)
				.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				
				LazyVGrid(
					columns: [
						GridItem(.flexible(), spacing: 10),
						GridItem(.flexible(), spacing: 10),
						GridItem(.flexible(), spacing: 10),
					],
					spacing: 10
				) {
					miniStatTile(title: "K/D", value: String(format: "%.2f", perf.kd), highlight: perf.kd >= Double(1.0))
					miniStatTile(title: "HS%", value: String(format: "%.1f%%", perf.hsPercent), highlight: nil)
					miniStatTile(title: "ADR", value: "\(Int(perf.adr.rounded()))", highlight: nil)
				}
				
				LazyVGrid(
					columns: [
						GridItem(.flexible(), spacing: 10),
						GridItem(.flexible(), spacing: 10),
					],
					spacing: 10
				) {
					miniStatTile(
						title: "Avg. Lobby Place",
						value: "#\(String(format: "%.1f", perf.avgLobbyPlace))",
						highlight: perf.avgLobbyPlace <= Double(4.5)
					)
					miniStatTile(
						title: "Top 3 in Lobby",
						value: "\(perf.top3Count)/\(perf.detailedMatchCount)",
						highlight: perf.detailedMatchCount > 0 ? (Double(perf.top3Count) / Double(perf.detailedMatchCount) >= Double(0.5)) : nil
					)
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func miniStatTile(title: String, value: String, highlight: Bool?) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.caption2.weight(.medium))
				.foregroundStyle(.secondary)
				.lineLimit(1)
			Text(value)
				.font(.headline.weight(.bold).monospacedDigit())
				.foregroundStyle(
					highlight == true ? Color.green : (highlight == false ? Color.valorantRed : Color.primary)
				)
		}
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	
	private func whatToDoNextCard(_ analysis: RankedAnalysis) -> some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: "lightbulb.fill")
				.font(.headline)
				.foregroundStyle(.yellow)
				.padding(.top, 2)
			
			VStack(alignment: .leading, spacing: 4) {
				Text("What to do next")
					.font(.subheadline.weight(.bold))
				Text(analysis.recommendation)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func rrChartCard(_ analysis: RankedAnalysis) -> some View {
		let chronological = Array(analysis.matches.reversed())
		return VStack(alignment: .leading, spacing: 8) {
			Text("RR WON & LOST")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			Chart {
				RuleMark(y: .value("Zero", 0))
					.foregroundStyle(.secondary.opacity(0.4))
					.lineStyle(.init(lineWidth: 1, dash: [3, 3]))
				
				ForEach(Array(chronological.enumerated()), id: \.element.id) { index, entry in
					let rr = entry.ratingEarned
					BarMark(
						x: .value("Match", index + 1),
						y: .value("RR", rr)
					)
					.foregroundStyle(rr >= 0 ? Color.green : Color.valorantRed)
					.cornerRadius(4)
					.annotation(position: rr >= 0 ? .top : .bottom) {
						Text(rr >= 0 ? "+\(rr)" : "\(rr)")
							.font(.system(size: 9, weight: .bold).monospacedDigit())
							.foregroundStyle(rr >= 0 ? Color.green : Color.valorantRed)
					}
				}
			}
			.frame(height: 150)
			.chartXAxis(.hidden)
			.chartYAxis {
				AxisMarks(position: .leading)
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func recentMatchesCard(_ analysis: RankedAnalysis) -> some View {
		let wrPct = Int(analysis.totalWinRate.rounded())
		let displayedMatches = showAllMatches ? analysis.matches : Array(analysis.matches.prefix(10))
		let hasMore = analysis.matches.count > 10 && !showAllMatches
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("RECENT RANKED MATCHES")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(wrPct)% win rate")
					.font(.caption.weight(.semibold).monospacedDigit())
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				ForEach(Array(displayedMatches.enumerated()), id: \.element.id) { index, entry in
					NavigationLink {
						MatchDetailsContainer(matchID: entry.id, userID: user.id)
					} label: {
						recentMatchRow(entry)
					}
					.buttonStyle(.plain)
					
					if index < displayedMatches.count - 1 || hasMore {
						Divider().opacity(0.22).padding(.leading, 56)
					}
				}
				
				if hasMore {
					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							showAllMatches = true
						}
					} label: {
						Text("Show all \(analysis.matches.count) matches")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(Color.accentColor)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 12)
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func recentMatchRow(_ entry: RankedAnalysis.MatchEntry) -> some View {
		let mapName = assets?.maps[entry.mapID]?.displayName ?? entry.mapID.rawValue
		let outcomeColor: Color = {
			switch entry.outcome {
			case .win: return .green
			case .loss: return Color.valorantRed
			case .draw: return .secondary
			}
		}()
		let rrColor: Color = entry.ratingEarned > 0 ? .green : (entry.ratingEarned < 0 ? Color.valorantRed : .secondary)
		
		return HStack(spacing: 12) {
			Group {
				if let agentID = entry.agentID {
					AgentImage.icon(agentID, teamID: nil)
				} else {
					Image(systemName: "questionmark")
						.font(.caption.weight(.bold))
						.foregroundStyle(.secondary)
				}
			}
			.frame(width: 34, height: 34)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
			.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(mapName)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
					
					if let agentID = entry.agentID, let agentName = assets?.agents[agentID]?.displayName {
						Text("· \(agentName)")
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				
				HStack(spacing: 6) {
					Text(entry.outcome.badgeText)
						.font(.system(size: 9.5, weight: .heavy))
						.foregroundStyle(outcomeColor)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(outcomeColor.opacity(0.14), in: Capsule())
					
					if let own = entry.ownRounds, let enemy = entry.enemyRounds {
						Text("\(own)–\(enemy)")
							.font(.caption.weight(.semibold).monospacedDigit())
							.foregroundStyle(.primary)
					}
					
					Text(entry.startTime.formatted(.dateTime.month(.abbreviated).day()))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			
			Spacer()
			
			Text(entry.ratingEarned > 0 ? "+\(entry.ratingEarned) RR" : "\(entry.ratingEarned) RR")
				.font(.subheadline.weight(.bold).monospacedDigit())
				.foregroundStyle(rrColor)
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
				.background(rrColor.opacity(0.14), in: Capsule())
			
			Image(systemName: "chevron.right")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
		}
		.padding(14)
		.contentShape(Rectangle())
	}
	
	private func agentPerformanceCard(_ agents: [RankedAnalysis.AgentSummary]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("AGENT PERFORMANCE (WIN RATE)")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				ForEach(Array(agents.enumerated()), id: \.element.id) { index, item in
					HStack(spacing: 12) {
						AgentImage.icon(item.agentID, teamID: nil)
							.frame(width: 32, height: 32)
							.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
							.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
						
						VStack(alignment: .leading, spacing: 2) {
							AgentLabel(agent: item.agentID)
								.font(.subheadline.weight(.semibold))
							Text("\(item.totalGames) game\(item.totalGames == 1 ? "" : "s") · \(item.wins)W – \(item.losses)L\(item.draws > 0 ? " – \(item.draws)D" : "")")
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
						}
						
						Spacer()
						
						let wrColor: Color = item.decidedGames == 0
							? .secondary
							: (item.winRate >= Double(50) ? .green : Color.valorantRed)
						Text(item.decidedGames > 0 ? "\(Int(item.winRate.rounded()))%" : "—")
							.font(.subheadline.weight(.bold).monospacedDigit())
							.foregroundStyle(wrColor)
					}
					.padding(14)
					
					if index < agents.count - 1 {
						Divider().opacity(0.22).padding(.leading, 58)
					}
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
}

// MARK: - Share Card Sheet

@available(iOS 16.0, *)
private struct RankedAnalysisShareSheet: View {
	let user: User
	let analysis: RankedAnalysis
	
	@Environment(\.dismiss) private var dismiss
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.configs) private var configs
	@Environment(\.location) private var location
	@Environment(\.imageManager) private var imageManager
	
	@State private var renderedImage: UIImage?
	@State private var preloadedImages: [AssetImage: UIImage] = [:]
	@State private var isRendering = false
	@State private var didCopyImage = false
	
	private var currentTierIcon: AssetImage? {
		seasons?.currentTierInfo(number: analysis.currentTier)?.icon
	}
	
	private var peakTierIcon: AssetImage? {
		analysis.peakRank.flatMap { seasons?.tierInfo($0)?.icon }
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 18) {
					shareCardCanvas(images: preloadedImages, clipCorners: true)
						.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
						.shadow(color: .black.opacity(0.45), radius: 22, y: 10)
					
					ShareCardActionButtons(
						renderedImage: renderedImage,
						isPreparing: isRendering,
						shareTitle: "Share MMR Summary",
						previewTitle: "VALORANT Ranked Analysis",
						didCopyImage: $didCopyImage
					)
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Share Ranked Summary")
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
			.task(id: analysis.matches.count) {
				await prepareAndRender()
			}
		}
	}
	
	private func shareCardCanvas(images: [AssetImage: UIImage], clipCorners: Bool) -> some View {
		let mmr = analysis.hiddenMMR
		let mmrColor: Color = mmr.signal.isPositive == true
			? Color(red: 0.24, green: 0.85, blue: 0.50)
			: (mmr.signal.isPositive == false ? Color(red: 0.96, green: 0.34, blue: 0.42) : .white.opacity(0.78))
		
		return VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 2) {
					Text("RANKED & MMR ANALYSIS")
						.font(.system(size: 11, weight: .semibold))
						.tracking(1.1)
						.foregroundStyle(.white.opacity(0.48))
					
					HStack(spacing: 4) {
						Text(user.gameName)
							.font(.system(size: 18, weight: .bold))
							.foregroundStyle(.white)
						Text("#\(user.tagLine)")
							.font(.system(size: 16, weight: .medium))
							.foregroundStyle(.white.opacity(0.48))
					}
					.lineLimit(1)
				}
				
				Spacer()
				
				Text(analysis.window.rawValue)
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
					.padding(.horizontal, 9)
					.padding(.vertical, 4)
					.background(Color.white.opacity(0.08), in: Capsule())
			}
			
			HStack(spacing: 14) {
				Group {
					if let currentTierIcon, let ui = images[currentTierIcon] {
						Image(uiImage: ui)
							.resizable()
							.scaledToFit()
					} else {
						CompetitiveTierImage(tier: analysis.currentTier)
					}
				}
				.frame(width: 54, height: 54)
				
				VStack(alignment: .leading, spacing: 3) {
					Text(analysis.currentTierName)
						.font(.system(size: 22, weight: .heavy))
						.foregroundStyle(.white)
					
					HStack(spacing: 6) {
						Text("\(analysis.currentRR) RR")
							.font(.system(size: 13, weight: .bold))
							.foregroundStyle(.white.opacity(0.85))
						if analysis.currentTier >= 3 {
							Text("• ELO \(analysis.currentELO)")
								.font(.system(size: 12.5, weight: .medium))
								.foregroundStyle(.white.opacity(0.55))
						}
					}
					.monospacedDigit()
					
					if let peakName = analysis.peakRankName {
						HStack(spacing: 5) {
							if let peakTierIcon, let ui = images[peakTierIcon] {
								Image(uiImage: ui)
									.resizable()
									.scaledToFit()
									.frame(width: 14, height: 14)
							}
							Text("Peak: \(peakName)")
								.font(.system(size: 11.5, weight: .medium))
								.foregroundStyle(.white.opacity(0.58))
						}
					}
				}
				
				Spacer()
			}
			
			VStack(alignment: .leading, spacing: 6) {
				HStack {
					Text("HIDDEN MMR ESTIMATE")
						.font(.system(size: 10, weight: .semibold))
						.tracking(0.8)
						.foregroundStyle(.white.opacity(0.48))
					Spacer()
					Text(mmr.signal.shortLabel.uppercased())
						.font(.system(size: 10, weight: .heavy))
						.foregroundStyle(mmrColor)
				}
				
				Text(mmr.signal.headline)
					.font(.system(size: 14, weight: .bold))
					.foregroundStyle(.white)
				
				Text(analysis.rankOutlook.summaryText)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white.opacity(0.68))
			}
			.padding(13)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.stroke(.white.opacity(0.08), lineWidth: 1)
			}
			
			if let perf = analysis.lobbyPerformance {
				let pct = Int(round(perf.acsDiffPercent))
				HStack(spacing: 0) {
					shareMetric(value: "\(Int(perf.userACS.rounded()))", label: "ACS (\(pct >= 0 ? "+\(pct)" : "\(pct)")%)")
					shareDivider
					shareMetric(value: String(format: "%.2f", perf.kd), label: "K/D")
					shareDivider
					shareMetric(value: String(format: "%.1f%%", perf.hsPercent), label: "HS%")
					shareDivider
					shareMetric(value: "#\(String(format: "%.1f", perf.avgLobbyPlace))", label: "AVG PLACE")
				}
				.padding(.vertical, 12)
				.background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 14, style: .continuous)
						.stroke(.white.opacity(0.08), lineWidth: 1)
				}
			}
			
			HStack {
				Text("Form: \(analysis.wins)W – \(analysis.losses)L\(analysis.draws > 0 ? " – \(analysis.draws)D" : "")")
					.font(.system(size: 11.5, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
				if let best = analysis.bestMap {
					let mapName = assets?.maps[best.mapID]?.displayName ?? best.mapID.rawValue
					Text("• Best Map: \(mapName)")
						.font(.system(size: 11.5, weight: .medium))
						.foregroundStyle(.white.opacity(0.55))
				}
			}
			.monospacedDigit()
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
	
	private var shareDivider: some View {
		Rectangle()
			.fill(.white.opacity(0.09))
			.frame(width: 1, height: 28)
	}
	
	private func shareMetric(value: String, label: String) -> some View {
		VStack(spacing: 3) {
			Text(value)
				.font(.system(size: 15, weight: .bold, design: .rounded))
				.monospacedDigit()
				.foregroundStyle(.white)
			Text(label)
				.font(.system(size: 8.5, weight: .semibold))
				.tracking(0.4)
				.foregroundStyle(.white.opacity(0.48))
		}
		.frame(maxWidth: .infinity)
	}
	
	@MainActor
	private func prepareAndRender() async {
		isRendering = true
		var loaded = preloadedImages
		for asset in [currentTierIcon, peakTierIcon].compactMap({ $0 }) where loaded[asset] == nil {
			if let cached = imageManager.cachedImage(for: asset, bucket: .icon) {
				loaded[asset] = cached
			} else if let downloaded = await imageManager.awaitImage(for: asset, bucket: .icon) {
				loaded[asset] = downloaded
			}
		}
		preloadedImages = loaded
		
		await Task.yield()
		guard !Task.isCancelled else { return }
		
		let snapshot = shareCardCanvas(images: loaded, clipCorners: false)
			.environment(\.assets, assets)
			.environment(\.configs, configs)
			.environment(\.location, location)
			.environment(\.imageManager, imageManager)
		
		renderedImage = ShareCardRenderer.render(snapshot)
		isRendering = false
	}
}
