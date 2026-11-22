import SwiftUI
import ValorantAPI

struct LeaderboardView: View {
	@EnvironmentObject private var accountManager: AccountManager
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.valorantLoad) private var load
	
	private let regions: [(id: String, name: String)] = [
		("eu", "Europe"),
		("na", "North America"),
		("ap", "Asia Pacific"),
		("kr", "Korea"),
		("br", "Brazil"),
		("latam", "Latin America"),
	]
	
	@State private var selectedRegion = "eu"
	@State private var selectedSeasonID: Season.ID?
	@State private var query = ""
	@State private var leaderboard: Leaderboard?
	@State private var isLoading = false
	@State private var errorMessage: String?
	
	var body: some View {
		List {
			Section {
				Picker("Region", selection: $selectedRegion) {
					ForEach(regions, id: \.id) { region in
						Text(region.name).tag(region.id)
					}
				}
				
				if let acts = assets?.seasons.actsInOrder.reversed(), !acts.isEmpty {
					Picker("Act", selection: $selectedSeasonID) {
						ForEach(Array(acts.prefix(15))) { act in
							Text(act.nameWithEpisode).tag(Optional(act.id))
						}
					}
				}
			}
			
			if isLoading && leaderboard == nil {
				Section {
					HStack {
						Spacer()
						ProgressView()
						Spacer()
					}
				}
			} else if let errorMessage {
				Section {
					Text(errorMessage)
						.foregroundStyle(.red)
				}
			} else if let leaderboard {
				Section {
					ForEach(leaderboard.players) { entry in
						if let puuid = entry.puuid, !entry.isAnonymized {
							NavigationLink {
								MatchListView(userID: puuid)
							} label: {
								leaderboardRow(entry)
							}
						} else {
							leaderboardRow(entry)
						}
					}
					
					let loadedEnd = leaderboard.startIndex + leaderboard.players.count
					if loadedEnd < leaderboard.totalPlayers && query.isEmpty {
						AsyncButton {
							await fetch(startIndex: loadedEnd, append: true)
						} label: {
							Label("Load Next 100", systemImage: "ellipsis")
						}
					}
				} header: {
					Text("Showing \(leaderboard.players.count) of \(leaderboard.totalPlayers.formatted()) players")
				}
			}
		}
		.searchable(text: $query, prompt: Text("Search player name"))
		.onSubmit(of: .search) {
			Task { await fetch(startIndex: 0, append: false) }
		}
		.onChange(of: selectedRegion) { _ in
			Task { await fetch(startIndex: 0, append: false) }
		}
		.onChange(of: selectedSeasonID) { _ in
			Task { await fetch(startIndex: 0, append: false) }
		}
		.refreshable {
			await fetch(startIndex: 0, append: false)
		}
		.navigationTitle("Leaderboard")
		.task {
			if let region = accountManager.activeAccount?.location.region {
				selectedRegion = region
			}
			if selectedSeasonID == nil {
				selectedSeasonID = seasons?.currentAct()?.id ?? assets?.seasons.actsInOrder.last?.id
			}
			if leaderboard == nil {
				await fetch(startIndex: 0, append: false)
			}
		}
	}
	
	private func leaderboardRow(_ entry: Leaderboard.Entry) -> some View {
		HStack(spacing: 12) {
			Text("#\(entry.leaderboardRank)")
				.font(.subheadline.bold().monospacedDigit())
				.frame(minWidth: 44, alignment: .leading)
				.foregroundStyle(entry.leaderboardRank <= 3 ? Color.valorantRed : .secondary)
			
			let act = selectedSeasonID.flatMap { assets?.seasons.acts[$0] } ?? seasons?.currentAct()
			let tierInfo = seasons?.tierInfo(number: entry.competitiveTier, in: act)
			CompetitiveTierImage(tierInfo: tierInfo)
				.frame(width: 30, height: 30)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(entry.fullName)
					.font(.body.weight(.medium))
					.lineLimit(1)
				Text("\(entry.numberOfWins) wins")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			
			Spacer()
			
			Text("\(entry.rankedRating) RR")
				.font(.subheadline.bold().monospacedDigit())
		}
		.padding(.vertical, 2)
	}
	
	private func fetch(startIndex: Int, append: Bool) async {
		guard let client = accountManager.activeAccount?.client else {
			errorMessage = "Sign in to view competitive leaderboards."
			return
		}
		guard let seasonID = selectedSeasonID ?? seasons?.currentAct()?.id ?? assets?.seasons.actsInOrder.last?.id else {
			return
		}
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }
		
		do {
			let fetched = try await client.getLeaderboard(
				region: selectedRegion,
				queueID: .competitive,
				seasonID: seasonID,
				startIndex: startIndex,
				size: 100,
				query: query.isEmpty ? nil : query
			)
			if append, var existing = leaderboard {
				existing.players.append(contentsOf: fetched.players)
				existing.totalPlayers = fetched.totalPlayers
				leaderboard = existing
			} else {
				leaderboard = fetched
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
