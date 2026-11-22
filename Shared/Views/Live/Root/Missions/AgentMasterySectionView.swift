import SwiftUI
import ValorantAPI

struct AgentMasterySectionView: View {
	var summaries: [AgentMasterySummary]
	var actEndDate: Date?
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Agent Mastery")
					.font(.headline)
				Spacer()
				if let actEndDate, actEndDate > Date() {
					HStack(spacing: 4) {
						Text(actEndDate, style: .relative)
						Image(systemName: "clock")
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				}
			}
			
			if let top = summaries.first {
				heroCard(for: top)
			} else {
				Text("Play matches to track your Patch 13.06 Agent Mastery progress and lifetime laurels.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.padding(.vertical, 8)
			}
			
			ForEach(summaries.dropFirst().prefix(2)) { summary in
				compactRow(for: summary)
			}
			
			if !summaries.isEmpty {
				NavigationLink {
					AgentMasteryListView(summaries: summaries)
				} label: {
					Text("View Agent Mastery")
						.font(.subheadline.weight(.medium))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 10)
						.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
				}
				.buttonStyle(.plain)
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
	}
	
	private func heroCard(for summary: AgentMasterySummary) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			ZStack(alignment: .bottomTrailing) {
				HStack(alignment: .center) {
					VStack(alignment: .leading, spacing: 6) {
						if summary.lifetimeLevel > 0 {
							LaurelBadge(level: summary.lifetimeLevel)
						}
						Text(summary.displayName.uppercased())
							.font(.title2.weight(.heavy))
						Text(summary.currentActLevel > 0 ? "ACT LEVEL \(summary.currentActLevel)" : "UNRANKED MASTERY")
							.font(.caption.weight(.bold))
							.foregroundStyle(.secondary)
					}
					Spacer()
				}
				.padding(14)
				.frame(minHeight: 112)
				
				AgentImage.fullPortrait(summary.agentID)
					.frame(width: 112, height: 112)
					.clipped()
				
				if summary.currentActLevel > 0 {
					Text(String(format: "%02d", summary.currentActLevel))
						.font(.caption.bold().monospacedDigit())
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
						.padding(8)
				}
			}
			.background(
				LinearGradient(
					colors: [Color.secondaryGroupedBackground, Color.tertiaryGroupedBackground],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				),
				in: RoundedRectangle(cornerRadius: 12)
			)
			
			Text("\(summary.xpInCurrentLevel.formatted()) / \(summary.nextLevelMPNeeded.formatted()) MP to Act Level \(min(10, summary.currentActLevel + 1))")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
			
			MasterySegmentedBar(
				actLevel: summary.currentActLevel,
				inLevelProgress: summary.levelProgress
			)
		}
		.padding(12)
		.background(Color.tertiaryGroupedBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
	}
	
	private func compactRow(for summary: AgentMasterySummary) -> some View {
		HStack(spacing: 12) {
			ZStack(alignment: .bottomTrailing) {
				AgentImage.icon(summary.agentID)
					.frame(width: 46, height: 46)
					.cornerRadius(8)
				if summary.currentActLevel > 0 {
					Text(String(format: "%02d", summary.currentActLevel))
						.font(.system(size: 10, weight: .bold).monospacedDigit())
						.padding(.horizontal, 4)
						.padding(.vertical, 1)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
				}
			}
			
			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text(summary.displayName)
						.font(.subheadline.weight(.semibold))
					Spacer()
					if summary.currentActLevel > 0 {
						Text("Act Level \(summary.currentActLevel)")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else if summary.lifetimeLevel > 0 {
						LaurelBadge(level: summary.lifetimeLevel)
					}
				}
				
				MasterySegmentedBar(
					actLevel: summary.currentActLevel,
					inLevelProgress: summary.levelProgress,
					compact: true
				)
				
				if summary.currentActMP > 0 {
					Text("\(summary.xpInCurrentLevel.formatted()) / \(summary.nextLevelMPNeeded.formatted()) MP to Act Level \(min(10, summary.currentActLevel + 1))")
						.font(.caption2.monospacedDigit())
						.foregroundStyle(.secondary)
				} else if summary.lastActLevel > 0 {
					Text("Last Act: Act Level \(summary.lastActLevel)")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
		}
		.padding(.vertical, 4)
	}
}

struct LaurelBadge: View {
	var level: Int
	
	var body: some View {
		HStack(spacing: 3) {
			Image(systemName: "laurel.leading")
				.font(.caption2)
			Text("\(level)")
				.font(.caption.bold().monospacedDigit())
			Image(systemName: "laurel.trailing")
				.font(.caption2)
		}
		.foregroundStyle(.secondary)
	}
}

