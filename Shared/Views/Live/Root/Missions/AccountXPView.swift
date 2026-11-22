import SwiftUI
import ValorantAPI

struct AccountXPView: View {
	var accountXP: AccountXP?
	
	@State private var showAllHistory = false
	
	var body: some View {
		if let accountXP {
			VStack(spacing: 12) {
				accountLevelCard(accountXP)
				recentXPCard(accountXP)
			}
		} else {
			Text("Pull to refresh Contracts to load your Account Level and Recent XP history.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(14)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
		}
	}
	
	private func accountLevelCard(_ xp: AccountXP) -> some View {
		let maxXP = 5000
		let current = min(maxXP, max(0, xp.progress.xp))
		let remaining = max(0, maxXP - current)
		let ratio = Double(current) / Double(maxXP)
		let firstWinAvailable: Bool = {
			guard let next = xp.nextTimeFirstWinAvailable else { return true }
			return next <= Date()
		}()
		
		return VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline) {
				Text("Account Level")
					.font(.headline)
				Spacer()
				Text("\(xp.progress.level)")
					.font(.title2.bold().monospacedDigit())
					.foregroundStyle(Color.valorantRed)
			}
			
			GeometryReader { geo in
				ZStack(alignment: .leading) {
					Capsule()
						.fill(Color.secondary.opacity(0.2))
					Capsule()
						.fill(Color.valorantRed)
						.frame(width: max(6, geo.size.width * CGFloat(ratio)))
				}
			}
			.frame(height: 6)
			
			HStack {
				Text("\(current.formatted()) / 5 000 XP")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				Spacer()
				Text("\(remaining.formatted()) remaining")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}
			
			Divider()
			
			HStack {
				Text("First Win of the Day")
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Spacer()
				if firstWinAvailable {
					Label("Available (+1 000 AP)", systemImage: "checkmark.circle")
						.font(.caption.weight(.medium))
						.foregroundStyle(.green)
				} else if let next = xp.nextTimeFirstWinAvailable {
					HStack(spacing: 4) {
						Image(systemName: "clock")
						Text(next, style: .relative)
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
	}
	
	@ViewBuilder
	private func recentXPCard(_ xp: AccountXP) -> some View {
		let sorted = xp.history.sorted { $0.matchStart > $1.matchStart }
		let visible = showAllHistory ? sorted : Array(sorted.prefix(3))
		
		if !sorted.isEmpty {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Text("Recent XP")
						.font(.headline)
					Spacer()
					Text(showAllHistory ? "All \(sorted.count) matches" : "Last \(min(3, sorted.count)) matches")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				ForEach(visible) { entry in
					VStack(alignment: .leading, spacing: 6) {
						HStack {
							Text("+\(entry.xpDelta.formatted()) XP")
								.font(.subheadline.bold().monospacedDigit())
							Spacer()
							Text(entry.matchStart.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits).hour().minute()))
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
						}
						
						VStack(spacing: 6) {
							ForEach(Array(entry.xpSources.enumerated()), id: \.offset) { _, source in
								HStack(spacing: 8) {
									Image(systemName: iconForSource(source.id))
										.font(.caption)
										.foregroundStyle(.secondary)
										.frame(width: 16)
									Text(labelForSource(source.id))
										.font(.caption)
										.foregroundStyle(.secondary)
									Spacer()
									Text("+\(source.amount.formatted())")
										.font(.caption.monospacedDigit())
										.foregroundStyle(.secondary)
								}
							}
						}
						.padding(10)
						.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
					}
				}
				
				if sorted.count > 3 {
					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							showAllHistory.toggle()
						}
					} label: {
						HStack {
							Spacer()
							Text(showAllHistory ? "Show Less" : "Show More")
							Image(systemName: showAllHistory ? "chevron.up" : "chevron.down")
								.font(.caption)
							Spacer()
						}
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.primary)
						.padding(.top, 2)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
		}
	}
	
	private func iconForSource(_ id: String) -> String {
		switch id {
		case "time-played": return "clock"
		case "match-win": return "trophy"
		case "first-win-of-the-day": return "star.fill"
		default: return "sparkles"
		}
	}
	
	private func labelForSource(_ id: String) -> String {
		switch id {
		case "time-played": return "Time Played"
		case "match-win": return "Match Win"
		case "first-win-of-the-day": return "First Win"
		default:
			return id
				.replacingOccurrences(of: "-", with: " ")
				.capitalized
		}
	}
}
