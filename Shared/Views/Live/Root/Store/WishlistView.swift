import SwiftUI
import ValorantAPI

struct WishlistView: View {
	@EnvironmentObject private var wishlistManager: WishlistManager
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var shopHistoryStore: ShopHistoryStore
	@Environment(\.assets) private var assets
	
	@State private var showingPicker = false
	@State private var search = ""
	
	private var resolvedSkins: [(entry: WishlistEntry, skin: WeaponSkin, weapon: WeaponInfo)] {
		guard let assets else { return [] }
		let allWeapons = Array(assets.weapons.values)
		return wishlistManager.entries.compactMap { entry in
			for weapon in allWeapons {
				if let skin = weapon.skins.first(where: { $0.id == entry.skinID }) {
					return (entry, skin, weapon)
				}
			}
			return nil
		}
		.filter { search.isEmpty || $0.skin.displayName.localizedCaseInsensitiveContains(search) || $0.weapon.displayName.localizedCaseInsensitiveContains(search) }
	}
	
	var body: some View {
		List {
			if wishlistManager.entries.isEmpty {
				Section {
					VStack(spacing: 10) {
						Image(systemName: "heart.text.square")
							.font(.largeTitle)
							.foregroundStyle(Color.accentColor)
						Text("No Wishlisted Skins")
							.font(.headline)
						Text("Add weapon skins to your wishlist to spot them immediately when they appear in your Daily Offers.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 20)
				}
			} else {
				Section {
					ForEach(resolvedSkins, id: \.entry.id) { item in
						NavigationLink {
							SkinDetailsView(skin: item.skin)
						} label: {
							HStack(spacing: 12) {
								let tierColor = item.skin.contentTierID.flatMap { assets?.contentTiers[$0]?.color } ?? .accentColor
								RoundedRectangle(cornerRadius: 3)
									.fill(tierColor)
									.frame(width: 4, height: 42)
								
								(item.skin.displayIcon ?? item.skin.levels.first?.displayIcon)?
									.view()
									.frame(width: 72, height: 38)
								
								VStack(alignment: .leading, spacing: 2) {
									Text(item.skin.displayName)
										.font(.body.weight(.medium))
									let count = shopHistoryStore.appearanceCount(
										for: item.skin.id,
										accountID: accountManager.activeAccount?.id,
										assets: assets
									)
									Text(count > 0 ? "\(item.weapon.displayName) • Seen \(count)×" : item.weapon.displayName)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
							.padding(.vertical, 4)
						}
						.swipeActions(edge: .trailing) {
							Button(role: .destructive) {
								wishlistManager.remove(id: item.entry.skinID)
							} label: {
								Label("Remove", systemImage: "trash")
							}
						}
					}
				} header: {
					Text("Wishlisted Skins (\(resolvedSkins.count))")
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search wishlist"))
		.navigationTitle("Wishlist")
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					showingPicker = true
				} label: {
					Image(systemName: "plus")
				}
			}
		}
		.sheet(isPresented: $showingPicker) {
			NavigationStack {
				WishlistItemPicker()
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button("Done") { showingPicker = false }
						}
					}
			}
		}
	}
}

struct WishlistItemPicker: View {
	@EnvironmentObject private var wishlistManager: WishlistManager
	@Environment(\.assets) private var assets
	
	@State private var search = ""
	@State private var selectedWeaponID: Weapon.ID?
	
	var body: some View {
		List {
			if let assets {
				let weapons = Weapon.ID.orderInCollection.compactMap { assets.weapons[$0] }
				Section {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 8) {
							filterChip(title: "All", isSelected: selectedWeaponID == nil) {
								selectedWeaponID = nil
							}
							ForEach(weapons) { weapon in
								filterChip(title: weapon.displayName, isSelected: selectedWeaponID == weapon.id) {
									selectedWeaponID = weapon.id
								}
							}
						}
						.padding(.vertical, 4)
					}
					.listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
				}
				
				let matchingSkins: [(weapon: WeaponInfo, skin: WeaponSkin)] = weapons
					.filter { selectedWeaponID == nil || $0.id == selectedWeaponID }
					.flatMap { weapon in
						weapon.skins
							.filter { $0.id != weapon.defaultSkinID }
							.filter { !$0.displayName.localizedCaseInsensitiveContains("Random") }
							.map { (weapon, $0) }
					}
					.filter { search.isEmpty || $0.skin.displayName.localizedCaseInsensitiveContains(search) || $0.weapon.displayName.localizedCaseInsensitiveContains(search) }
					.sorted { $0.skin.displayName.localizedCaseInsensitiveCompare($1.skin.displayName) == .orderedAscending }
				
				Section {
					ForEach(matchingSkins, id: \.skin.id) { item in
						let wishlisted = wishlistManager.contains(item.skin.id)
						Button {
							wishlistManager.toggle(item.skin.id)
						} label: {
							HStack(spacing: 12) {
								(item.skin.displayIcon ?? item.skin.levels.first?.displayIcon)?
									.view()
									.frame(width: 64, height: 34)
								
								VStack(alignment: .leading, spacing: 2) {
									Text(item.skin.displayName)
										.foregroundStyle(.primary)
									Text(item.weapon.displayName)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								
								Spacer()
								
								Image(systemName: wishlisted ? "heart.fill" : "heart")
									.foregroundStyle(wishlisted ? Color.accentColor : .secondary)
							}
							.padding(.vertical, 2)
						}
					}
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search skins"))
		.navigationTitle("Add to Wishlist")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.caption.weight(.semibold))
				.padding(.horizontal, 12)
				.padding(.vertical, 6)
				.background(isSelected ? Color.accentColor : Color.secondaryGroupedBackground, in: Capsule())
				.foregroundStyle(isSelected ? .white : .primary)
		}
		.buttonStyle(.plain)
	}
}
