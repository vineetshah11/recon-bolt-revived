import SwiftUI
import ValorantAPI
import HandyOperators
import UserDefault

struct MatchListView: View {
	let userID: User.ID
	
	@LocalData var user: User?
	@LocalData var matchList: MatchList?
	@LocalData var summary: CareerSummary?
	@LocalData var identity: Player.Identity?
	@State var isEditingFilter = false
	@UserDefault.State("MatchListView.filter") var filter = MatchListFilter()
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	@Environment(\.location) private var location
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@EnvironmentObject private var bookmarkList: BookmarkList
	
	private var shownMatches: [CompetitiveUpdate] {
		matchList?.matches ?? []
	}
	
	private var cachedMatchDetails: [MatchDetails] {
		shownMatches.prefix(40).compactMap {
			LocalDataProvider.shared.matchDetailsManager.loadedObject(for: $0.id)
		}
	}
	
	private var detailsByID: [Match.ID: MatchDetails] {
		Dictionary(uniqueKeysWithValues: cachedMatchDetails.map { ($0.id, $0) })
	}
	
	var body: some View {
		let currentAct = seasons?.currentAct()
		let prevAct = assets?.seasons.actBefore(currentAct)
		let mastery = AgentMasteryCalculator.compute(
			userID: userID,
			matches: cachedMatchDetails,
			assets: assets,
			contractsDetails: nil,
			currentAct: currentAct,
			previousAct: prevAct
		)
		let accolades = AccoladesCalculator.compute(
			userID: userID,
			matches: cachedMatchDetails,
			act: currentAct
		)
		let sessions = SessionRecapBuilder.buildSessions(
			userID: userID,
			matches: shownMatches,
			detailsByID: detailsByID
		)
		
		List {
			Section(header: Text("Player", comment: "Match List: section")) {
				PlayerIdentityCell(user: user, identity: identity)
				
				CompetitiveSummaryCell(summary: summary)
			}
			
			Section {
				AgentMasterySummaryBox(summaries: mastery)
					.listRowInsets(EdgeInsets())
					.listRowBackground(Color.clear)
			}
			
			Section {
				AccoladesSummaryBox(userID: userID, matches: cachedMatchDetails, report: accolades)
					.listRowInsets(EdgeInsets())
					.listRowBackground(Color.clear)
			}
			
			Section {
				HStack(spacing: 12) {
					NavigationLink {
						SessionRecapView(userID: userID, sessions: sessions)
					} label: {
						VStack(alignment: .leading, spacing: 6) {
							HStack(spacing: 6) {
								Image(systemName: "clock.badge.checkmark")
									.foregroundStyle(Color.valorantRed)
								Text("Session Recap")
									.font(.subheadline.weight(.semibold))
							}
							if let latest = sessions.first {
								Text(latest.startTime.formatted(.dateTime.day().month(.abbreviated)))
									.font(.caption)
									.foregroundStyle(.secondary)
								HStack(spacing: 4) {
									Text("\(latest.items.count) matches")
										.foregroundStyle(.secondary)
									if latest.netRRDelta != 0 {
										Text("• \(latest.netRRDelta > 0 ? "+\(latest.netRRDelta)" : "\(latest.netRRDelta)") RR")
											.foregroundStyle(latest.netRRDelta > 0 ? Color.green : Color.red)
									}
								}
								.font(.caption.monospacedDigit())
							} else {
								Text("Open matches to build")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						.frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
						.padding(12)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
					}
					.buttonStyle(.plain)
					
					NavigationLink {
						if let user, let matchList {
							StatisticsContainer(user: user, matchList: matchList)
						}
					} label: {
						VStack(alignment: .leading, spacing: 6) {
							HStack(spacing: 6) {
								Image(systemName: "chart.line.uptrend.xyaxis")
									.foregroundStyle(Color.valorantRed)
								Text("View Stats")
									.font(.subheadline.weight(.semibold))
							}
							Text("Win rate, K/D & more")
								.font(.caption)
								.foregroundStyle(.secondary)
							Spacer(minLength: 0)
						}
						.frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
						.padding(12)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
					}
					.buttonStyle(.plain)
					.disabled(user == nil || matchList == nil)
				}
				.listRowInsets(EdgeInsets())
				.listRowBackground(Color.clear)
			}
			
			Section(header: Text("Matches", comment: "Match List: section")) {
				ForEach(shownMatches) { match in
					MatchCell(match: match, userID: userID, filter: filter)
				}
				
				if matchList?.canLoadOlderMatches == true {
					AsyncButton {
						await updateMatchList(update: ValorantClient.loadOlderMatches)
					} label: {
						Label(
							String(localized: "Load Older Matches", comment: "Match List"),
							systemImage: "ellipsis"
						)
					}
				}
			}
		}
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				if !shouldAnonymize(userID) {
					Button {
						bookmarkList.toggleBookmark(for: userID, location: location!)
					} label: {
						if bookmarkList.hasBookmark(for: userID) {
							Label(
								String(localized: "Remove Bookmark", comment: "Match List: accessibility label"),
								systemImage: "bookmark.fill"
							)
						} else {
							Label(
								String(localized: "Add Bookmark", comment: "Match List: accessibility label"),
								systemImage: "bookmark"
							)
						}
					}
				}
				
				Button {
					isEditingFilter = true
				} label: {
					Label(
						String(localized: "Edit Filter", comment: "Match List: accessibility label"),
						systemImage: "line.horizontal.3.decrease.circle"
					)
					.symbolVariant(filter.isActive ? .fill : .none)
				}
			}
		}
		.refreshable { await refresh() }
		.sheet(isPresented: $isEditingFilter) {
			MatchListFilterEditor(filter: $filter)
		}
		.withLocalData($user, id: userID, shouldAutoUpdate: true)
		.withLocalData($matchList, id: userID, shouldAutoUpdate: true)
		.withLocalData($summary, id: userID, shouldAutoUpdate: true)
		.withLocalData($identity, id: userID, shouldAutoUpdate: true)
		.anonymizing(additionally: shouldAnonymize(userID) ? .all : .none)
		.navigationTitle(title)
	}
	
