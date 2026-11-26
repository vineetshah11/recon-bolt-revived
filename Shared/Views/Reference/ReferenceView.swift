import SwiftUI
import ValorantAPI

struct ReferenceView: View {
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var wishlistManager: WishlistManager
	
	var body: some View {
		AssetsUnwrappingView { assets in
			List {
				Section {
					NavigationLink {
						FriendsView()
					} label: {
						hubRow(icon: "person.2.fill", title: "Friends") {
							FriendsOnlineCountView()
						}
					}
					
					if let userID = accountManager.activeAccount?.id {
						NavigationLink {
							BookmarkListView(userID: userID)
						} label: {
							hubRow(icon: "bookmark.fill", title: "Bookmarks")
						}
					}
					
					NavigationLink {
						UsernameHistoryView()
					} label: {
						hubRow(icon: "person.text.rectangle", title: "Name History")
					}
					
					NavigationLink {
						LeaderboardView()
					} label: {
						hubRow(icon: "trophy.fill", title: "Leaderboard")
					}
					
					NavigationLink {
						PurchaseHistoryView()
					} label: {
						hubRow(icon: "creditcard.fill", title: "Purchase History")
					}
					
					NavigationLink {
						PlayerSettingsSnapshotsView()
					} label: {
						hubRow(icon: "gearshape.arrow.triangle.2.circlepath", title: "Player Settings")
					}
				} header: {
					Text("Social & Account")
				}
				
				Section {
					NavigationLink {
						SeasonGoalsView()
					} label: {
						hubRow(icon: "target", title: "Season Goals")
					}
					
					NavigationLink {
						ProgressTimelinesView()
					} label: {
						hubRow(icon: "chart.xyaxis.line", title: "Progress Timelines")
					}
					
					if let userID = accountManager.activeAccount?.id {
						NavigationLink {
							MapRatingsView(userID: userID)
						} label: {
							hubRow(icon: "map.fill", title: "Map Ranks")
						}
					}
				} header: {
					Text("Progress")
				}
				
				Section {
					NavigationLink {
						WishlistView()
					} label: {
						hubRow(icon: "heart.fill", title: "Wishlist") {
							if !wishlistManager.entries.isEmpty {
								Text("\(wishlistManager.entries.count)")
									.foregroundStyle(.secondary)
									.monospacedDigit()
							}
						}
					}
					
					NavigationLink {
						ShopHistoryView()
					} label: {
						hubRow(icon: "clock.arrow.circlepath", title: "Shop History")
					}
				} header: {
					Text("Shop")
				}
				
				Section {
					NavigationLink {
						MapListView()
					} label: {
						hubRow(icon: "map", title: "Maps")
					}
					
					NavigationLink {
						AgentListView()
					} label: {
						hubRow(icon: "person", title: "Agents")
					}
					
					NavigationLink {
						WeaponListView()
					} label: {
						hubRow(icon: "scope", title: "Weapons")
					}
					
					NavigationLink {
						LineupsView()
					} label: {
						hubRow(icon: "location.north.line", title: "Line-Ups")
					}
					
					NavigationLink {
						ContractArchiveView()
					} label: {
						hubRow(icon: "archivebox", title: "Contracts")
					}
				} header: {
					Text("Game Info")
				} footer: {
					let ver = assets.version.riotClientVersion.isEmpty
						? assets.version.version
						: assets.version.riotClientVersion
					Text("Version \(ver)", comment: "Hub")
				}
			}
		}
		.navigationTitle("Hub")
	}
	
	private func hubRow<Trailing: View>(
		icon: String,
		title: LocalizedStringKey,
		@ViewBuilder trailing: () -> Trailing = { EmptyView() }
	) -> some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.foregroundStyle(Color.accentColor)
				.frame(width: 24)
			Text(title)
				.font(.title3.weight(.medium))
			Spacer()
			trailing()
		}
		.padding(.vertical, 6)
	}
}

private struct FriendsOnlineCountView: View {
	@EnvironmentObject private var onlineCount: SocialOnlineCount
	
	var body: some View {
		Text("\(onlineCount.count)")
			.foregroundStyle(.secondary)
			.monospacedDigit()
	}
}

#if DEBUG
struct ReferenceView_Previews: PreviewProvider {
	static var previews: some View {
		ReferenceView()
			.environmentObject(AccountManager.mocked)
			.environmentObject(SocialManager())
			.environmentObject(SocialOnlineCount())
			.environmentObject(WishlistManager())
			.withToolbar()
	}
}
#endif
