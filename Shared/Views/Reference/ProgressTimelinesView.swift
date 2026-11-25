import SwiftUI
import Charts
import ValorantAPI

struct ProgressTimelinesView: View {
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var progressTimelineStore: ProgressTimelineStore
	@Environment(\.seasons) private var seasons
	@Environment(\.assets) private var assets
	@Environment(\.valorantLoad) private var load
	
	@State private var range: ProgressTimeRange = .days90
	@State private var selectedCurrency: WalletCurrency = .vp
	@State private var isRefreshing = false
	@Namespace private var rangeNamespace
	
	enum WalletCurrency: String, CaseIterable, Identifiable {
		case vp = "VP"
		case rp = "RP"
		case kc = "KC"
		
		var id: String { rawValue }
		
		var currencyID: Currency.ID {
			switch self {
			case .vp: return .valorantPoints
			case .rp: return .radianitePoints
			case .kc: return .kingdomCredits
			}
		}
		
		var accentColor: Color {
			switch self {
			case .vp: return .valorantRed
			case .rp: return .orange
			case .kc: return .valorantBlue
			}
		}
		
		func value(in point: ProgressTimelinePoint) -> Int? {
			switch self {
			case .vp: return point.vp
			case .rp: return point.rp
			case .kc: return point.kc
			}
		}
	}
	
