import SwiftUI
import ValorantAPI

struct MatchPerformanceTabView: View {
	enum Metric: String, CaseIterable, Identifiable {
		case acs = "ACS"
		case damage = "Damage"
		case kills = "Kills"
		
		var id: String { rawValue }
		
		var headerTitle: String {
			switch self {
			case .acs: return "ACS PER ROUND"
			case .damage: return "DAMAGE PER ROUND"
			case .kills: return "KILLS PER ROUND"
			}
		}
	}
	
	enum SideFilter: String, CaseIterable, Identifiable {
		case all = "All"
		case attack = "Attack"
		case defense = "Defense"
		
		var id: String { rawValue }
	}
	
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedPlayer: Player
	
	@Environment(\.assets) private var assets
	@State private var metric: Metric = .acs
	@State private var sideFilter: SideFilter = .all
	@State private var expandedRounds: Set<Int> = []
	
	var body: some View {
		let stats = analytics.byPlayer[focusedPlayer.id]
		let entries = (stats?.roundEntries ?? []).filter { entry in
			switch sideFilter {
			case .all: return true
			case .attack: return entry.isAttack
			case .defense: return !entry.isAttack
			}
		}
		let lobbyAvg: Double = {
			switch metric {
			case .acs: return analytics.lobbyAvgACS
			case .damage: return analytics.lobbyAvgADR
			case .kills: return analytics.lobbyAvgKills
			}
		}()
		
		VStack(alignment: .leading, spacing: 14) {
			HStack {
				Text(metric.headerTitle)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				Spacer()
				Menu {
					ForEach(Metric.allCases) { item in
						Button {
							metric = item
						} label: {
							if metric == item {
								Label(item.rawValue, systemImage: "checkmark")
							} else {
								Text(item.rawValue)
							}
						}
					}
				} label: {
					HStack(spacing: 4) {
						Text(metric.rawValue)
						Image(systemName: "chevron.up.chevron.down")
					}
					.font(.caption.weight(.bold))
					.foregroundStyle(Color.accentColor)
				}
			}
			.padding(.horizontal, 4)
			
			chartCard(entries: entries, lobbyAvg: lobbyAvg)
			
			roundsSection(entries: entries)
		}
	}
	
	private func metricValue(for entry: MatchAnalytics.PlayerRoundEntry) -> Int {
		switch metric {
		case .acs: return entry.acs
		case .damage: return entry.damage
		case .kills: return entry.kills
		}
	}
	
