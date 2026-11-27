import SwiftUI
import ValorantAPI

@available(iOS 16.0, *)
struct StatisticsOverviewView: View {
	var statistics: Statistics
	
	@Environment(\.seasons) private var seasons
	@State private var infoTooltip: MetricTooltip?
	
	private struct MetricTooltip: Identifiable {
		let id = UUID()
		let title: String
		let message: String
	}
	
	private var ov: Statistics.Overview { statistics.overview }
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				performanceSection
				
				rankRatingSection
				
				combatStatsSection
				
				lobbyOverviewSection
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Overview")
		.navigationBarTitleDisplayMode(.inline)
		.alert(item: $infoTooltip) { item in
			Alert(
				title: Text(item.title),
				message: Text(item.message),
				dismissButton: .default(Text("OK"))
			)
		}
	}
	
	// MARK: - Sections
	
	private var performanceSection: some View {
		sectionCard("PERFORMANCE") {
			let winRateColor: Color? = ov.winRate >= Double(50) ? .green : Color.valorantRed
			let kdColor: Color? = ov.kdRatio >= Double(1.0) ? .green : Color.valorantRed
			let kadColor: Color? = ov.kadRatio >= Double(1.25) ? .green : (ov.kadRatio < Double(0.95) ? Color.valorantRed : nil)
			let avgRRColor: Color? = ov.avgRRChange.map { $0 >= 0 ? .green : Color.valorantRed }
			
			metricTile(
				icon: "medal",
				title: "Win Rate",
				value: formatPercent(ov.winRate),
				trend: ov.wins + ov.losses > 0 ? (ov.winRate >= Double(50) ? .up(winRateColor!) : .down(winRateColor!)) : nil,
				detail: "\(ov.wins) wins, \(ov.losses) losses\(ov.draws > 0 ? ", \(ov.draws) draws" : "") across \(ov.matchesCount) matches."
			)
			
			metricTile(
				icon: "plus.square.fill",
				title: "K/D Ratio",
				value: String(format: "%.2f", ov.kdRatio),
				trend: ov.totalDeaths > 0 || ov.totalKills > 0 ? (ov.kdRatio >= Double(1.0) ? .up(kdColor!) : .down(kdColor!)) : nil,
				detail: "\(ov.totalKills) total kills and \(ov.totalDeaths) total deaths."
			)
			
			metricTile(
				icon: "chart.bar.fill",
				title: "KAD",
				value: String(format: "%.2f", ov.kadRatio),
				trend: kadColor.map { ov.kadRatio >= Double(1.25) ? .up($0) : .down($0) },
				detail: "\(ov.totalKills) kills + \(ov.totalAssists) assists per \(ov.totalDeaths) deaths."
			)
			
			metricTile(
				icon: "scope",
				title: "HS %",
				value: formatPercent(ov.hsPercent),
				trend: nil,
				detail: "\(ov.headshots) headshots out of \(ov.totalHits) total hits landed."
			)
			
			metricTile(
				icon: "clock",
				title: "Total Playtime",
				value: formatDuration(ov.totalPlaytime),
				trend: nil,
				detail: "Total active in-match time across \(ov.matchesCount) analyzed match(es)."
			)
			
			metricTile(
				icon: "chart.line.uptrend.xyaxis",
				title: "Ø RR Change",
				value: ov.avgRRChange.map { String(format: "%+.1f", $0) } ?? "—",
				trend: ov.avgRRChange.flatMap { avg in
					avgRRColor.map { avg >= 0 ? .up($0) : .down($0) }
				},
				detail: ov.rankedMatchCount > 0
					? "Average rank rating change across \(ov.rankedMatchCount) ranked match(es)."
					: "No ranked matches found in the current selection."
			)
		}
	}
	
	private var rankRatingSection: some View {
		sectionCard("RANK RATING") {
			metricTile(
				icon: "arrow.up.right",
				title: "Ø RR Gain",
				value: ov.avgRRGain.map { String(format: "+%.1f", $0) } ?? "—",
				trend: ov.avgRRGain != nil ? .up(.green) : nil,
				detail: ov.bestRRGain.map { "Highest single-match gain: +\($0) RR." } ?? "No positive RR changes recorded yet."
			)
			
			metricTile(
				icon: "arrow.down.right",
				title: "Ø RR Loss",
				value: ov.avgRRLoss.map { String(format: "%.1f", $0) } ?? "—",
				trend: ov.avgRRLoss != nil ? .down(Color.valorantRed) : nil,
				detail: ov.worstRRLoss.map { "Largest single-match loss: \($0) RR." } ?? "No negative RR changes recorded yet."
			)
			
			metricTile(
				icon: "chart.line.uptrend.xyaxis",
				title: "Net RR",
				value: ov.rankedMatchCount > 0 ? (ov.netRR >= 0 ? "+\(ov.netRR)" : "\(ov.netRR)") : "—",
				trend: ov.rankedMatchCount > 0 ? (ov.netRR >= 0 ? .up(.green) : .down(Color.valorantRed)) : nil,
				detail: "Cumulative rank rating gained or lost over \(ov.rankedMatchCount) ranked match(es)."
			)
			
			let streakText = ov.currentStreakCount > 0
				? "\(ov.currentStreakCount) \(ov.currentStreakIsWin ? "W" : "L")"
				: "—"
			metricTile(
				icon: "flame.fill",
				title: "Current Streak",
				value: streakText,
				trend: ov.currentStreakCount > 0 ? (ov.currentStreakIsWin ? .up(.green) : .down(Color.valorantRed)) : nil,
				detail: "Longest win streak: \(ov.longestWinStreak) W · Longest loss streak: \(ov.longestLossStreak) L."
			)
		}
	}
	
	private var combatStatsSection: some View {
		sectionCard("COMBAT STATS") {
			metricTile(
				icon: "bolt.fill",
				title: "Average ACS",
				value: "\(Int(ov.averageACS.rounded()))",
				trend: nil,
				detail: "Average combat score per round across \(ov.totalRoundsPlayed) rounds."
			)
			
			metricTile(
				icon: "flame",
				title: "Average ADR",
				value: "\(Int(ov.averageADR.rounded()))",
				trend: nil,
				detail: "Average damage dealt per round across \(ov.totalRoundsPlayed) rounds."
			)
			
			metricTile(
				icon: "checkmark.shield",
				title: "KAST",
				value: formatPercent(ov.averageKAST),
				trend: nil,
				detail: "Percentage of rounds with a Kill, Assist, Survival, or Trade."
			)
			
			metricTile(
				icon: "scope",
				title: "First Bloods",
				value: "\(ov.firstBloods)",
				trend: ov.firstBloods + ov.firstDeaths > 0
					? (ov.firstBloods >= ov.firstDeaths ? .up(.green) : .down(Color.valorantRed))
					: nil,
				detail: "Opening duels: \(ov.firstBloods) First Bloods vs \(ov.firstDeaths) First Deaths."
			)
			
			metricTile(
				icon: "shield.checkered",
				title: "Clutches Won",
				value: "\(ov.clutchesWon)",
				trend: nil,
				detail: "\(ov.clutchesWon) of \(ov.clutchesAttempted) clutch situations won (\(Int(ov.clutchWinRate.rounded()))%)."
			)
			
			metricTile(
				icon: "star.fill",
				title: "Multi-Kills (3K+)",
				value: "\(ov.tripleKills + ov.quadraKills + ov.aces)",
				trend: nil,
				detail: "\(ov.tripleKills) 3K · \(ov.quadraKills) 4K · \(ov.aces) Ace(s). Longest kill streak: \(ov.longestKillStreak)."
			)
			
			metricTile(
				icon: "crown.fill",
				title: "Match MVPs",
				value: "\(ov.matchMVPs)",
				trend: nil,
				detail: "\(ov.matchMVPs) Match MVP and \(ov.teamMVPs) additional Team MVP awards."
			)
			
			metricTile(
				icon: "bolt.circle",
				title: "Kill Streak",
				value: "\(ov.longestKillStreak)",
				trend: nil,
				detail: "Longest consecutive kills without dying inside a single match."
			)
		}
	}
	
	private var lobbyOverviewSection: some View {
		sectionCard("LOBBY OVERVIEW") {
			let avgTierName: String = {
				guard let tier = ov.averageLobbyTier else { return "—" }
				return seasons?.currentTierInfo(number: tier)?.name ?? "Tier \(tier)"
			}()
			
			metricTile(
				icon: "shield",
				title: "Avg Lobby Rank",
				value: avgTierName,
				trend: nil,
				detail: "Average competitive tier of players across analyzed matches."
			)
			
			metricTile(
				icon: "chart.line.uptrend.xyaxis",
				title: "ACS vs Lobby",
				value: ov.acsVsLobbyPercent.map { String(format: "%+.0f %%", $0) } ?? "—",
				trend: ov.acsVsLobbyPercent.map { $0 >= Double(0) ? .up(.green) : .down(Color.valorantRed) },
				detail: ov.averageLobbyACS.map {
					"Your average ACS (\(Int(ov.averageACS.rounded()))) compared to the lobby average (\(Int($0.rounded())))."
				} ?? "Not enough lobby comparison data yet."
			)
			
			metricTile(
				icon: "number",
				title: "Avg Lobby Place",
				value: ov.averageLobbyPlace.map { String(format: "#%.1f", $0) } ?? "—",
				trend: ov.averageLobbyPlace.map { $0 <= Double(4.5) ? .up(.green) : .down(Color.valorantRed) },
				detail: "Average ACS placement across \(ov.lobbyPlaceMatchCount) analyzed match(es)."
			)
			
			metricTile(
				icon: "trophy",
				title: "Top 3 in Lobby",
				value: ov.lobbyPlaceMatchCount > 0 ? "\(ov.top3LobbyCount)/\(ov.lobbyPlaceMatchCount)" : "—",
				trend: ov.lobbyPlaceMatchCount > 0 && ov.top3LobbyRate >= Double(50) ? .up(.green) : nil,
				detail: "\(Int(ov.top3LobbyRate.rounded()))% of matches finished in the top 3 of the lobby by ACS."
			)
			
			metricTile(
				icon: "flag.checkered",
				title: "Round Win Rate",
				value: formatPercent(ov.roundWinRate),
				trend: ov.totalRoundsPlayed > 0 ? (ov.roundWinRate >= Double(50) ? .up(.green) : .down(Color.valorantRed)) : nil,
				detail: "Round-level win percentage across \(ov.totalRoundsPlayed) played rounds."
			)
			
			metricTile(
				icon: "timer",
				title: "Avg Match Time",
				value: formatShortDuration(ov.averageMatchDuration),
				trend: nil,
				detail: "Mean duration of an analyzed match."
			)
			
			metricTile(
				icon: "person.badge.shield.checkmark",
				title: "Avg Account Lvl",
				value: ov.averageAccountLevel.map(String.init) ?? "—",
				trend: nil,
				detail: "Average account level of participants in your matches."
			)
		}
	}
	
	// MARK: - Components
	
	private enum Trend {
		case up(Color)
		case down(Color)
		
		var symbol: String {
			switch self {
			case .up: return "arrow.up"
			case .down: return "arrow.down"
			}
		}
		
		var color: Color {
			switch self {
			case .up(let c), .down(let c): return c
			}
		}
	}
	
	private func sectionCard<Content: View>(
		_ header: String,
		@ViewBuilder content: () -> Content
	) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(header)
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
				content()
			}
			.padding(12)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func metricTile(
		icon: String,
		title: String,
		value: String,
		trend: Trend?,
		detail: String
	) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 5) {
				Image(systemName: icon)
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
				
				Text(title)
					.font(.caption.weight(.medium))
					.foregroundStyle(.secondary)
					.lineLimit(1)
				
				Spacer(minLength: 2)
				
				Button {
					infoTooltip = MetricTooltip(title: title, message: detail)
				} label: {
					Image(systemName: "info.circle")
						.font(.caption2)
						.foregroundStyle(.secondary.opacity(0.65))
				}
				.buttonStyle(.plain)
			}
			
			HStack(alignment: .firstTextBaseline) {
				Text(value)
					.font(.title3.weight(.bold).monospacedDigit())
					.foregroundStyle(.primary)
					.lineLimit(1)
					.minimumScaleFactor(0.75)
				
				Spacer(minLength: 4)
				
				if let trend {
					Image(systemName: trend.symbol)
						.font(.caption.weight(.bold))
						.foregroundStyle(trend.color)
				}
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func formatPercent(_ value: Double) -> String {
		String(format: "%.1f %%", value)
	}
	
	private func formatDuration(_ interval: TimeInterval) -> String {
		guard interval > 0 else { return "0m" }
		let f = DateComponentsFormatter()
		f.allowedUnits = [.day, .hour, .minute]
		f.unitsStyle = .short
		f.maximumUnitCount = 2
		return f.string(from: interval) ?? "—"
	}
	
	private func formatShortDuration(_ interval: TimeInterval) -> String {
		guard interval > 0 else { return "—" }
		let mins = Int((interval / 60).rounded())
		return "\(mins)m"
	}
}
