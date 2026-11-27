import SwiftUI
import ValorantAPI

struct MatchDetailsContainer: View {
	let matchID: Match.ID
	let userID: User.ID
	
	@LocalData var details: MatchDetails?
	@LocalData var matchList: MatchList?
	
	init(matchID: Match.ID, userID: User.ID) {
		self.matchID = matchID
		self.userID = userID
		self._details = .init(id: matchID)
		self._matchList = .init(id: userID)
	}
	
	var body: some View {
		Group {
			if let details {
				if details.players.isEmpty {
					Text("Match data unavailable.")
						.foregroundStyle(.secondary)
				} else {
					let competitiveUpdate = matchList?.matches.first(where: { $0.id == matchID })
					MatchDetailsView(
						data: .init(details: details, userID: userID),
						competitiveUpdate: competitiveUpdate
					)
				}
			} else {
				ProgressView()
			}
		}
		.withLocalData($details, id: matchID, shouldAutoUpdate: true, shouldReportErrors: true)
		.withLocalData($matchList, id: userID)
	}
}
