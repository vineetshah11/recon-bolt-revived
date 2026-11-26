import SwiftUI
import ValorantAPI

struct MatchDetailsContainer: View {
	let matchID: Match.ID
	let userID: User.ID
	
	@LocalData var details: MatchDetails?
	
	init(matchID: Match.ID, userID: User.ID) {
		self.matchID = matchID
		self.userID = userID
		self._details = .init(id: matchID)
	}
	
	var body: some View {
		Group {
			if let details {
				if details.players.isEmpty {
					Text("Match data unavailable.")
						.foregroundStyle(.secondary)
				} else {
					MatchDetailsView(data: .init(details: details, userID: userID))
				}
			} else {
				ProgressView()
			}
		}
		.withLocalData($details, id: matchID, shouldAutoUpdate: true, shouldReportErrors: true)
	}
}
