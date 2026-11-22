import SwiftUI
import Charts
import ValorantAPI

@available(iOS 16.0, *)
struct EconomyView: View {
	var statistics: Statistics
	
	private var econ: Statistics.Economy { statistics.economy }
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				overallSection
				
				buyTypesSection
				
				if !econ.byQueue.isEmpty {
					spendByQueueSection
				}
				
				if !statistics.winRate.roundsByLoadoutDelta.isEmpty {
					loadoutDeltaSection
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Economy")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private var overallSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("OVERALL")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			LazyVGrid(
				columns: [
					GridItem(.flexible(), spacing: 10),
					GridItem(.flexible(), spacing: 10),
				],
				spacing: 10
			) {
				econTile("Avg Loadout", value: "\(Int(econ.avgLoadoutValue.rounded()))")
				econTile("Avg Spend / Rd", value: "\(Int(econ.avgSpendPerRound.rounded()))")
				econTile("Dmg / 1k Credits", value: String(format: "%.0f", econ.damagePer1000Spent))
				econTile("Total Spent", value: formattedCredits(econ.totalSpent))
			}
			.padding(12)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private var buyTypesSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("BY BUY TYPE")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 12) {
				ForEach(Statistics.Economy.BuyType.allCases) { buyType in
					if let stats = econ.byBuyType[buyType], stats.rounds > 0 {
						VStack(alignment: .leading, spacing: 6) {
							HStack {
								Text(buyType.rawValue)
									.font(.subheadline.weight(.semibold))
								Spacer()
								Text("\(Int(stats.winRate.rounded()))% WR")
									.font(.subheadline.weight(.bold).monospacedDigit())
									.foregroundStyle(stats.winRate >= Double(50) ? Color.valorantBlue : Color.valorantRed)
							}
							
							GeometryReader { geo in
								ZStack(alignment: .leading) {
									Capsule()
										.fill(Color.valorantRed.opacity(0.45))
									Capsule()
										.fill(Color.valorantBlue)
										.frame(width: max(4, geo.size.width * CGFloat(stats.winRate / Double(100))))
								}
							}
							.frame(height: 6)
							
							HStack {
								Text("\(stats.wins)W – \(stats.losses)L · \(stats.rounds) rds")
								Spacer()
								Text("Avg Loadout \(stats.avgLoadout) · \(stats.avgDamage) dmg/rd")
							}
							.font(.caption2.monospacedDigit())
							.foregroundStyle(.secondary)
						}
					}
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private var spendByQueueSection: some View {
		let rows = econ.byQueue.sorted { $0.value.rounds > $1.value.rounds }
		return VStack(alignment: .leading, spacing: 8) {
			Text("SPEND BY QUEUE")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				ForEach(Array(rows.enumerated()), id: \.element.key) { index, item in
					HStack(spacing: 10) {
						if let modeID = statistics.modeByQueue[item.key] {
							GameModeImage(id: modeID)
								.frame(width: 24, height: 24)
								.foregroundStyle(Color.accentColor)
						}
						
						QueueLabel(queue: item.key ?? .custom)
							.font(.subheadline.weight(.semibold))
						
						Spacer()
						
						VStack(alignment: .trailing, spacing: 2) {
							Text("\(item.value.avgSpend) / rd")
								.font(.subheadline.weight(.bold).monospacedDigit())
							Text("Loadout \(item.value.avgLoadout) · \(item.value.rounds) rds")
								.font(.caption2.monospacedDigit())
								.foregroundStyle(.secondary)
						}
					}
					.padding(14)
					
					if index < rows.count - 1 {
						Divider().opacity(0.22).padding(.leading, 14)
					}
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private var loadoutDeltaSection: some View {
		let buckets = bucketedLoadoutDelta
		return VStack(alignment: .leading, spacing: 8) {
			Text("WIN RATE BY LOADOUT DELTA")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(alignment: .leading, spacing: 8) {
				Chart(buckets, id: \.label) { bucket in
					BarMark(
						x: .value("Delta", bucket.label),
						y: .value("Win Rate", bucket.winRate)
					)
					.foregroundStyle(bucket.winRate >= Double(50) ? Color.valorantBlue : Color.valorantRed)
					.cornerRadius(4)
				}
				.frame(height: 160)
				.chartYScale(domain: 0...100)
				
				Text("Average loadout value advantage per round against the enemy team.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private struct DeltaBucket {
		var label: String
		var winRate: Double
	}
	
	private var bucketedLoadoutDelta: [DeltaBucket] {
		let bands: [(String, ClosedRange<Int>)] = [
			("<-2k", Int.min ... -2001),
			("-2k", -2000 ... -1001),
			("-1k", -1000 ... -251),
			("Even", -250 ... 250),
			("+1k", 251 ... 1000),
			("+2k", 1001 ... 2000),
			("+2k+", 2001 ... Int.max),
		]
		return bands.compactMap { label, range in
			let tally = statistics.winRate.roundsByLoadoutDelta
				.filter { range.contains($0.key) }
				.values
				.reduce(into: Statistics.WinRate.Tally.zero, +=)
			guard tally.total > 0 else { return nil }
			let wr = Double(tally.wins) * Double(100) / Double(tally.total)
			return DeltaBucket(label: label, winRate: wr)
		}
	}
	
	private func econTile(_ title: String, value: String) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title)
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.title3.weight(.bold).monospacedDigit())
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func formattedCredits(_ amount: Int) -> String {
		if amount >= 1_000_000 {
			return String(format: "%.1fM", Double(amount) / Double(1_000_000))
		}
		if amount >= 1_000 {
			return "\(amount / 1000)k"
		}
		return "\(amount)"
	}
	
	// MARK: - Overview Preview
	
	static func overview(statistics: Statistics) -> some View {
		let rows: [(name: String, winRate: Double)] = Statistics.Economy.BuyType.allCases.compactMap { bt in
			guard let s = statistics.economy.byBuyType[bt], s.rounds > 0 else { return nil }
			return (bt.rawValue, s.winRate)
		}
		return Group {
			if rows.isEmpty {
				Text("Not enough data!")
					.font(.caption)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, minHeight: 80)
			} else {
				Chart(rows, id: \.name) { row in
					BarMark(
						x: .value("Buy Type", row.name),
						y: .value("Win Rate", row.winRate)
					)
					.foregroundStyle(Color.accentColor)
					.cornerRadius(4)
				}
				.chartYScale(domain: 0...100)
				.frame(height: 110)
			}
		}
	}
}