	private func chartCard(
		entries: [MatchAnalytics.PlayerRoundEntry],
		lobbyAvg: Double
	) -> some View {
		VStack(spacing: 14) {
			Picker("Side", selection: $sideFilter) {
				ForEach(SideFilter.allCases) { side in
					Text(side.rawValue).tag(side)
				}
			}
			.pickerStyle(.segmented)
			
			if entries.isEmpty {
				Text("No round data for this filter.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.frame(height: 150)
			} else {
				// Top win/loss round dashes
				HStack(spacing: 3) {
					ForEach(entries) { entry in
						Capsule()
							.fill(entry.won ? Color.valorantBlue : Color.valorantRed)
							.frame(height: 3)
					}
				}
				
				PerformanceRoundChart(
					entries: entries,
					values: entries.map(metricValue),
					lobbyAverage: lobbyAvg,
					lobbyAvgLabel: metric == .kills
						? String(format: "%.2f", lobbyAvg)
						: "\(Int(lobbyAvg.rounded()))"
				)
				.frame(height: 155)
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func roundsSection(entries: [MatchAnalytics.PlayerRoundEntry]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("ROUNDS")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
					let isExpanded = expandedRounds.contains(entry.roundNumber)
					
					VStack(spacing: 10) {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								if isExpanded {
									expandedRounds.remove(entry.roundNumber)
								} else {
									expandedRounds.insert(entry.roundNumber)
								}
							}
						} label: {
							HStack(spacing: 10) {
								Text("\(entry.roundNumber + 1)")
									.font(.subheadline.weight(.bold).monospacedDigit())
									.foregroundStyle(entry.won ? Color.valorantBlue : Color.valorantRed)
									.frame(width: 24, alignment: .leading)
								
								Group {
									if let weaponID = entry.weaponID {
										WeaponImage.killStreamIcon(weaponID)
											.scaledToFit()
											.foregroundStyle(.secondary)
									} else {
										Color.clear
									}
								}
								.frame(width: 48, height: 18)
								
								HStack(spacing: 3) {
									ForEach(Array(entry.killedAgentIDs.enumerated()), id: \.offset) { _, agentID in
										AgentImage.icon(agentID)
											.frame(width: 22, height: 22)
											.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
											.clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
									}
								}
								
								Spacer()
								
								Text("\(entry.kills) / \(entry.deaths) / \(entry.assists)")
									.font(.subheadline.weight(.semibold).monospacedDigit())
									.foregroundStyle(.primary)
								
								Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
									.font(.caption2.weight(.semibold))
									.foregroundStyle(.secondary)
							}
							.padding(.vertical, 12)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						
						if isExpanded {
							VStack(alignment: .leading, spacing: 8) {
								HStack(spacing: 16) {
									roundDetailMetric("ACS", "\(entry.acs)")
									roundDetailMetric("Damage", "\(entry.damage)")
									roundDetailMetric("Loadout", "\(entry.loadoutValue)")
									roundDetailMetric("Spent", "\(entry.spent)")
								}
								
								HStack {
									Text("\(entry.isAttack ? "Attack" : "Defense") · \(entry.outcome)")
										.font(.caption)
										.foregroundStyle(.secondary)
									
									Spacer()
									
									NavigationLink {
										RoundInfoContainer(matchData: data, roundNumber: entry.roundNumber)
									} label: {
										Label("Round Map", systemImage: "map")
											.font(.caption.weight(.semibold))
											.foregroundStyle(Color.accentColor)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.bottom, 12)
						}
					}
					.padding(.horizontal, 14)
					
					if index < entries.count - 1 {
						Divider()
							.opacity(0.25)
							.padding(.leading, 14)
					}
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	private func roundDetailMetric(_ title: String, _ value: String) -> some View {
		VStack(alignment: .leading, spacing: 1) {
			Text(title)
				.font(.system(size: 10, weight: .medium))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.caption.weight(.bold).monospacedDigit())
		}
	}
}

private struct PerformanceRoundChart: View {
	let entries: [MatchAnalytics.PlayerRoundEntry]
	let values: [Int]
	let lobbyAverage: Double
	let lobbyAvgLabel: String
	
	var body: some View {
		GeometryReader { geo in
			let w = geo.size.width
			let h = geo.size.height
			let topPad: CGFloat = 20
			let botPad: CGFloat = 20
			let plotH = max(20, h - topPad - botPad)
			
			let maxVal = max(CGFloat(values.max() ?? 1), CGFloat(lobbyAverage), 1) * 1.1
			let minVal: CGFloat = 0
			let span = max(1, maxVal - minVal)
			
			let count = values.count
			let points: [CGPoint] = values.enumerated().map { idx, val in
				let x = count > 1 ? w * (CGFloat(idx) / CGFloat(count - 1)) : w * 0.5
				let yNorm = (CGFloat(val) - minVal) / span
				let y = topPad + plotH * (1 - yNorm)
				return CGPoint(x: max(8, min(w - 8, x)), y: y)
			}
			
			let avgYNorm = min(1, max(0, (CGFloat(lobbyAverage) - minVal) / span))
			let avgY = topPad + plotH * (1 - avgYNorm)
			
			let bestIndex = values.enumerated().max { $0.element < $1.element }?.offset
			let lowIndex = values.enumerated().min { $0.element < $1.element }?.offset
			
			ZStack(alignment: .topLeading) {
				// Lobby average dashed line
				Path { p in
					p.move(to: CGPoint(x: 0, y: avgY))
					p.addLine(to: CGPoint(x: w, y: avgY))
				}
				.stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
				
				Text("Ø Lobby \(lobbyAvgLabel)")
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.secondary)
					.position(x: max(54, w - 48), y: max(10, avgY - 10))
				
				// Performance line
				Path { p in
					for (i, pt) in points.enumerated() {
						if i == 0 {
							p.move(to: pt)
						} else {
							let prev = points[i - 1]
							let midX = (prev.x + pt.x) * 0.5
							p.addCurve(
								to: pt,
								control1: CGPoint(x: midX, y: prev.y),
								control2: CGPoint(x: midX, y: pt.y)
							)
						}
					}
				}
				.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
				
				// Round dots + BEST / LOW diamonds
				ForEach(Array(points.enumerated()), id: \.offset) { idx, pt in
					if idx == bestIndex {
						diamond(size: 9, color: .yellow)
							.position(pt)
						Text("BEST")
							.font(.system(size: 9, weight: .bold))
							.foregroundStyle(.secondary)
							.position(x: min(max(pt.x, 18), w - 18), y: max(8, pt.y - 12))
					} else if idx == lowIndex, bestIndex != lowIndex {
						diamond(size: 8, color: .orange)
							.position(pt)
						Text("LOW")
							.font(.system(size: 9, weight: .bold))
							.foregroundStyle(.secondary)
							.position(x: min(max(pt.x, 16), w - 16), y: min(h - 8, pt.y + 12))
					} else {
						Circle()
							.fill(Color.accentColor)
							.frame(width: 6, height: 6)
							.position(pt)
					}
				}
			}
		}
	}
	
	private func diamond(size: CGFloat, color: Color) -> some View {
		Rectangle()
			.fill(color)
			.frame(width: size, height: size)
			.rotationEffect(.degrees(45))
	}
}
