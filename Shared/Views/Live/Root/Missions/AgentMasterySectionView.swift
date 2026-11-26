import SwiftUI
import ValorantAPI

enum MasteryTierStyle {
	static func color(for level: Int) -> Color {
		switch level {
		case ..<4:
			return Color(red: 0.45, green: 0.47, blue: 0.50)
		case 4..<7:
			return Color(red: 0.16, green: 0.62, blue: 0.72)
		case 7..<10:
			return Color(red: 0.80, green: 0.56, blue: 0.18)
		default:
			return Color(red: 0.64, green: 0.28, blue: 0.78)
		}
	}
}

struct MasteryCornerRibbonShape: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: CGPoint(x: rect.width * 0.28, y: 0))
		path.addLine(to: CGPoint(x: rect.maxX, y: 0))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		path.addLine(to: CGPoint(x: 0, y: rect.maxY))
		path.closeSubpath()
		return path
	}
}

struct MasteryAgentIcon: View {
	let agentID: Agent.ID
	let actLevel: Int
	var size: CGFloat = 48
	var cornerRadius: CGFloat = 8
	
	var body: some View {
		let tierColor = MasteryTierStyle.color(for: actLevel)
		AgentImage.icon(agentID)
			.frame(width: size, height: size)
			.background(Color(red: 0.14, green: 0.17, blue: 0.20))
			.overlay(alignment: .bottom) {
				if actLevel > 0 {
					Rectangle()
						.fill(tierColor)
						.frame(height: 1.5)
				}
			}
			.overlay(alignment: .bottomTrailing) {
				if actLevel > 0 {
					Text(String(format: "%02d", actLevel))
						.font(.system(size: max(9, size * 0.20), weight: .bold).monospacedDigit())
						.foregroundStyle(.white)
						.padding(.leading, max(6, size * 0.14))
						.padding(.trailing, max(4, size * 0.08))
						.padding(.vertical, 2)
						.background {
							MasteryCornerRibbonShape()
								.fill(tierColor)
						}
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
					.stroke(Color.white.opacity(0.10), lineWidth: 1)
			}
	}
}

struct AgentMasterySectionView: View {
	var summaries: [AgentMasterySummary]
	var actEndDate: Date?
	var isEmbedded: Bool = false
	
	private var displayedSummaries: [AgentMasterySummary] {
		let active = summaries.filter(\.hasMasteryActivity)
		return active.isEmpty ? summaries : active
	}
	
	var body: some View {
		let displayed = displayedSummaries
		
		VStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 14) {
				HStack {
					Text("Agent Mastery")
						.font(.headline)
					Spacer()
					if let actEndDate, actEndDate > Date() {
						HStack(spacing: 5) {
							CountdownText(target: actEndDate)
							Image(systemName: "clock")
						}
						.font(.subheadline.monospacedDigit())
						.foregroundStyle(.secondary)
					}
				}
				
				if let top = displayed.first {
					NavigationLink {
						AgentMasteryDetailView(summary: top, actEndDate: actEndDate)
					} label: {
						AgentMasteryHeroCard(summary: top, isEmbedded: isEmbedded)
					}
					.buttonStyle(.plain)
				} else {
					Text("Play matches to track your Agent Mastery progress and lifetime laurels.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.padding(.vertical, 8)
				}
				
				ForEach(displayed.dropFirst().prefix(2)) { summary in
					NavigationLink {
						AgentMasteryDetailView(summary: summary, actEndDate: actEndDate)
					} label: {
						AgentMasteryCompactRow(summary: summary)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(14)
			.background(
				Color.tertiaryGroupedBackground.opacity(0.65),
				in: RoundedRectangle(cornerRadius: 16, style: .continuous)
			)
			
			if !summaries.isEmpty {
				NavigationLink {
					AgentMasteryListView(summaries: summaries, actEndDate: actEndDate)
				} label: {
					Text("View Agent Mastery")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.primary)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 12)
						.background(Color(.systemFill), in: Capsule())
				}
				.buttonStyle(.plain)
			}
		}
	}
}

struct AgentMasteryCompactRow: View {
	var summary: AgentMasterySummary
	