	var title: Text {
		if !shouldAnonymize(userID), let user {
			return Text(user.gameName)
		} else {
			return Text("Matches", comment: "Match List: title if name unknown/hidden")
		}
	}
	
	func refresh() async {
		async let matchListUpdate: Void = updateMatchList(update: ValorantClient.loadMatches)
		async let summaryUpdate: Void = load {
			try await $0.fetchCareerSummary(for: userID, forceFetch: true)
		}
		async let identityUpdate: Void = load {
			try await $0.fetchIdentity(for: userID, forceFetch: true)
		}
		_ = await (matchListUpdate, summaryUpdate, identityUpdate)
	}
	
	func updateMatchList(update: @escaping (ValorantClient) -> (inout MatchList) async throws -> Void) async {
		await load { try await $0.updateMatchList(for: userID, update: update($0)) }
	}
}

extension MatchListView {
	init(userID: User.ID) {
		self.init(
			userID: userID,
			user: .init(id: userID),
			matchList: .init(id: userID),
			summary: .init(id: userID),
			identity: .init(id: userID)
		)
	}
}

extension MatchListFilter: DefaultsValueConvertible {}

#if DEBUG
struct MatchListView_Previews: PreviewProvider {
	static var previews: some View {
		MatchListView(
			userID: PreviewData.userID,
			user: .init(preview: PreviewData.user),
			matchList: .init(preview: PreviewData.matchList),
			summary: .init(preview: PreviewData.summary),
			identity: .init(preview: PreviewData.userIdentity)
		)
		.withToolbar()
		.environmentObject(BookmarkList())
	}
}
#endif
