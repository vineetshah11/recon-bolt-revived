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
						CountdownText(target: actEndDate)
						Image(systemName: "clock")
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				}
			}
			
			if let top = summaries.first {
				NavigationLink {
					AgentMasteryDetailView(summary: top, actEndDate: actEndDate)
				} label: {
					AgentMasteryHeroCard(summary: top)
				}
				.buttonStyle(.plain)
			} else {
				Text("Play matches to track your Agent Mastery progress and lifetime laurels.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.padding(.vertical, 8)
			}
			
			ForEach(summaries.dropFirst().prefix(2)) { summary in
				NavigationLink {
					AgentMasteryDetailView(summary: summary, actEndDate: actEndDate)
				} label: {
					compactRow(for: summary)
				}
				.buttonStyle(.plain)
			}
			
			if !summaries.isEmpty {
				NavigationLink {
					AgentMasteryListView(summaries: summaries, actEndDate: actEndDate)
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
				
				if summary.currentActMP > 0 || summary.currentActLevel > 0 {
					Text("\(summary.xpInCurrentLevel.formatted()) / \(summary.nextLevelMPNeeded.formatted()) MP to Act Level \(summary.currentActLevel + 1)")
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

struct AgentMasteryHeroCard: View {
	var summary: AgentMasterySummary
	var showProgressBar: Bool = true
	
	var body: some View {
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
						if !showProgressBar, let role = summary.roleName, !role.isEmpty {
							Text(role)
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					Spacer()
				}
				.padding(14)
				.frame(minHeight: 118)
				
				AgentImage.fullPortrait(summary.agentID)
					.frame(width: 118, height: 118)
					.clipped()
				
				let displayBadgeLevel = max(summary.currentActLevel, summary.lastActLevel)
				if displayBadgeLevel > 0 {
					Text(String(format: "%02d", displayBadgeLevel))
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
			
			if showProgressBar {
				Text("\(summary.xpInCurrentLevel.formatted()) / \(summary.nextLevelMPNeeded.formatted()) MP to Act Level \(summary.currentActLevel + 1)")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				
				MasterySegmentedBar(
					actLevel: summary.currentActLevel,
					inLevelProgress: summary.levelProgress
				)
			}
		}
		.padding(showProgressBar ? 12 : 0)
		.background(
			showProgressBar ? Color.tertiaryGroupedBackground.opacity(0.65) : Color.clear,
			in: RoundedRectangle(cornerRadius: 12)
		)
	}
}

struct AgentMasteryDetailView: View {
	var summary: AgentMasterySummary
	var actEndDate: Date?
	
	@Environment(\.assets) private var assets
	
	private var portraitTierLevel: Int {
		max(summary.currentActLevel, summary.lastActLevel)
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				AgentMasteryHeroCard(summary: summary, showProgressBar: false)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16))
				
				actLevelsCard
				
				rewardTrackSection
			}
			.padding()
		}
		.background(Color.groupedBackground)
		.navigationTitle(summary.displayName)
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private var actLevelsCard: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack {
				Text("Act Levels")
					.font(.headline)
				Spacer()
				if let actEndDate, actEndDate > Date() {
					HStack(spacing: 4) {
						CountdownText(target: actEndDate)
						Image(systemName: "clock")
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				}
			}
			
			HStack(alignment: .firstTextBaseline) {
				Text("Act Level \(summary.currentActLevel)")
					.font(.title3.bold())
				Spacer()
				Text("\(summary.xpInCurrentLevel.formatted()) / \(summary.nextLevelMPNeeded.formatted()) MP")
					.font(.subheadline.weight(.semibold).monospacedDigit())
					.foregroundStyle(Color.valorantRed)
			}
			
			MasterySegmentedBar(
				actLevel: summary.currentActLevel,
				inLevelProgress: summary.levelProgress
			)
			
			HStack(spacing: 10) {
				ForEach(AgentMasteryCalculator.portraitUpgradeMilestones) { milestone in
					let unlocked = portraitTierLevel >= milestone.level
					VStack(spacing: 6) {
						ZStack(alignment: .topLeading) {
							AgentImage.icon(summary.agentID)
								.frame(width: 68, height: 68)
								.saturation(unlocked ? 1 : 0.45)
								.opacity(unlocked ? 1 : 0.5)
								.background(Color.tertiaryGroupedBackground)
								.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
								.overlay {
									RoundedRectangle(cornerRadius: 10, style: .continuous)
										.strokeBorder(tierAccentColor(for: milestone.level).opacity(unlocked ? 0.9 : 0.4), lineWidth: 1.5)
								}
								.overlay(alignment: .bottomTrailing) {
									Text(String(format: "%02d", milestone.level))
										.font(.system(size: 10, weight: .bold).monospacedDigit())
										.foregroundStyle(.white)
										.padding(.horizontal, 5)
										.padding(.vertical, 2)
										.background(tierAccentColor(for: milestone.level).opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
										.padding(3)
								}
							
							Group {
								if unlocked {
									Image(systemName: "checkmark.circle.fill")
										.foregroundStyle(Color.valorantRed, .white)
										.font(.system(size: 18))
								} else {
									Image(systemName: "lock.fill")
										.font(.system(size: 10, weight: .bold))
										.foregroundStyle(.white)
										.frame(width: 20, height: 20)
										.background(Color.black.opacity(0.72), in: Circle())
								}
							}
							.offset(x: -5, y: -5)
						}
						
						VStack(spacing: 1) {
							Text("Act Level \(milestone.level)")
								.font(.caption2.weight(.semibold))
							Text("\(milestone.cumulativeMP.formatted()) MP")
								.font(.system(size: 10).monospacedDigit())
								.foregroundStyle(.secondary)
						}
					}
					.frame(maxWidth: .infinity)
				}
			}
			.padding(.top, 4)
			
			Text("Act Levels 1, 4, 7, and 10 each unlock a Portrait Upgrade. Upgrades reached last Act stay on the portrait; its level shows from Act Level 1 this Act.")
				.font(.caption)
				.foregroundStyle(.secondary)
			
			Divider()
			
			HStack {
				Label("Last Act's Level", systemImage: "clock.arrow.circlepath")
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(summary.lastActLevel)")
					.font(.subheadline.bold().monospacedDigit())
			}
			
			Text("Act Levels start over every Act. Lifetime Levels never reset.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16))
	}
	
	private var rewardTrackSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .center) {
				Text("Reward Track")
					.font(.title3.bold())
				Spacer()
				VStack(alignment: .trailing, spacing: 2) {
					LaurelBadge(level: summary.lifetimeLevel)
					Text("Lifetime Level")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			.padding(.horizontal, 4)
			
			ForEach(AgentMasteryCalculator.rewardTrackTiers) { tier in
				let isUnlocked = summary.lifetimeLevel >= tier.level
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Text("\(tier.level)")
							.font(.caption.bold().monospacedDigit())
							.frame(width: 24, height: 24)
							.background(
								isUnlocked ? Color.valorantRed : Color.tertiaryGroupedBackground,
								in: Circle()
							)
							.foregroundStyle(isUnlocked ? .white : .secondary)
						
						Text("Lifetime Level \(tier.level)")
							.font(.subheadline.weight(.bold))
						
						Spacer()
						
						if isUnlocked {
							Label("Unlocked", systemImage: "checkmark.circle.fill")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.green)
						} else {
							Label("Not reached", systemImage: "lock.fill")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					
					ForEach(tier.items) { item in
						HStack(spacing: 12) {
							Image(systemName: item.iconName)
								.font(.system(size: 16))
								.foregroundStyle(isUnlocked ? .primary : .secondary)
								.frame(width: 34, height: 34)
								.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8))
							
							VStack(alignment: .leading, spacing: 2) {
								Text(item.title)
									.font(.subheadline.weight(.medium))
									.foregroundStyle(isUnlocked ? .primary : .secondary)
								HStack(spacing: 4) {
									(assets?.currencies[.kingdomCredits]?.displayIcon).view()
										.frame(width: 12, height: 12)
									Text(item.costKC.formatted())
										.font(.caption.monospacedDigit())
										.foregroundStyle(.secondary)
								}
							}
							Spacer()
						}
					}
				}
				.padding(14)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16))
			}
			
			Text("You buy these rewards with Kingdom Credits in VALORANT once the agent reaches their Lifetime Level.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
		}
	}
	
	private func tierAccentColor(for level: Int) -> Color {
		switch level {
		case 1: return .gray
		case 4: return .cyan
		case 7: return .orange
		default: return .purple
		}
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
									.fill(step < actLevel ? Color.valorantRed : Color.valorantRed.opacity(0.85))
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
						.foregroundStyle(actLevel >= 1 ? Color.valorantRed : .secondary)
					Spacer()
					Image(systemName: actLevel >= 4 ? "diamond.fill" : "diamond")
						.foregroundStyle(actLevel >= 4 ? Color.valorantRed : .secondary)
					Spacer()
					Image(systemName: actLevel >= 7 ? "diamond.fill" : "diamond")
						.foregroundStyle(actLevel >= 7 ? Color.valorantRed : .secondary)
					Spacer()
					Image(systemName: actLevel >= 10 ? "diamond.fill" : "diamond")
						.foregroundStyle(actLevel >= 10 ? Color.valorantRed : .secondary)
				}
				.font(.system(size: 8))
				.padding(.horizontal, 12)
			}
		}
	}
}

