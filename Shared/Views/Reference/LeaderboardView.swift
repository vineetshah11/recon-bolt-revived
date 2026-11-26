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
	@State private var submittedQuery = ""
	@State private var hasInitializedFilters = false
	@State private var reloadToken = 0
	@State private var fetchGeneration = 0
	@State private var leaderboard: Leaderboard?
	@State private var isLoading = false
	@State private var errorMessage: String?
	
	private struct QueryKey: Equatable {
		let region: String
		let seasonID: Season.ID?
		let query: String
		let reloadToken: Int
	}
	
	private var queryKey: QueryKey {
		QueryKey(
			region: selectedRegion,
			seasonID: selectedSeasonID,
			query: submittedQuery,
			reloadToken: reloadToken
		)
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 14) {
				searchBar
				
				metadataHeader
				
				if isLoading && leaderboard == nil {
					VStack {
						ProgressView()
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 48)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
				} else if let errorMessage {
					VStack(spacing: 8) {
						Text(errorMessage)
							.font(.subheadline)
							.foregroundStyle(.red)
							.multilineTextAlignment(.center)
						Button("Retry") {
							reloadToken &+= 1
						}
						.buttonStyle(.bordered)
					}
					.frame(maxWidth: .infinity)
					.padding(20)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
				} else if let leaderboard {
					if leaderboard.players.isEmpty {
						Text("No players found.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 40)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
					} else {
						LazyVStack(spacing: 0) {
							ForEach(Array(leaderboard.players.enumerated()), id: \.element.id) { index, entry in
								if let puuid = entry.puuid, !entry.isAnonymized {
									NavigationLink {
										MatchListView(userID: puuid)
									} label: {
										leaderboardRow(entry, showChevron: true)
									}
									.buttonStyle(.plain)
								} else {
									leaderboardRow(entry, showChevron: false)
								}
								
								if index < leaderboard.players.count - 1 {
									Divider()
										.padding(.leading, 72)
										.opacity(0.45)
								}
							}
						}
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
						.clipped()
					}
					
					let loadedEnd = leaderboard.startIndex + leaderboard.players.count
					if loadedEnd < leaderboard.totalPlayers && query.isEmpty {
						AsyncButton {
							await fetch(startIndex: loadedEnd, append: true)
						} label: {
							HStack(spacing: 8) {
								if isLoading {
									ProgressView()
										.controlSize(.small)
								}
								Text("Load Next 100")
									.font(.subheadline.weight(.semibold))
							}
							.frame(maxWidth: .infinity)
							.padding(.vertical, 12)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.buttonStyle(.plain)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
		}
		.background(Color.groupedBackground)
		.refreshable {
			await fetch(startIndex: 0, append: false)
		}
		.navigationTitle("Leaderboard")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				filterMenu
			}
		}
		.task(id: queryKey) {
			if !hasInitializedFilters {
				hasInitializedFilters = true
				let defaultRegion = accountManager.activeAccount?.location.region
				let defaultSeason = seasons?.currentAct()?.id ?? assets?.seasons.actsInOrder.last?.id
				var didAdjustDefaults = false
				if let defaultRegion, defaultRegion != selectedRegion {
					selectedRegion = defaultRegion
					didAdjustDefaults = true
				}
				if selectedSeasonID == nil, let defaultSeason {
					selectedSeasonID = defaultSeason
					didAdjustDefaults = true
				}
				if didAdjustDefaults {
					return
				}
			}
			await fetch(startIndex: 0, append: false)
		}
	}
	
	private var currentRegionName: String {
		regions.first(where: { $0.id == selectedRegion })?.name ?? selectedRegion.uppercased()
	}
	
	private var searchBar: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.secondary)
			TextField("Search players...", text: $query)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.submitLabel(.search)
				.onSubmit {
					submittedQuery = query
					reloadToken &+= 1
				}
			if !query.isEmpty {
				Button {
					query = ""
					submittedQuery = ""
					reloadToken &+= 1
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.background(Color.secondaryGroupedBackground, in: Capsule())
		.overlay {
			Capsule()
				.stroke(Color.separator.opacity(0.3), lineWidth: 0.5)
		}
	}
	
	private var metadataHeader: some View {
		HStack {
			if let leaderboard {
				Text("\(leaderboard.totalPlayers.formatted()) Players")
					.font(.subheadline.weight(.medium).monospacedDigit())
					.foregroundStyle(.secondary)
			} else if isLoading {
				Text("Loading...")
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
			}
			
			Spacer()
			
			Menu {
				Picker("Region", selection: $selectedRegion) {
					ForEach(regions, id: \.id) { region in
						Text(region.name).tag(region.id)
					}
				}
			} label: {
				HStack(spacing: 6) {
					Image(systemName: "display")
					Text(currentRegionName)
				}
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 4)
	}
	
	private var filterMenu: some View {
		Menu {
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
		} label: {
			Image(systemName: "line.3.horizontal.decrease")
				.foregroundStyle(Color.accentColor)
		}
	}
	
	private func leaderboardRow(_ entry: Leaderboard.Entry, showChevron: Bool) -> some View {
		let act = selectedSeasonID.flatMap { assets?.seasons.acts[$0] } ?? seasons?.currentAct()
		let tierInfo = seasons?.tierInfo(number: entry.competitiveTier, in: act)
		
		return ZStack {
			Text("\(entry.leaderboardRank)")
				.font(.system(size: 46, weight: .black, design: .rounded).monospacedDigit())
				.foregroundStyle(rankWatermarkColor(entry.leaderboardRank))
				.lineLimit(1)
				.minimumScaleFactor(0.45)
				.frame(maxWidth: .infinity, alignment: .center)
				.offset(x: -14)
				.allowsHitTesting(false)
			
			HStack(spacing: 12) {
				PlayerCardImage.small(entry.playerCardID)
					.frame(width: 46, height: 46)
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
				
				VStack(alignment: .leading, spacing: 3) {
					if let gameName = entry.gameName, !gameName.isEmpty, !entry.isAnonymized {
						Group {
							if let tagLine = entry.tagLine, !tagLine.isEmpty {
								(Text(gameName)
									.font(.subheadline.weight(.bold))
									.foregroundColor(.primary)
								+ Text("#\(tagLine)")
									.font(.subheadline)
									.foregroundColor(.secondary))
							} else {
								Text(gameName)
									.font(.subheadline.weight(.bold))
									.foregroundColor(.primary)
							}
						}
						.lineLimit(1)
					} else {
						Text("Secret Agent")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.primary)
							.lineLimit(1)
					}
					
					if let titleID = entry.titleID,
					   let titleText = assets?.playerTitles[titleID]?.titleText,
					   !titleText.isEmpty {
						Text(titleText)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				
				Spacer(minLength: 6)
				
				VStack(alignment: .trailing, spacing: 2) {
					Text("\(entry.rankedRating.formatted()) RR")
						.font(.subheadline.weight(.semibold).monospacedDigit())
						.foregroundStyle(.primary)
					Text("\(entry.numberOfWins) W")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
				
				CompetitiveTierImage(tierInfo: tierInfo)
					.frame(width: 30, height: 30)
				
				Image(systemName: "chevron.right")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.tertiary)
					.opacity(showChevron ? 1 : 0)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.contentShape(Rectangle())
	}
	
	private func rankWatermarkColor(_ rank: Int) -> Color {
		switch rank {
		case 1: return Color.yellow.opacity(0.16)
		case 2: return Color.gray.opacity(0.22)
		case 3: return Color.orange.opacity(0.18)
		default: return Color.secondary.opacity(0.12)
		}
	}
	
	private func fetch(startIndex: Int, append: Bool) async {
		guard let client = accountManager.activeAccount?.client else {
			errorMessage = "Sign in to view competitive leaderboards."
			return
		}
		guard let seasonID = selectedSeasonID ?? seasons?.currentAct()?.id ?? assets?.seasons.actsInOrder.last?.id else {
			return
		}
		fetchGeneration += 1
		let gen = fetchGeneration
		isLoading = true
		errorMessage = nil
		defer {
			if gen == fetchGeneration {
				isLoading = false
			}
		}
		
		do {
			let fetched = try await client.getLeaderboard(
				region: selectedRegion,
				queueID: .competitive,
				seasonID: seasonID,
				startIndex: startIndex,
				size: 100,
				query: submittedQuery.isEmpty ? nil : submittedQuery
			)
			guard !Task.isCancelled, gen == fetchGeneration else { return }
			if append, var existing = leaderboard {
				existing.players.append(contentsOf: fetched.players)
				existing.totalPlayers = fetched.totalPlayers
				leaderboard = existing
			} else {
				leaderboard = fetched
			}
		} catch {
			guard !Task.isCancelled, gen == fetchGeneration else { return }
			if error is CancellationError || (error as? URLError)?.code == .cancelled {
				return
			}
			errorMessage = error.localizedDescription
		}
	}
}