	private struct ChartDatum: Identifiable {
		var id: String
		var date: Date
		var value: Double
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 14) {
				if let accountID = accountManager.activeAccount?.id {
					let filteredPoints = progressTimelineStore.points(for: accountID, in: range)
					let allPoints = progressTimelineStore.points(for: accountID, in: .allTime)
					let firstDate = progressTimelineStore.firstRecordedDate(for: accountID)
					
					rangePicker
					
					recordedSinceCaption(firstDate: firstDate)
					
					accountLevelCard(filtered: filteredPoints, all: allPoints)
					
					leaderboardRankCard(filtered: filteredPoints, all: allPoints)
					
					walletCard(filtered: filteredPoints, all: allPoints)
				} else {
					emptySignedOutCard
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground.ignoresSafeArea())
		.navigationTitle("Progress Timelines")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				if isRefreshing {
					ProgressView()
				}
			}
		}
		.task(id: accountManager.activeAccount?.id) {
			await refreshTimelines(showErrorAlerts: false)
		}
		.refreshable {
			await refreshTimelines(showErrorAlerts: true)
		}
	}
	
	// MARK: - Controls & Header
	
	private var rangePicker: some View {
		HStack(spacing: 4) {
			ForEach(ProgressTimeRange.allCases) { option in
				let isSelected = (range == option)
				Button {
					withAnimation(.easeInOut(duration: 0.18)) {
						range = option
					}
				} label: {
					Text(option.rawValue)
						.font(.subheadline.weight(isSelected ? .semibold : .medium))
						.foregroundStyle(isSelected ? .primary : .secondary)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 7)
						.background {
							if isSelected {
								Capsule()
									.fill(Color.secondary.opacity(0.24))
									.matchedGeometryEffect(id: "timeline_range_pill", in: rangeNamespace)
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
	
	@ViewBuilder
	private func recordedSinceCaption(firstDate: Date?) -> some View {
		if let firstDate {
			let formatted = firstDate.formatted(.dateTime.day().month(.abbreviated).year())
			Text("Recorded on this device since \(formatted)")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .center)
		} else {
			Text("Pull to refresh to record your current snapshot.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .center)
		}
	}
	
	private var emptySignedOutCard: some View {
		VStack(spacing: 8) {
			Image(systemName: "person.crop.circle.badge.exclamationmark")
				.font(.title2)
				.foregroundStyle(.secondary)
			Text("Sign in to view Progress Timelines")
				.font(.headline)
			Text("Select or sign in to an account in Settings to record your account level, leaderboard rank, and wallet over time.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(24)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: - Account Level Card
	
	private func accountLevelCard(
		filtered: [ProgressTimelinePoint],
		all: [ProgressTimelinePoint]
	) -> some View {
		let levelSeries: [ChartDatum] = filtered.compactMap { point in
			guard let level = point.accountLevel else { return nil }
			let fractionalXP = Double(max(0, min(5_000, point.accountXP ?? 0))) / Double(5_000)
			return ChartDatum(
				id: point.id,
				date: point.recordedAt,
				value: Double(level) + fractionalXP
			)
		}
		
		let latestAll = all.last(where: { $0.accountLevel != nil })
		let latestLevel = latestAll?.accountLevel
		let latestXP = latestAll?.accountXP
		
		let firstFiltered = filtered.first(where: { $0.accountLevel != nil })
		let lastFiltered = filtered.last(where: { $0.accountLevel != nil })
		let deltaText: String = {
			guard let first = firstFiltered,
				  let firstLevel = first.accountLevel,
				  let lastLevel = lastFiltered?.accountLevel else {
				return "Pull to refresh to record account level"
			}
			let dateStr = first.recordedAt.formatted(.dateTime.day().month(.abbreviated))
			if first.id == lastFiltered?.id {
				return "Recorded on \(dateStr)"
			}
			let delta = lastLevel - firstLevel
			if delta > 0 {
				let unit = delta == 1 ? "level" : "levels"
				return "+\(delta) \(unit) since \(dateStr)"
			} else if delta == 0 {
				return "Same level since \(dateStr)"
			} else {
				return "\(delta) levels since \(dateStr)"
			}
		}()
		
		return VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline) {
				Text("Account Level")
					.font(.headline)
				Spacer()
				Text(latestLevel.map(String.init) ?? "—")
					.font(.title2.bold().monospacedDigit())
			}
			
			Text(deltaText)
				.font(.subheadline)
				.foregroundStyle(.secondary)
			
			if !levelSeries.isEmpty {
				let values = levelSeries.map(\.value)
				let minInt = Int(floor(values.min() ?? 0))
				let maxInt = Int(ceil(values.max() ?? 1))
				let domainLow = Double(max(0, minInt - 1))
				let domainHigh = Double(max(minInt + 2, maxInt + 2))
				
				lineChart(
					data: levelSeries,
					yDomain: domainLow...domainHigh,
					color: .accentColor,
					desiredYAxisCount: 3,
					yLabel: { value in
						"\(Int(value.rounded()))"
					}
				)
				.frame(height: 165)
			} else {
				chartEmptyPlaceholder("No account level points in this range yet.")
			}
			
			if let latestXP {
				let clamped = max(0, min(5_000, latestXP))
				let ratio = Double(clamped) / Double(5_000)
				
				VStack(alignment: .leading, spacing: 6) {
					GeometryReader { geo in
						ZStack(alignment: .leading) {
							Capsule()
								.fill(Color.secondary.opacity(0.2))
							Capsule()
								.fill(Color.accentColor)
								.frame(width: clamped > 0 ? max(6, geo.size.width * CGFloat(ratio)) : 0)
						}
					}
					.frame(height: 5)
					
					Text("\(Self.spacedNumber(clamped)) / 5 000 XP")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
				.padding(.top, 2)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: - Leaderboard Rank Card
	
	private func leaderboardRankCard(
		filtered: [ProgressTimelinePoint],
		all: [ProgressTimelinePoint]
	) -> some View {
		let rankPoints = filtered.compactMap { point -> (point: ProgressTimelinePoint, rank: Int)? in
			guard let rank = point.leaderboardRank, rank > 0 else { return nil }
			return (point, rank)
		}
		
		let latestRank = all.last(where: { ($0.leaderboardRank ?? 0) > 0 })?.leaderboardRank
		let currentRank = rankPoints.last?.rank ?? latestRank
		
		// Plot -rank so smaller leaderboard numbers (better ranks) sit near the top.
		let rankSeries: [ChartDatum] = rankPoints.map { item in
			ChartDatum(
				id: item.point.id,
				date: item.point.recordedAt,
				value: Double(-item.rank)
			)
		}
		
		let deltaText: String = {
			guard let first = rankPoints.first, let last = rankPoints.last else {
				return "Reach Immortal+ leaderboard to track rank changes"
			}
			let dateStr = first.point.recordedAt.formatted(.dateTime.day().month(.abbreviated))
			if first.point.id == last.point.id {
				return "Recorded on \(dateStr)"
			}
			let climbed = first.rank - last.rank
			if climbed > 0 {
				let unit = climbed == 1 ? "place" : "places"
				return "\(climbed) \(unit) up since \(dateStr)"
			} else if climbed < 0 {
				let lost = abs(climbed)
				let unit = lost == 1 ? "place" : "places"
				return "\(lost) \(unit) down since \(dateStr)"
			} else {
				return "Unchanged since \(dateStr)"
			}
		}()
		
		return VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline) {
				Text("Leaderboard Rank")
					.font(.headline)
				Spacer()
				if let currentRank {
					Text("#\(currentRank)")
						.font(.title2.bold().monospacedDigit())
				} else {
					Text("Unranked")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.secondary)
				}
			}
			
			Text(deltaText)
				.font(.subheadline)
				.foregroundStyle(.secondary)
			
			if !rankSeries.isEmpty {
				let ranks = rankPoints.map(\.rank)
				let minRank = ranks.min() ?? 1
				let maxRank = ranks.max() ?? 100
				let pad = max(25, (maxRank - minRank) / 5)
				let lowY = Double(-(maxRank + pad))
				let highY = Double(-max(1, minRank - pad))
				let safeHighY = max(lowY + Double(10), highY)
				
				lineChart(
					data: rankSeries,
					yDomain: lowY...safeHighY,
					color: .valorantBlue,
					desiredYAxisCount: 3,
					yLabel: { value in
						"#\(max(1, Int(abs(value).rounded())))"
					}
				)
				.frame(height: 155)
			} else {
				chartEmptyPlaceholder("No leaderboard rank points recorded in this range.")
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: - Wallet Card
	
	private func walletCard(
		filtered: [ProgressTimelinePoint],
		all: [ProgressTimelinePoint]
	) -> some View {
		let walletSeries: [ChartDatum] = filtered.compactMap { point in
			guard let amount = selectedCurrency.value(in: point) else { return nil }
			return ChartDatum(
				id: point.id,
				date: point.recordedAt,
				value: Double(amount)
			)
		}
		
		let latestAll = all.last(where: { selectedCurrency.value(in: $0) != nil })
		let latestAmount = latestAll.flatMap { selectedCurrency.value(in: $0) }
		
		let firstFiltered = filtered.first(where: { selectedCurrency.value(in: $0) != nil })
		let lastFiltered = filtered.last(where: { selectedCurrency.value(in: $0) != nil })
		let deltaText: String = {
			guard let first = firstFiltered,
				  let firstVal = selectedCurrency.value(in: first),
				  let lastVal = lastFiltered.flatMap({ selectedCurrency.value(in: $0) }) else {
				return "Open Live Store or refresh to record balances"
			}
			let dateStr = first.recordedAt.formatted(.dateTime.day().month(.abbreviated))
			if first.id == lastFiltered?.id {
				return "Recorded on \(dateStr)"
			}
			let delta = lastVal - firstVal
			let prefix = delta >= 0 ? "+" : "-"
			if delta == 0 {
				return "No \(selectedCurrency.rawValue) change since \(dateStr)"
			}
			return "\(prefix)\(Self.spacedNumber(abs(delta))) \(selectedCurrency.rawValue) since \(dateStr)"
		}()
		
		let latestBalances = all.last(where: { $0.vp != nil || $0.rp != nil || $0.kc != nil })
		
		return VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 10) {
				Text("Wallet")
					.font(.headline)
				
				HStack(spacing: 2) {
					ForEach(WalletCurrency.allCases) { currency in
						let selected = (currency == selectedCurrency)
						Button {
							withAnimation(.easeInOut(duration: 0.15)) {
								selectedCurrency = currency
							}
						} label: {
							Text(currency.rawValue)
								.font(.caption.weight(selected ? .bold : .medium))
								.foregroundStyle(selected ? .primary : .secondary)
								.padding(.horizontal, 8)
								.padding(.vertical, 4)
								.background(
									selected ? Color.secondary.opacity(0.24) : Color.clear,
									in: Capsule()
								)
						}
						.buttonStyle(.plain)
					}
				}
				.padding(2)
				.background(Color.tertiaryGroupedBackground, in: Capsule())
				
				Spacer()
				
				if let latestAmount {
					CurrencyLabel(amount: latestAmount, currencyID: selectedCurrency.currencyID)
						.font(.headline.weight(.bold).monospacedDigit())
				} else {
					Text("—")
						.font(.headline.bold())
						.foregroundStyle(.secondary)
				}
			}
			
			Text(deltaText)
				.font(.subheadline)
				.foregroundStyle(.secondary)
			
			if !walletSeries.isEmpty {
				let values = walletSeries.map(\.value)
				let minVal = values.min() ?? 0
				let maxVal = values.max() ?? 100
				let span = max(Double(50), maxVal - minVal)
				let domainLow = max(Double(0), minVal - span * Double(0.15))
				let domainHigh = max(domainLow + Double(50), maxVal + span * Double(0.15))
				
				lineChart(
					data: walletSeries,
					yDomain: domainLow...domainHigh,
					color: selectedCurrency.accentColor,
					desiredYAxisCount: 3,
					yLabel: { value in
						Self.compactBalance(Int(value.rounded()))
					}
				)
				.frame(height: 155)
			} else {
				chartEmptyPlaceholder("No wallet snapshots recorded in this range yet.")
			}
			
			if let latestBalances {
				Divider()
					.opacity(0.35)
				
				HStack {
					ForEach(WalletCurrency.allCases) { currency in
						let value = currency.value(in: latestBalances) ?? 0
						CurrencyLabel(amount: value, currencyID: currency.currencyID)
							.font(.subheadline.monospacedDigit())
							.frame(maxWidth: .infinity)
					}
				}
				.padding(.top, 2)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: - Shared Chart Builder
	
	@ViewBuilder
	private func lineChart(
		data: [ChartDatum],
		yDomain: ClosedRange<Double>,
		color: Color,
		desiredYAxisCount: Int,
		yLabel: @escaping (Double) -> String
	) -> some View {
		let baseChart = Chart(data) { entry in
			LineMark(
				x: .value("Date", entry.date),
				y: .value("Value", entry.value)
			)
			.foregroundStyle(color)
			.lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
			
			PointMark(
				x: .value("Date", entry.date),
				y: .value("Value", entry.value)
			)
			.foregroundStyle(color)
			.symbolSize(22)
		}
		.chartYScale(domain: yDomain)
		.chartYAxis {
			AxisMarks(position: .trailing, values: .automatic(desiredCount: desiredYAxisCount)) { value in
				AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
					.foregroundStyle(Color.secondary.opacity(0.25))
				if let number = value.as(Double.self) {
					AxisValueLabel {
						Text(yLabel(number))
							.font(.caption2.monospacedDigit())
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.chartXAxis {
			AxisMarks(values: .automatic(desiredCount: 3)) { _ in
				AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
					.foregroundStyle(Color.secondary.opacity(0.25))
				AxisValueLabel(format: .dateTime.day().month(.abbreviated))
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		
		if data.count == 1, let singleDate = data.first?.date {
			let start = Calendar.current.date(byAdding: .day, value: -1, to: singleDate) ?? singleDate
			let end = Calendar.current.date(byAdding: .day, value: 1, to: singleDate) ?? singleDate
			baseChart.chartXScale(domain: start...end)
		} else {
			baseChart
		}
	}
	
	private func chartEmptyPlaceholder(_ message: String) -> some View {
		Text(message)
			.font(.caption)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
			.padding(.horizontal, 12)
			.background(Color.tertiaryGroupedBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
	}
	
	// MARK: - Refresh
	
	@MainActor
	private func refreshTimelines(showErrorAlerts: Bool) async {
		guard let account = accountManager.activeAccount else { return }
		guard !isRefreshing else { return }
		isRefreshing = true
		defer { isRefreshing = false }
		
		if let cachedSummary = LocalDataProvider.shared.careerSummaryManager.loadedObject(for: account.id) {
			progressTimelineStore.record(summary: cachedSummary, seasons: seasons, for: account.id)
		}
		
		if showErrorAlerts {
			await load { client in
				async let xpTask = try? client.getAccountXP()
				async let walletTask = try? client.getStoreWallet()
				async let summaryTask = try? client.getCareerSummary(userID: account.id)
				
				let (xp, wallet, summary) = await (xpTask, walletTask, summaryTask)
				if let xp {
					progressTimelineStore.record(accountXP: xp, for: account.id)
				}
				if let wallet {
					progressTimelineStore.record(wallet: wallet, for: account.id)
				}
				if let summary {
					LocalDataProvider.shared.careerSummaryManager.store(summary, asOf: .now)
					progressTimelineStore.record(summary: summary, seasons: seasons, for: account.id)
				}
			}
		} else {
			let client = account.client
			async let xpTask = try? client.getAccountXP()
			async let walletTask = try? client.getStoreWallet()
			async let summaryTask = try? client.getCareerSummary(userID: account.id)
			
			let (xp, wallet, summary) = await (xpTask, walletTask, summaryTask)
			if let xp {
				progressTimelineStore.record(accountXP: xp, for: account.id)
			}
			if let wallet {
				progressTimelineStore.record(wallet: wallet, for: account.id)
			}
			if let summary {
				LocalDataProvider.shared.careerSummaryManager.store(summary, asOf: .now)
				progressTimelineStore.record(summary: summary, seasons: seasons, for: account.id)
			}
		}
	}
	
	// MARK: - Formatting
	
	private static func spacedNumber(_ value: Int) -> String {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.groupingSeparator = " "
		return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
	}
	
	private static func compactBalance(_ value: Int) -> String {
		if value >= 10_000 {
			return "\(value / 1_000)k"
		}
		return "\(value)"
	}
}

#if DEBUG
struct ProgressTimelinesView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			ProgressTimelinesView()
		}
		.environmentObject(AccountManager.mocked)
		.environmentObject(ProgressTimelineStore())
		.withToolbar()
	}
}
#endif
