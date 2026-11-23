import SwiftUI
import ValorantAPI

struct ShopHistoryView: View {
	@EnvironmentObject private var shopHistoryStore: ShopHistoryStore
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var wishlistManager: WishlistManager
	@Environment(\.assets) private var assets
	
	@State private var search = ""
	
	var body: some View {
		let history = shopHistoryStore.days(for: accountManager.activeAccount?.id)
		let filtered = history.filter { day in
			guard !search.isEmpty else { return true }
			return day.offerSkinLevelIDs.contains { level in
				assets?.resolveSkin(level)?.skin.displayName.localizedCaseInsensitiveContains(search) == true
			}
		}
		
		List {
			if filtered.isEmpty {
				Section {
					VStack(spacing: 10) {
						Image(systemName: "clock.arrow.circlepath")
							.font(.largeTitle)
							.foregroundStyle(Color.accentColor)
						Text("No Shop History Yet")
							.font(.headline)
						Text("Each time you check your Daily Store in Recon Bolt, today's 4 offers are archived here automatically.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 20)
				}
			} else {
				ForEach(filtered) { day in
					Section {
						ForEach(day.offerSkinLevelIDs, id: \.self) { levelID in
							if let resolved = assets?.resolveSkin(levelID) {
								NavigationLink {
									SkinDetailsView(skin: resolved.skin)
								} label: {
									HStack(spacing: 12) {
										let tierColor = resolved.skin.contentTierID.flatMap { assets?.contentTiers[$0]?.color } ?? .secondary
										RoundedRectangle(cornerRadius: 2)
											.fill(tierColor)
											.frame(width: 4, height: 34)
										
										resolved.displayIcon?.view()
											.frame(width: 68, height: 34)
										
										VStack(alignment: .leading, spacing: 2) {
											HStack(spacing: 6) {
												Text(resolved.skin.displayName)
													.font(.subheadline.weight(.medium))
												if wishlistManager.contains(resolved.skin.id) {
													Image(systemName: "heart.fill")
														.font(.caption2)
														.foregroundStyle(Color.accentColor)
												}
											}
											Text(resolved.weapon.displayName)
												.font(.caption)
												.foregroundStyle(.secondary)
										}
									}
									.padding(.vertical, 2)
								}
							}
						}
					} header: {
						Text(day.date.formatted(date: .complete, time: .omitted))
					}
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search past offers"))
		.navigationTitle("Shop History")
	}
}
