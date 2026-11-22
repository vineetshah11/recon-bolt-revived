import SwiftUI

struct PassPlannerCard: View {
	var planner: PassPlanner
	var includeEpilogue: Binding<Bool>?
	
	@State private var isExpanded = false
	
	var body: some View {
		VStack(spacing: 0) {
			Button {
				withAnimation(.easeInOut(duration: 0.2)) {
					isExpanded.toggle()
				}
			} label: {
				HStack(spacing: 10) {
					Image(systemName: isExpanded ? "lock.open.fill" : "calendar.badge.clock")
						.foregroundStyle(Color.accentColor)
					Text("Pass Planner")
						.font(.subheadline.weight(.semibold))
					Spacer()
					Text("\(planner.dailyXPRequired.formatted()) XP/day")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
					Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				.padding(12)
			}
			.buttonStyle(.plain)
			
			if isExpanded {
				Divider()
					.padding(.horizontal, 12)
				
				VStack(alignment: .leading, spacing: 10) {
					if let includeEpilogue {
						Toggle("Include Epilogue (Levels 51–55)", isOn: includeEpilogue)
							.font(.caption)
							.tint(Color.accentColor)
					}
					
					HStack {
						statPill(title: "Remaining XP", value: planner.remainingXP.formatted())
						statPill(title: "Days Left", value: "\(planner.daysRemaining)d")
						statPill(title: "Daily Goal", value: "\(planner.dailyXPRequired.formatted())")
					}
					
					Text("Estimated Matches Needed (Total / Per Day)")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
						.padding(.top, 2)
					
					ForEach(planner.breakdowns) { mode in
						HStack {
							Text(mode.name)
								.font(.caption)
							Spacer()
							Text(String(format: "%d total • %.1f/day", mode.totalGamesNeeded, mode.gamesPerDay))
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
						}
					}
				}
				.padding(12)
			}
		}
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
	}
	
	private func statPill(title: LocalizedStringKey, value: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title)
				.font(.caption2)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.caption.bold().monospacedDigit())
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(8)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8))
	}
}
