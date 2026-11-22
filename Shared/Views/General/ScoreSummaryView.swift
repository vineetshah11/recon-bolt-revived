import SwiftUI
import ValorantAPI

struct ScoreSummaryView: View {
	let teams: [Team]
	var players: [Player] = []
	let ownTeamID: Team.ID?
	
	var body: some View {
		let _ = assert(!teams.isEmpty)
		if teams.count > 2 {
			let ranked = MatchDetails.rankTeams(teams, players: players)
			if
				let ownTeamID,
				let rankIndex = ranked.firstIndex(where: { $0.id == ownTeamID })
			{
				let team = ranked[rankIndex]
				let rank = (team.placement ?? 0) > 0 ? team.placement! : rankIndex + 1
				Text(PlacementFormatter.ordinal(rank))
					.foregroundColor(team.won || rank == 1 ? .valorantBlue : .primary)
			} else if let winner = ranked.first {
				Text(verbatim: "\(winner.pointCount)")
					.foregroundColor(.valorantBlue)
			}
		} else {
			let sorted = teams.sorted(on: \.pointCount)
				.reversed()
				.movingToFront { $0.id == ownTeamID }
			
			if sorted.count >= 2 {
				HStack {
					Text(verbatim: "\(sorted[0].pointCount)")
						.foregroundColor(.valorantBlue)
					Text("–")
						.foregroundStyle(.tertiary)
					Text(verbatim: "\(sorted[1].pointCount)")
						.foregroundColor(.valorantRed)
				}
			} else if let onlyTeam = sorted.first {
				Text(verbatim: "\(onlyTeam.pointCount) points")
			}
		}
	}
}
