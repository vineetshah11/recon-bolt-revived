import SwiftUI
import Charts
import ValorantAPI

@available(iOS 16.0, *)
struct KDRatioView: View {
	var statistics: Statistics
	
	private enum TimelineMetric: String, CaseIterable, Identifiable {
		case kd = "K/D"
		case kad = "KAD"
		var id: String { rawValue }
	}
	
	@State private var timelineMetric: TimelineMetric = .kd
	@Environment(\.assets) private var assets
	
	private var kdStats: Statistics.KDRatio { statistics.kdRatio }
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				timelineSection
				
				byAgentSection
				
				byMapSection
				
				if !kdStats.byWeapon.isEmpty {
					byWeaponSection
				}
				
				byPremadeSection
				
				bestMatchesSection
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Kill Death Ratio")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	// MARK: - Sections
	
	private var timelineSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("PERFORMANCE TIMELINE")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				Spacer()
				Picker("Metric", selection: $timelineMetric) {
					ForEach(TimelineMetric.allCases) { metric in
						Text(metric.rawValue).tag(metric)
					}
				}
				.pickerStyle(.segmented)
				.frame(width: 130)
			}
			.padding(.horizontal, 4)
			
			VStack(alignment: .leading, spacing: 10) {
				if kdStats.byMatch.isEmpty {
					Text("No match combat data available.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.padding(20)
				} else {
					let entries = kdStats.byMatch
					Chart {
						RuleMark(y: .value("Break-even", Double(1.0)))
							.foregroundStyle(.secondary.opacity(0.45))
							.lineStyle(.init(lineWidth: 1, dash: [4, 3]))
						
						ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
							let val = timelineMetric == .kd ? entry.kd : entry.kad
							LineMark(
								x: .value("Match", index + 1),
								y: .value(timelineMetric.rawValue, val)
							)
							.foregroundStyle(Color.accentColor)
							.interpolationMethod(.catmullRom)
							
							AreaMark(
								x: .value("Match", index + 1),
								y: .value(timelineMetric.rawValue, val)
							)
							.foregroundStyle(
								LinearGradient(
									colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
									startPoint: .top,
									endPoint: .bottom
								)
							)
							.interpolationMethod(.catmullRom)
						}
					}
					.frame(height: 170)
					.chartYAxis {
						AxisMarks(position: .leading)
					}
					.chartXAxis(.hidden)
					
					HStack {
						Label("Overall K/D: \(String(format: "%.2f", statistics.overview.kdRatio))", systemImage: "scope")
						Spacer()
						Text("KAD: \(String(format: "%.2f", statistics.overview.kadRatio))")
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	@ViewBuilder
	private var byAgentSection: some View {
		let rows = kdStats.byAgent.sorted { $0.value.matches > $1.value.matches }
		if !rows.isEmpty {
			VStack(alignment: .leading, spacing: 8) {
				Text("BY AGENT")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				VStack(spacing: 0) {
					ForEach(Array(rows.enumerated()), id: \.element.key) { index, item in
						HStack(spacing: 10) {
							AgentImage.icon(item.key, teamID: nil)
								.frame(width: 34, height: 34)
								.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8))
								.clipShape(RoundedRectangle(cornerRadius: 8))
							
							VStack(alignment: .leading, spacing: 2) {
								AgentLabel(agent: item.key)
									.font(.subheadline.weight(.semibold))
								Text("\(item.value.matches) match\(item.value.matches == 1 ? "" : "es") · \(Int(item.value.winRate.rounded()))% WR")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							VStack(alignment: .trailing, spacing: 2) {
								Text(String(format: "%.2f K/D", item.value.kd))
									.font(.subheadline.weight(.bold).monospacedDigit())
									.foregroundStyle(item.value.kd >= Double(1.0) ? Color.valorantBlue : Color.valorantRed)
								Text("ACS \(item.value.acs) · HS \(Int(item.value.hsPercent.rounded()))%")
									.font(.caption2.monospacedDigit())
									.foregroundStyle(.secondary)
							}
						}
						.padding(14)
						
						if index < rows.count - 1 {
							Divider().opacity(0.22).padding(.leading, 58)
						}
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	@ViewBuilder
	private var byMapSection: some View {
		let rows = kdStats.byMap.sorted { $0.value.matches > $1.value.matches }
		if !rows.isEmpty {
			VStack(alignment: .leading, spacing: 8) {
				Text("BY MAP")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				VStack(spacing: 0) {
					ForEach(Array(rows.enumerated()), id: \.element.key) { index, item in
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(assets?.maps[item.key]?.displayName ?? item.key.rawValue)
									.font(.subheadline.weight(.semibold))
								Text("\(item.value.wins)W – \(item.value.losses)L · \(Int(item.value.winRate.rounded()))%")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							VStack(alignment: .trailing, spacing: 2) {
								Text(String(format: "%.2f K/D", item.value.kd))
									.font(.subheadline.weight(.bold).monospacedDigit())
									.foregroundStyle(item.value.kd >= Double(1.0) ? Color.valorantBlue : Color.valorantRed)
								Text("ADR \(item.value.adr) · KAD \(String(format: "%.2f", item.value.kad))")
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
	}
	
	@ViewBuilder
	private var byWeaponSection: some View {
		let rows = kdStats.byWeapon.sorted { $0.value.kills > $1.value.kills }
		VStack(alignment: .leading, spacing: 8) {
			Text("BY WEAPON")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				ForEach(Array(rows.prefix(12).enumerated()), id: \.element.key) { index, item in
					HStack(spacing: 12) {
						WeaponImage.killStreamIcon(item.key)
							.scaledToFit()
							.foregroundStyle(.secondary)
							.frame(width: 52, height: 20)
						
						Stats.WeaponLabel(weapon: item.key)
							.font(.subheadline.weight(.semibold))
						
						Spacer()
						
						VStack(alignment: .trailing, spacing: 2) {
							Text("\(item.value.kills) kills")
								.font(.subheadline.weight(.bold).monospacedDigit())
							Text("HS \(Int(item.value.hsPercent.rounded()))% · \(item.value.damage) dmg")
								.font(.caption2.monospacedDigit())
								.foregroundStyle(.secondary)
						}
					}
					.padding(14)
					
					if index < min(rows.count, 12) - 1 {
						Divider().opacity(0.22).padding(.leading, 14)
					}
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	@ViewBuilder
	private var byPremadeSection: some View {
		let rows = kdStats.byPremade.sorted { $0.value.matches > $1.value.matches }
		VStack(alignment: .leading, spacing: 8) {
			Text("BY PREMADE TEAMMATE")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			if rows.isEmpty {
				Text("No games played with premade teammates.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.padding(16)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			} else {
				VStack(spacing: 0) {
					ForEach(Array(rows.prefix(8).enumerated()), id: \.element.key) { index, item in
						HStack {
							UserLabel(userID: item.key)
								.font(.subheadline.weight(.semibold))
							Spacer()
							VStack(alignment: .trailing, spacing: 2) {
								Text("\(item.value.matches) games · \(Int(item.value.winRate.rounded()))% WR")
									.font(.caption.weight(.semibold).monospacedDigit())
								Text(String(format: "%.2f K/D", item.value.kd))
									.font(.caption2.monospacedDigit())
									.foregroundStyle(.secondary)
							}
						}
						.padding(14)
						
						if index < min(rows.count, 8) - 1 {
							Divider().opacity(0.22).padding(.leading, 14)
						}
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	@ViewBuilder
	private var bestMatchesSection: some View {
		let topMatches = kdStats.byMatch.sorted { lhs, rhs in
			if lhs.kd != rhs.kd { return lhs.kd > rhs.kd }
			return lhs.kills > rhs.kills
		}
		if !topMatches.isEmpty {
			VStack(alignment: .leading, spacing: 8) {
				Text("YOUR BEST MATCHES")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				VStack(spacing: 0) {
					ForEach(Array(topMatches.prefix(8).enumerated()), id: \.element.id) { index, entry in
						NavigationLink {
							MatchDetailsContainer(matchID: entry.id, userID: statistics.userID)
						} label: {
							HStack(spacing: 10) {
								if let agentID = entry.agentID {
									AgentImage.icon(agentID, teamID: nil)
										.frame(width: 32, height: 32)
										.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 7))
										.clipShape(RoundedRectangle(cornerRadius: 7))
								}
								
								VStack(alignment: .leading, spacing: 2) {
									Text(assets?.maps[entry.mapID]?.displayName ?? entry.mapID.rawValue)
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(.primary)
									Text(entry.startTime.formatted(date: .abbreviated, time: .shortened))
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								
								Spacer()
								
								VStack(alignment: .trailing, spacing: 2) {
									Text(String(format: "%.2f K/D", entry.kd))
										.font(.subheadline.weight(.bold).monospacedDigit())
										.foregroundStyle(Color.valorantBlue)
									Text("\(entry.kills)/\(entry.deaths)/\(entry.assists) · \(entry.acs) ACS")
										.font(.caption2.monospacedDigit())
										.foregroundStyle(.secondary)
								}
								
								Image(systemName: "chevron.right")
									.font(.caption2.weight(.semibold))
									.foregroundStyle(.secondary)
							}
							.padding(14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						
						if index < min(topMatches.count, 8) - 1 {
							Divider().opacity(0.22).padding(.leading, 56)
						}
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	// MARK: - Overview Preview
	
	static func overview(statistics: Statistics) -> some View {
		let entries = statistics.kdRatio.byMatch
		return Group {
			if entries.isEmpty {
				Text("Not enough data!")
					.font(.caption)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, minHeight: 80)
			} else {
				let plotted = entries.count == 1 ? [entries[0], entries[0]] : entries
				Chart {
					RuleMark(y: .value("Break-even", Double(1.0)))
						.foregroundStyle(.secondary.opacity(0.4))
						.lineStyle(.init(lineWidth: 1, dash: [3, 3]))
					
					ForEach(Array(plotted.enumerated()), id: \.offset) { index, entry in
						LineMark(
							x: .value("Match", index),
							y: .value("K/D", entry.kd)
						)
						.foregroundStyle(Color.accentColor)
						.interpolationMethod(.catmullRom)
						
						AreaMark(
							x: .value("Match", index),
							y: .value("K/D", entry.kd)
						)
						.foregroundStyle(
							LinearGradient(
								colors: [Color.accentColor.opacity(0.26), Color.accentColor.opacity(0.02)],
								startPoint: .top,
								endPoint: .bottom
							)
						)
						.interpolationMethod(.catmullRom)
					}
				}
				.frame(height: 110)
			}
		}
	}
}