struct MasterySegmentedBar: View {
	var actLevel: Int
	var inLevelProgress: Double
	var compact = false
	
	var body: some View {
		VStack(spacing: compact ? 0 : 4) {
			HStack(spacing: 4) {
				ForEach(0..<10, id: \.self) { step in
					let fill: Double = step < actLevel ? 1 : (step == actLevel ? inLevelProgress : 0)
					GeometryReader { geo in
						ZStack(alignment: .leading) {
							Capsule()
								.fill(Color.secondary.opacity(0.25))
							if fill > 0 {
								Capsule()
									.fill(step < actLevel ? Color.primary : Color.valorantRed)
									.frame(width: geo.size.width * CGFloat(min(1, max(0, fill))))
							}
						}
					}
					.frame(height: compact ? 4 : 5)
				}
			}
			
			if !compact {
				HStack {
					Image(systemName: actLevel >= 1 ? "diamond.fill" : "diamond")
					Spacer()
					Image(systemName: actLevel >= 4 ? "diamond.fill" : "diamond")
					Spacer()
					Image(systemName: actLevel >= 7 ? "diamond.fill" : "diamond")
					Spacer()
					Image(systemName: actLevel >= 10 ? "diamond.fill" : "diamond")
				}
				.font(.system(size: 8))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 12)
			}
		}
	}
}

struct AgentMasterySummaryBox: View {
	var summaries: [AgentMasterySummary]
	
	var body: some View {
		NavigationLink {
			AgentMasteryListView(summaries: summaries)
		} label: {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Image(systemName: "chevron.right")
						.font(.caption.bold())
						.foregroundStyle(Color.valorantRed)
					Text("Agent Mastery")
						.font(.headline)
					Spacer()
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				
				let top3 = Array(summaries.prefix(3))
				if top3.isEmpty {
					Text("No agent mastery data from cached matches yet.")
						.font(.caption)
						.foregroundStyle(.secondary)
				} else {
					HStack(spacing: 12) {
						ForEach(top3) { item in
							VStack(spacing: 6) {
								ZStack(alignment: .bottomTrailing) {
									AgentImage.icon(item.agentID)
										.frame(width: 54, height: 54)
										.cornerRadius(10)
									if item.currentActLevel > 0 {
										Text(String(format: "%02d", item.currentActLevel))
											.font(.system(size: 10, weight: .bold).monospacedDigit())
											.padding(.horizontal, 4)
											.padding(.vertical, 1)
											.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
									}
								}
								Text(item.displayName)
									.font(.caption.weight(.semibold))
									.lineLimit(1)
								LaurelBadge(level: item.lifetimeLevel)
							}
							.frame(maxWidth: .infinity)
						}
					}
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
		}
		.buttonStyle(.plain)
	}
}

struct AgentMasteryListView: View {
	var summaries: [AgentMasterySummary]
	
	@State private var search = ""
	
	var body: some View {
		let filtered = summaries.filter {
			search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)
		}
		List {
			ForEach(filtered) { item in
				Section {
					VStack(alignment: .leading, spacing: 10) {
						HStack(spacing: 12) {
							AgentImage.icon(item.agentID)
								.frame(width: 52, height: 52)
								.cornerRadius(10)
							VStack(alignment: .leading, spacing: 3) {
								HStack {
									Text(item.displayName)
										.font(.headline)
									Spacer()
									LaurelBadge(level: item.lifetimeLevel)
								}
								Text("Act Level \(item.currentActLevel) • \(item.currentActMP.formatted()) MP")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						
						MasterySegmentedBar(
							actLevel: item.currentActLevel,
							inLevelProgress: item.levelProgress
						)
						
						if item.matchesPlayed > 0 {
							HStack {
								statChip(label: "Matches", value: "\(item.matchesPlayed)")
								statChip(label: "Win %", value: String(format: "%.0f%%", item.winRate * Double(100)))
								statChip(label: "ACS", value: "\(item.averageACS)")
								statChip(label: "K/D", value: String(format: "%.2f", item.kdRatio))
							}
						}
					}
					.padding(.vertical, 4)
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search agents"))
		.navigationTitle("Agent Mastery")
	}
	
	private func statChip(label: LocalizedStringKey, value: String) -> some View {
		VStack(spacing: 2) {
			Text(value)
				.font(.caption.bold().monospacedDigit())
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 6)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8))
	}
}
