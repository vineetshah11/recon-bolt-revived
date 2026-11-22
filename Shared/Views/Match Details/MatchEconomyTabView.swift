import SwiftUI
import ValorantAPI

struct MatchEconomyTabView: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedPlayer: Player
	
	@State private var normalizeChart = false
	
	var body: some View {
		let stats = analytics.byPlayer[focusedPlayer.id]
		
		if let econ = analytics.economyAnalytics(for: focusedPlayer.teamID) {
			VStack(alignment: .leading, spacing: 14) {
				if let stats {
					overviewCard(stats: stats, econ: econ)
				}
				
				teamLoadoutChartCard(econ: econ)
				
				if !econ.allyBuyTypes.isEmpty {
					buyTypesCard(econ: econ)
				}
				
				roundsCard(econ: econ, playerEntries: stats?.roundEntries ?? [])
			}
		} else {
			Text("Economy analysis is available in 2-team round matches.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity)
				.padding(24)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	private func overviewCard(
		stats: MatchAnalytics.PlayerMatchAnalytics,
		econ: MatchAnalytics.EconomyAnalytics
	) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("ECONOMY OVERVIEW")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 10) {
				HStack(spacing: 10) {
					econMetricTile(
						title: "Avg Loadout",
						value: "\(Int(stats.avgLoadout.rounded()))",
						subtitle: "Lobby Ø \(Int(econ.lobbyAvgLoadout.rounded()))",
						isGood: stats.avgLoadout >= econ.lobbyAvgLoadout
					)
					econMetricTile(
						title: "Avg Spent",
						value: "\(Int(stats.avgSpent.rounded()))",
						subtitle: "Lobby Ø \(Int(econ.lobbyAvgSpent.rounded()))",
						isGood: nil
					)
				}
				
				HStack(spacing: 10) {
					econMetricTile(
						title: "Damage / 1k Credits",
						value: "\(Int(stats.damagePer1kCredits.rounded()))",
						subtitle: "Lobby Ø \(Int(econ.lobbyAvgDmgPer1k.rounded()))",
						isGood: stats.damagePer1kCredits >= econ.lobbyAvgDmgPer1k
					)
					econMetricTile(
						title: "Total Spent",
						value: "\(stats.totalSpent)",
						subtitle: "\(stats.roundsPlayed) rounds",
						isGood: nil
					)
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	private func econMetricTile(title: String, value: String, subtitle: String, isGood: Bool?) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.title3.bold().monospacedDigit())
				.foregroundStyle(isGood == true ? Color.green : isGood == false ? Color.valorantRed : .primary)
			Text(subtitle)
				.font(.caption2.monospacedDigit())
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	
	private func teamLoadoutChartCard(econ: MatchAnalytics.EconomyAnalytics) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Team Loadout Value")
					.font(.headline)
				Spacer()
				HStack(spacing: 10) {
					legendDot(title: "Your Team", color: .valorantBlue)
					legendDot(title: "Enemy", color: .valorantRed)
				}
			}
			
			TeamEconomyLineChart(rounds: econ.roundEntries)
				.frame(height: 140)
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func legendDot(title: String, color: Color) -> some View {
		HStack(spacing: 4) {
			Circle().fill(color).frame(width: 7, height: 7)
			Text(title)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}
	
	private func buyTypesCard(econ: MatchAnalytics.EconomyAnalytics) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("BUY TYPES")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 12) {
				ForEach(econ.allyBuyTypes) { item in
					let pct = Int(round(item.winRate * Double(100)))
					VStack(alignment: .leading, spacing: 6) {
						HStack {
							Text(item.type.rawValue)
								.font(.subheadline.weight(.semibold))
							Spacer()
							Text("Ø \(item.avgLoadout)")
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
							Text("\(item.wins)W–\(item.losses)L (\(pct)%)")
								.font(.caption.weight(.bold).monospacedDigit())
								.foregroundStyle(pct >= 50 ? Color.valorantBlue : Color.valorantRed)
						}
						
						GeometryReader { geo in
							ZStack(alignment: .leading) {
								Capsule().fill(Color.secondary.opacity(0.18))
								Capsule()
									.fill(pct >= 50 ? Color.valorantBlue : Color.valorantRed)
									.frame(width: max(8, geo.size.width * CGFloat(item.winRate)))
							}
						}
						.frame(height: 6)
					}
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	private func roundsCard(
		econ: MatchAnalytics.EconomyAnalytics,
		playerEntries: [MatchAnalytics.PlayerRoundEntry]
	) -> some View {
		let byRound = Dictionary(uniqueKeysWithValues: playerEntries.map { ($0.roundNumber, $0) })
		return VStack(alignment: .leading, spacing: 8) {
			Text("ROUND ECONOMY")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				ForEach(Array(econ.roundEntries.enumerated()), id: \.element.id) { index, round in
					let myEntry = byRound[round.roundNumber]
					HStack(spacing: 10) {
						Text("R\(round.roundNumber + 1)")
							.font(.caption.bold().monospacedDigit())
							.foregroundStyle(.white)
							.frame(width: 34, height: 24)
							.background(
								round.allyWon ? Color.valorantBlue : Color.valorantRed,
								in: RoundedRectangle(cornerRadius: 6, style: .continuous)
							)
						
						VStack(alignment: .leading, spacing: 1) {
							Text(round.allyBuyType.rawValue)
								.font(.caption.weight(.semibold))
							if let myEntry {
								Text("You: \(myEntry.loadoutValue) · Spent \(myEntry.spent)")
									.font(.caption2.monospacedDigit())
									.foregroundStyle(.secondary)
							}
						}
						
						Spacer()
						
						VStack(alignment: .trailing, spacing: 1) {
							Text("\(round.allyLoadout)")
								.font(.caption.weight(.bold).monospacedDigit())
								.foregroundStyle(Color.valorantBlue)
							Text("vs \(round.enemyLoadout)")
								.font(.caption2.monospacedDigit())
								.foregroundStyle(Color.valorantRed)
						}
					}
					.padding(.horizontal, 14)
					.padding(.vertical, 10)
					
					if index < econ.roundEntries.count - 1 {
						Divider().opacity(0.25).padding(.leading, 14)
					}
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
}

private struct TeamEconomyLineChart: View {
	let rounds: [MatchAnalytics.RoundTeamEconomy]
	
	var body: some View {
		GeometryReader { geo in
			let w = geo.size.width
			let h = geo.size.height
			let maxVal = max(1, rounds.flatMap { [$0.allyLoadout, $0.enemyLoadout] }.max() ?? 1)
			let count = rounds.count
			
			let allyPts: [CGPoint] = rounds.enumerated().map { idx, r in
				let x = count > 1 ? w * (CGFloat(idx) / CGFloat(count - 1)) : w * 0.5
				let y = 10 + (h - 20) * (1 - CGFloat(r.allyLoadout) / CGFloat(maxVal))
				return CGPoint(x: max(4, min(w - 4, x)), y: y)
			}
			let enemyPts: [CGPoint] = rounds.enumerated().map { idx, r in
				let x = count > 1 ? w * (CGFloat(idx) / CGFloat(count - 1)) : w * 0.5
				let y = 10 + (h - 20) * (1 - CGFloat(r.enemyLoadout) / CGFloat(maxVal))
				return CGPoint(x: max(4, min(w - 4, x)), y: y)
			}
			
			ZStack {
				linePath(enemyPts)
					.stroke(Color.valorantRed, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
				linePath(allyPts)
					.stroke(Color.valorantBlue, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
			}
		}
	}
	
	private func linePath(_ pts: [CGPoint]) -> Path {
		Path { p in
			for (i, pt) in pts.enumerated() {
				if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
			}
		}
	}
}