	var body: some View {
		HStack(spacing: 12) {
			MasteryAgentIcon(
				agentID: summary.agentID,
				actLevel: summary.currentActLevel,
				size: 48,
				cornerRadius: 8
			)
			
			VStack(alignment: .leading, spacing: 5) {
				HStack {
					Text(summary.displayName)
						.font(.body.weight(.semibold))
						.foregroundStyle(.primary)
					Spacer()
					if summary.currentActLevel > 0 {
						Text("Act Level \(summary.currentActLevel)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					} else if summary.lifetimeLevel > 0 {
						LaurelBadge(level: summary.lifetimeLevel, tint: .secondary, fontSize: 13)
					}
				}
				
				MasterySegmentedBar(
					actLevel: summary.currentActLevel,
					inLevelProgress: summary.levelProgress,
					fillColor: .accentColor,
					compact: true
				)
				
				if summary.currentActMP > 0 || summary.currentActLevel > 0 {
					Text("\(summary.xpInCurrentLevel.formatted()) / \(summary.nextLevelMPNeeded.formatted()) MP to Act Level \(summary.currentActLevel + 1)")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				} else if summary.lastActLevel > 0 {
					Text("Last Act: Act Level \(summary.lastActLevel)")
						.font(.caption)
						.foregroundStyle(.secondary)
				} else {
					Text("Not played this Act")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.padding(.vertical, 2)
	}
}

struct AgentMasteryHeroCard: View {
	var summary: AgentMasterySummary
	var showProgressBar: Bool = true
	var isEmbedded: Bool = false
	
	var body: some View {
		let badgeLevel = showProgressBar ? summary.currentActLevel : max(summary.currentActLevel, summary.lastActLevel)
		let tierColor = badgeLevel > 0 ? MasteryTierStyle.color(for: badgeLevel) : Color.white.opacity(0.18)
		
		VStack(alignment: .leading, spacing: 0) {
			Color.clear
				.frame(height: 132)
				.frame(maxWidth: .infinity)
				.background {
					LinearGradient(
						colors: [
							Color(red: 0.08, green: 0.11, blue: 0.15),
							Color(red: 0.13, green: 0.19, blue: 0.25),
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					)
				}
				.overlay(alignment: .trailing) {
					AgentImage.fullPortrait(summary.agentID)
						.scaledToFill()
						.frame(width: 152, height: 156, alignment: .top)
						.offset(x: 6, y: 8)
				}
				.clipped()
				.overlay(alignment: .leading) {
					VStack(alignment: .leading, spacing: 6) {
						if summary.lifetimeLevel > 0 {
							LaurelBadge(level: summary.lifetimeLevel, tint: .white.opacity(0.92), fontSize: 13)
						}
						Text(summary.displayName.uppercased())
							.font(.system(size: 28, weight: .black))
							.foregroundStyle(.white)
							.lineLimit(1)
							.minimumScaleFactor(0.7)
						Text("ACT LEVEL \(summary.currentActLevel)")
							.font(.system(size: 13, weight: .bold))
							.tracking(0.3)
							.foregroundStyle(.white.opacity(0.92))
						if !showProgressBar, let role = summary.roleName, !role.isEmpty {
							Text(role)
								.font(.caption)
								.foregroundStyle(.white.opacity(0.7))
						}
					}
					.padding(.horizontal, 14)
					.padding(.vertical, 14)
				}
				.overlay(alignment: .bottomTrailing) {
					if badgeLevel > 0 {
						Text(String(format: "%02d", badgeLevel))
							.font(.system(size: 14, weight: .bold).monospacedDigit())
							.foregroundStyle(.white)
							.padding(.leading, 8)
							.frame(width: 44, height: 24)
							.background {
								MasteryCornerRibbonShape()
									.fill(tierColor)
							}
					}
				}
			
			if showProgressBar || badgeLevel > 0 {
				Rectangle()
					.fill(tierColor)
					.frame(height: 2.5)
			}
			
			if showProgressBar {
				VStack(alignment: .leading, spacing: 10) {
					Group {
						if summary.currentActLevel > 0 || summary.currentActMP > 0 {
							Text("\(summary.xpInCurrentLevel.formatted()) / \(summary.nextLevelMPNeeded.formatted()) MP to Act Level \(summary.currentActLevel + 1)")
						} else if summary.lastActLevel > 0 {
							Text("Last Act: Act Level \(summary.lastActLevel)")
						} else {
							Text("Not played this Act")
						}
					}
					.font(.caption.weight(.medium).monospacedDigit())
					.foregroundStyle(.white.opacity(0.92))
					
					MasterySegmentedBar(
						actLevel: summary.currentActLevel,
						inLevelProgress: summary.levelProgress,
						fillColor: .white,
						compact: false
					)
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 12)
				.background(Color(red: 0.06, green: 0.07, blue: 0.09))
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.stroke(Color.white.opacity(0.14), lineWidth: 1)
		}
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
					.foregroundStyle(Color.accentColor)
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
										.foregroundStyle(Color.accentColor, .white)
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
								isUnlocked ? Color.accentColor : Color.tertiaryGroupedBackground,
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
		MasteryTierStyle.color(for: level)
	}
}

struct LaurelBadge: View {
	var level: Int
	var tint: Color = .secondary
	var fontSize: CGFloat = 13
	
	var body: some View {
		HStack(spacing: 3) {
			Image(systemName: "laurel.leading")
			Text("\(level)")
				.fontWeight(.bold)
				.monospacedDigit()
			Image(systemName: "laurel.trailing")
		}
		.font(.system(size: fontSize))
		.foregroundStyle(tint)
	}
}

struct MasterySegmentedBar: View {
	var actLevel: Int
	var inLevelProgress: Double
	var fillColor: Color = .accentColor
	var compact: Bool = false
	
	private static let milestoneByColumn: [Int: Int] = [
		0: 1,
		3: 4,
		6: 7,
		9: 10,
	]
	
	var body: some View {
		VStack(spacing: compact ? 0 : 6) {
			HStack(spacing: 4) {
				ForEach(0..<10, id: \.self) { step in
					let fill: Double = step < actLevel ? 1 : (step == actLevel ? inLevelProgress : 0)
					ZStack(alignment: .leading) {
						Capsule()
							.fill(Color.white.opacity(0.14))
						if fill > 0 {
							HorizontalFillCapsuleShape(fraction: fill, minWidth: 3)
								.fill(fillColor)
						}
					}
					.frame(height: compact ? 4 : 5)
				}
			}
			
			if !compact {
				HStack(spacing: 4) {
					ForEach(0..<10, id: \.self) { column in
						if let milestone = Self.milestoneByColumn[column] {
							let reached = actLevel >= milestone
							Image(systemName: reached ? "diamond.fill" : "diamond")
								.font(.system(size: 8, weight: .semibold))
								.foregroundStyle(reached ? fillColor : .secondary)
								.frame(maxWidth: .infinity)
						} else {
							Color.clear
								.frame(maxWidth: .infinity, maxHeight: 8)
						}
					}
				}
			}
		}
	}
}

struct AgentMasterySummaryBox: View {
	var summaries: [AgentMasterySummary]
	var actEndDate: Date? = nil
	
	@State private var isExpanded = false
	
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
						Text("Agent Mastery")
							.font(.headline)
							.foregroundStyle(.primary)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				
				Spacer()
				
				NavigationLink {
					AgentMasteryListView(summaries: summaries, actEndDate: actEndDate)
				} label: {
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
						.padding(.leading, 8)
				}
				.buttonStyle(.plain)
			}
			
			if summaries.isEmpty {
				Text("No agent mastery data available yet.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else if !isExpanded {
				HStack(spacing: 12) {
					ForEach(Array(summaries.prefix(3))) { item in
						NavigationLink {
							AgentMasteryDetailView(summary: item, actEndDate: actEndDate)
						} label: {
							VStack(spacing: 6) {
								MasteryAgentIcon(
									agentID: item.agentID,
									actLevel: item.currentActLevel,
									size: 56,
									cornerRadius: 10
								)
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
			} else {
				if let top = summaries.first {
					NavigationLink {
						AgentMasteryDetailView(summary: top, actEndDate: actEndDate)
					} label: {
						AgentMasteryHeroCard(summary: top, isEmbedded: true)
					}
					.buttonStyle(.plain)
				}
				
				ForEach(Array(summaries.dropFirst().prefix(2))) { summary in
					NavigationLink {
						AgentMasteryDetailView(summary: summary, actEndDate: actEndDate)
					} label: {
						AgentMasteryCompactRow(summary: summary)
					}
					.buttonStyle(.plain)
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
}

struct AgentMasteryListView: View {
	var summaries: [AgentMasterySummary]
	var actEndDate: Date? = nil
	
	private var playedSummaries: [AgentMasterySummary] {
		summaries.filter(\.hasMasteryActivity)
	}
	
	private var unplayedSummaries: [AgentMasterySummary] {
		summaries
			.filter { !$0.hasMasteryActivity }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
	}
	
	var body: some View {
		let played = playedSummaries
		let unplayed = unplayedSummaries
		
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 14) {
				ForEach(played) { item in
					NavigationLink {
						AgentMasteryDetailView(summary: item, actEndDate: actEndDate)
					} label: {
						playedCard(for: item)
					}
					.buttonStyle(.plain)
				}
				
				if !unplayed.isEmpty {
					Text("Not Played Yet")
						.font(.title3.bold())
						.foregroundStyle(.primary)
						.padding(.top, 8)
					
					LazyVGrid(
						columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
						spacing: 12
					) {
						ForEach(unplayed) { item in
							NavigationLink {
								AgentMasteryDetailView(summary: item, actEndDate: actEndDate)
							} label: {
								unplayedCard(for: item)
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.top, 12)
			.padding(.bottom, 24)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Agent Mastery")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private func playedCard(for item: AgentMasterySummary) -> some View {
		let hasCurrentActProgress = item.currentActLevel > 0 || item.currentActMP > 0
		
		return VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .center, spacing: 12) {
				MasteryAgentIcon(
					agentID: item.agentID,
					actLevel: item.currentActLevel,
					size: 52,
					cornerRadius: 10
				)
				
				VStack(alignment: .leading, spacing: 3) {
					Text(item.displayName)
						.font(.headline)
						.foregroundStyle(.primary)
					Text(hasCurrentActProgress ? "Act Level \(item.currentActLevel)" : "Not played this Act")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				
				Spacer(minLength: 8)
				
				HStack(spacing: 10) {
					VStack(alignment: .trailing, spacing: 2) {
						LaurelBadge(level: item.lifetimeLevel, tint: .primary, fontSize: 15)
						Text("Lifetime Level")
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
					
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.tertiary)
				}
			}
			
			MasterySegmentedBar(
				actLevel: item.currentActLevel,
				inLevelProgress: item.levelProgress,
				fillColor: .accentColor,
				compact: false
			)
			
			if hasCurrentActProgress {
				Text("\(item.xpInCurrentLevel.formatted()) / \(item.nextLevelMPNeeded.formatted()) MP to Act Level \(item.currentActLevel + 1)")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			} else if item.lastActLevel > 0 {
				Text("Last Act: Act Level \(item.lastActLevel)")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(14)
		.background(
			Color.secondaryGroupedBackground,
			in: RoundedRectangle(cornerRadius: 16, style: .continuous)
		)
	}
	
	private func unplayedCard(for item: AgentMasterySummary) -> some View {
		HStack(spacing: 10) {
			MasteryAgentIcon(
				agentID: item.agentID,
				actLevel: 0,
				size: 36,
				cornerRadius: 8
			)
			
			Text(item.displayName)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.primary)
				.lineLimit(1)
			
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 10)
		.background(
			Color.secondaryGroupedBackground,
			in: RoundedRectangle(cornerRadius: 14, style: .continuous)
		)
	}
}
