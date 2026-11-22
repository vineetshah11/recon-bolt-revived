import SwiftUI
import ValorantAPI

struct AccoladesSummaryBox: View {
	var userID: User.ID
	var matches: [MatchDetails]
	var report: AccoladesReport
	
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
						Text("Accolades")
							.font(.headline)
							.foregroundStyle(.primary)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				
				Spacer()
				
				NavigationLink {
					AccoladesView(userID: userID, matches: matches)
				} label: {
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
						.padding(.leading, 8)
				}
				.buttonStyle(.plain)
			}
			
			HStack {
				Text("This Act")
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(report.totalEarned) earned")
					.font(.caption.weight(.semibold).monospacedDigit())
			}
			
			if report.earnedItems.isEmpty {
				Text("Play matches in the current Act to earn performance accolades.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else if !isExpanded {
				HStack(spacing: 12) {
					ForEach(Array(report.earnedItems.prefix(3))) { item in
						accoladeCircleLink(item)
					}
				}
			} else {
				LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
					ForEach(report.earnedItems) { item in
						accoladeCircleLink(item)
					}
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func accoladeCircleLink(_ item: AccoladeSummary) -> some View {
		NavigationLink {
			AccoladeDetailView(
				userID: userID,
				item: item,
				totalCachedMatches: matches.count
			)
		} label: {
			VStack(spacing: 6) {
				ZStack {
					Circle()
						.fill(Color.accentColor)
						.frame(width: 44, height: 44)
					Image(systemName: item.type.iconName)
						.font(.system(size: 18, weight: .bold))
						.foregroundStyle(.white)
				}
				Text("×\(item.count)")
					.font(.subheadline.bold().monospacedDigit())
				Text(item.type.title)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}

struct AccoladesView: View {
	enum Scope: String, CaseIterable, Identifiable {
		case thisAct = "This Act"
		case allActs = "All Acts"
		
		var id: String { rawValue }
	}
	
	var userID: User.ID
	var matches: [MatchDetails]
	
	@Environment(\.seasons) private var seasons
	@State private var scope: Scope = .thisAct
	
	private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
	
	var body: some View {
		let report = AccoladesCalculator.compute(
			userID: userID,
			matches: matches,
			act: scope == .thisAct ? seasons?.currentAct() : nil,
			seasons: seasons
		)
		
		ScrollView {
			VStack(spacing: 14) {
				Picker("Scope", selection: $scope) {
					ForEach(Scope.allCases) { item in
						Text(item.rawValue).tag(item)
					}
				}
				.pickerStyle(.segmented)
				
				VStack(alignment: .leading, spacing: 4) {
					Text("\(report.totalEarned) earned")
						.font(.title2.bold().monospacedDigit())
					Text("\(report.earnedTypesCount) of \(report.totalTypesCount) accolades")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				
				LazyVGrid(columns: columns, spacing: 10) {
					ForEach(report.allItems) { item in
						NavigationLink {
							AccoladeDetailView(
								userID: userID,
								item: item,
								totalCachedMatches: matches.count
							)
						} label: {
							accoladeGridCard(item)
						}
						.buttonStyle(.plain)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Accolades")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private func accoladeGridCard(_ item: AccoladeSummary) -> some View {
		let earned = item.count > 0
		return VStack(spacing: 7) {
			ZStack {
				Circle()
					.fill(earned ? Color.accentColor : Color.secondary.opacity(0.18))
					.frame(width: 46, height: 46)
				Image(systemName: item.type.iconName)
					.font(.system(size: 20, weight: .bold))
					.foregroundStyle(earned ? Color.white : Color.secondary.opacity(0.65))
			}
			
			Text(item.type.title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(earned ? .primary : .secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
			
			Text("×\(item.count)")
				.font(.subheadline.bold().monospacedDigit())
				.foregroundStyle(earned ? .primary : .secondary)
			
			Group {
				if let best = item.bestValue, earned {
					Text("Best \(item.type.formattedValue(best))")
				} else {
					Text("Not earned yet")
				}
			}
			.font(.caption2.monospacedDigit())
			.foregroundStyle(.secondary)
			.lineLimit(1)
			.minimumScaleFactor(0.8)
		}
		.frame(maxWidth: .infinity, minHeight: 132)
		.padding(.horizontal, 6)
		.padding(.vertical, 10)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.opacity(earned ? 1 : 0.72)
	}
}

struct AccoladeDetailView: View {
	var userID: User.ID
	var item: AccoladeSummary
	var totalCachedMatches: Int
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				heroCard
				statsSummaryCard
				if !item.byAct.isEmpty {
					actBreakdownCard
				}
				recentMatchesSection
				
				Text("Accolades are calculated from your cached match details. Open matches in Career to load more history.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.top, 2)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle(item.type.title)
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private var heroCard: some View {
		ZStack(alignment: .topTrailing) {
			LinearGradient(
				colors: [
					Color.accentColor.opacity(0.75),
					Color.accentColor.opacity(0.32),
					Color.secondaryGroupedBackground,
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
			
			Image(systemName: item.type.iconName)
				.font(.system(size: 132, weight: .bold))
				.foregroundStyle(.white.opacity(0.1))
				.offset(x: 24, y: 12)
			
			VStack(alignment: .leading, spacing: 10) {
				ZStack {
					Circle()
						.fill(Color.accentColor)
						.frame(width: 48, height: 48)
					Image(systemName: item.type.iconName)
						.font(.system(size: 21, weight: .bold))
						.foregroundStyle(.white)
				}
				
				Text(item.type.title)
					.font(.title.bold())
					.foregroundStyle(.white)
				
				VStack(alignment: .leading, spacing: 3) {
					Text("HOW TO EARN")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(.white.opacity(0.68))
					Text(item.type.howToEarn)
						.font(.subheadline)
						.foregroundStyle(.white)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(18)
		}
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var statsSummaryCard: some View {
		HStack(spacing: 0) {
			statColumn(
				label: "This Act",
				value: "×\(item.thisActCount)",
				subtitle: item.thisActBest.map { "Best \(item.type.formattedValue($0))" } ?? "—"
			)
			
			Divider().frame(height: 44).opacity(0.35)
			
			statColumn(
				label: "All Acts",
				value: "×\(item.allTimeCount)",
				subtitle: item.allTimeBest.map { "Best \(item.type.formattedValue($0))" } ?? "—"
			)
			
			Divider().frame(height: 44).opacity(0.35)
			
			statColumn(
				label: "Personal Best",
				value: item.allTimeBest.map { item.type.formattedValue($0) } ?? "—",
				subtitle: item.type.unitLabel
			)
		}
		.padding(.vertical, 14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func statColumn(label: String, value: String, subtitle: String) -> some View {
		VStack(spacing: 4) {
			Text(label)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.title2.bold().monospacedDigit())
			Text(subtitle)
				.font(.caption2.monospacedDigit())
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
		}
		.frame(maxWidth: .infinity)
	}
	
	private var actBreakdownCard: some View {
		let maxCount = max(1, item.byAct.map(\.count).max() ?? 1)
		return VStack(alignment: .leading, spacing: 12) {
			Text("Earned by Act")
				.font(.headline)
			
			ForEach(item.byAct) { actRow in
				VStack(alignment: .leading, spacing: 6) {
					HStack {
						Text(actRow.actName)
							.font(.caption.weight(.semibold))
						Spacer()
						Text("×\(actRow.count) · Best \(item.type.formattedValue(actRow.bestValue))")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					}
					
					GeometryReader { geo in
						let ratio = Double(actRow.count) / Double(maxCount)
						ZStack(alignment: .leading) {
							Capsule().fill(Color.secondary.opacity(0.18))
							Capsule()
								.fill(Color.accentColor)
								.frame(width: max(8, geo.size.width * CGFloat(ratio)))
						}
					}
					.frame(height: 6)
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private var recentMatchesSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Recent Matches")
				.font(.headline)
			
			Text("Earned in \(item.allTimeRecords.count) of the \(totalCachedMatches) cached matches")
				.font(.caption)
				.foregroundStyle(.secondary)
			
			if item.allTimeRecords.isEmpty {
				Text("Not earned in your cached matches yet.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(14)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			} else {
				ForEach(item.allTimeRecords) { record in
					NavigationLink {
						MatchDetailsContainer(matchID: record.matchID, userID: userID)
					} label: {
						HStack(spacing: 10) {
							VStack(alignment: .leading, spacing: 3) {
								Text(assets?.maps[record.mapID]?.displayName ?? "Map")
									.font(.subheadline.weight(.semibold))
								Text(record.gameStart.formatted(.relative(presentation: .named)))
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							if record.isNewBest {
								HStack(spacing: 4) {
									Image(systemName: "sparkle")
									Text("New best")
								}
								.font(.caption.weight(.semibold))
								.foregroundStyle(Color.orange)
								.padding(.horizontal, 8)
								.padding(.vertical, 4)
								.background(Color.orange.opacity(0.15), in: Capsule())
							}
							
							Text(item.type.formattedValue(record.value))
								.font(.headline.bold().monospacedDigit())
							
							Image(systemName: "chevron.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
						}
						.padding(14)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
					}
					.buttonStyle(.plain)
				}
			}
		}
	}
}
