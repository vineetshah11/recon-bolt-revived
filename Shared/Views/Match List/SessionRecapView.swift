import SwiftUI
import ValorantAPI

struct SessionRecapView: View {
	var userID: User.ID
	var sessions: [PlaySession]
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		List {
			if sessions.isEmpty {
				Section {
					Text("Open recent matches to cache their details and generate play-session recaps.")
						.foregroundStyle(.secondary)
				}
			} else {
				ForEach(sessions) { session in
					Section {
						VStack(alignment: .leading, spacing: 10) {
							HStack {
								VStack(alignment: .leading, spacing: 2) {
									Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
										.font(.headline)
									Text("\(session.items.count) \(session.items.count == 1 ? "match" : "matches") • \(session.wins)W – \(session.losses)L\(session.draws > 0 ? " – \(session.draws)D" : "")")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								Spacer()
								if session.netRRDelta != 0 {
									Text(session.netRRDelta > 0 ? "+\(session.netRRDelta) RR" : "\(session.netRRDelta) RR")
										.font(.subheadline.bold().monospacedDigit())
										.foregroundStyle(session.netRRDelta > 0 ? Color.green : Color.red)
								}
							}
							
							HStack {
								statPill(title: "K/D", value: String(format: "%.2f", session.kdRatio))
								statPill(title: "ACS", value: "\(session.averageACS)")
								statPill(title: "HS %", value: String(format: "%.1f%%", session.headshotPercentage))
							}
						}
						.padding(.vertical, 4)
						
						ForEach(session.items) { item in
							let match = item.details
							let player = match.players.firstElement(withID: userID)
							let won = match.teams.first(where: { $0.id == player?.teamID })?.won == true
							NavigationLink {
								MatchDetailsContainer(matchID: match.id, userID: userID)
							} label: {
								HStack(spacing: 10) {
									if let player, let agentID = player.agentID {
										let isOVariant = Team.ID.isGauntletOVariant(
											for: player.id,
											teamID: player.teamID,
											in: match.players
										)
										AgentImage.icon(agentID, teamID: player.teamID, isOVariant: isOVariant)
											.frame(width: 34, height: 34)
											.cornerRadius(8)
									}
									
									VStack(alignment: .leading, spacing: 2) {
										HStack(spacing: 6) {
											Text(assets?.maps[match.matchInfo.mapID]?.displayName ?? "Map")
												.font(.subheadline.weight(.medium))
											match.matchInfo.queueLabel
												.font(.caption2)
												.foregroundStyle(.secondary)
										}
										if let s = player?.stats {
											Text("\(s.kills)/\(s.deaths)/\(s.assists)")
												.font(.caption.monospacedDigit())
												.foregroundStyle(.secondary)
										}
									}
									
									Spacer()
									
									if let upd = item.update, upd.isRanked {
										Text(upd.ratingEarned >= 0 ? "+\(upd.ratingEarned) RR" : "\(upd.ratingEarned) RR")
											.font(.caption.bold().monospacedDigit())
											.foregroundStyle(upd.ratingEarned >= 0 ? Color.green : Color.red)
									} else {
										Text(won ? "WIN" : "LOSS")
											.font(.caption2.bold())
											.foregroundStyle(won ? Color.green : Color.red)
									}
								}
							}
						}
					}
				}
			}
		}
		.navigationTitle("Session Recap")
	}
	
	private func statPill(title: LocalizedStringKey, value: String) -> some View {
		VStack(spacing: 2) {
			Text(value)
				.font(.subheadline.bold().monospacedDigit())
			Text(title)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 6)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8))
	}
}
