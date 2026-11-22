import SwiftUI
import ValorantAPI

struct AccoladesSummaryBox: View {
	var userID: User.ID
	var matches: [MatchDetails]
	var report: AccoladesReport
	
	var body: some View {
		NavigationLink {
			AccoladesView(userID: userID, matches: matches)
		} label: {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Image(systemName: "chevron.right")
						.font(.caption.bold())
						.foregroundStyle(Color.valorantRed)
					Text("Accolades")
						.font(.headline)
					Spacer()
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				
				HStack {
					Text("This Act")
						.font(.caption)
						.foregroundStyle(.secondary)
					Spacer()
					Text("\(report.totalEarned) earned")
						.font(.caption.weight(.semibold).monospacedDigit())
				}
				
				let top3 = Array(report.items.prefix(3))
				if top3.isEmpty {
					Text("Play matches in the current Act to earn performance accolades.")
						.font(.caption)
						.foregroundStyle(.secondary)
				} else {
					HStack(spacing: 12) {
						ForEach(top3) { item in
							VStack(spacing: 6) {
								ZStack {
									Circle()
										.fill(item.type.badgeColor)
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

struct AccoladesView: View {
	enum Scope: String, CaseIterable, Identifiable {
		case thisAct = "This Act"
		case allMatches = "All Cached Matches"
		
		var id: String { rawValue }
	}
	
	var userID: User.ID
	var matches: [MatchDetails]
	
	@Environment(\.seasons) private var seasons
	@State private var scope: Scope = .thisAct
	
	var body: some View {
		let report = AccoladesCalculator.compute(
			userID: userID,
			matches: matches,
			act: scope == .thisAct ? seasons?.currentAct() : nil
		)
		
		List {
			Section {
				Picker("Scope", selection: $scope) {
					ForEach(Scope.allCases) { item in
						Text(item.rawValue).tag(item)
					}
				}
				.pickerStyle(.segmented)
				.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
			}
			
			Section {
				HStack {
					Text("Total Accolades Earned")
						.font(.headline)
					Spacer()
					Text("\(report.totalEarned)")
						.font(.title2.bold().monospacedDigit())
						.foregroundStyle(Color.valorantRed)
				}
				.padding(.vertical, 4)
			}
			
			Section {
				if report.items.isEmpty {
					Text("No accolades earned in this scope yet.")
						.foregroundStyle(.secondary)
				} else {
					ForEach(report.items) { item in
						HStack(spacing: 14) {
							ZStack {
								Circle()
									.fill(item.type.badgeColor)
									.frame(width: 40, height: 40)
								Image(systemName: item.type.iconName)
									.font(.system(size: 16, weight: .bold))
									.foregroundStyle(.white)
							}
							
							VStack(alignment: .leading, spacing: 2) {
								Text(item.type.title)
									.font(.headline)
								Text(item.type.subtitle)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							Text("×\(item.count)")
								.font(.headline.monospacedDigit())
								.foregroundStyle(item.type.badgeColor)
						}
						.padding(.vertical, 4)
					}
				}
			} header: {
				Text("Breakdown")
			}
		}
		.navigationTitle("Accolades")
	}
}
