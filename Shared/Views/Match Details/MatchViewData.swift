import ValorantAPI
import SwiftUI

/// View data for a match, used in many views involved in match details.
struct MatchViewData {
	let details: MatchDetails
	let myself: Player?
	let players: [Player.ID: Player]
	let parties: [Party.ID]
	let rankedTeams: [Team]
	let teamColors: [Team.ID: Color]
	
	var isMultiTeam: Bool {
		details.teams.count > 2
	}
	
	init(details: MatchDetails, userID: Player.ID?) {
		self.details = details
		
		let candidates = details.players.filter { $0.id == userID }
		assert(candidates.count <= 1)
		self.myself = candidates.first
		
		self.players = .init(values: details.players)
		
		self.parties = Dictionary(grouping: details.players) { $0.partyID }
			.filter { $0.value.count > 1 }
			.sorted(on: \.value.count)
			.reversed()
			.movingToFront { $0.value.contains { $0.id == userID } }
			.map(\.key)
		
		let ranked = details.rankedTeams()
		self.rankedTeams = ranked
		self.teamColors = details.teams.count > 2
			? Color.assignedTeamColors(for: ranked.map(\.id), ownTeamID: candidates.first?.teamID)
			: [:]
	}
	
	func player(_ id: Player.ID?) -> Player? {
		id.flatMap { players[$0] }
	}
	
	func placement(of teamID: Team.ID) -> Int? {
		details.placement(of: teamID)
	}
	
	func isGauntletOVariant(for player: Player) -> Bool {
		Team.ID.isGauntletOVariant(for: player.id, teamID: player.teamID, in: details.players)
	}
	
	func relativeColor(of other: Player) -> Color? {
		let teamColor = relativeColor(of: other.teamID) ?? .valorantBlue
		return other.id == myself?.id ? .valorantSelf : teamColor
	}
	
	func relativeColor(of other: Player.ID) -> Color? {
		players[other].flatMap(relativeColor)
	}
	
	func relativeColor(of teamID: Team.ID) -> Color? {
		if teamID == .neutral {
			return .gray
		} else if isMultiTeam {
			return teamColors[teamID] ?? teamID.color ?? .valorantRed
		} else if let own = myself?.teamID {
			return teamID == own ? .valorantBlue : .valorantRed
		} else {
			return teamID.color
		}
	}
}