struct AgentMasterySummaryBox: View {
	var summaries: [AgentMasterySummary]
	var actEndDate: Date? = nil
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			NavigationLink {
				AgentMasteryListView(summaries: summaries, actEndDate: actEndDate)
			} label: {
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
			}
			.buttonStyle(.plain)
			
			let top3 = Array(summaries.prefix(3))
			if top3.isEmpty {
				Text("No agent mastery data available yet.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				HStack(spacing: 12) {
					ForEach(top3) { item in
						NavigationLink {
							AgentMasteryDetailView(summary: item, actEndDate: actEndDate)
						} label: {
							VStack(spacing: 6) {
								ZStack(alignment: .bottomTrailing) {
									AgentImage.icon(item.agentID)
										.frame(width: 54, height: 54)
										.cornerRadius(10)
									let badge = max(item.currentActLevel, item.lastActLevel)
									if badge > 0 {
										Text(String(format: "%02d", badge))
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
						.buttonStyle(.plain)
					}
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
	}
}

struct AgentMasteryListView: View {
	var summaries: [AgentMasterySummary]
	var actEndDate: Date? = nil
	
	@State private var search = ""
	
	var body: some View {
		let filtered = summaries.filter {
			search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)
		}
		List {
			ForEach(filtered) { item in
				Section {
					NavigationLink {
						AgentMasteryDetailView(summary: item, actEndDate: actEndDate)
					} label: {
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
									Text("Act Level \(item.currentActLevel) • \(item.xpInCurrentLevel.formatted()) / \(item.nextLevelMPNeeded.formatted()) MP")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
							
							MasterySegmentedBar(
								actLevel: item.currentActLevel,
								inLevelProgress: item.levelProgress
							)
						}
						.padding(.vertical, 4)
					}
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search agents"))
		.navigationTitle("Agent Mastery")
	}
}
