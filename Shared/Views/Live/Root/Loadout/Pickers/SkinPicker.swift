import SwiftUI
import ValorantAPI

struct SkinPicker: View {
	@Binding var gun: Loadout.Gun
	var inventory: Inventory
	
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var favoritesManager: FavoritesManager
	@EnvironmentObject private var wishlistManager: WishlistManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@Environment(\.valorantLoad) private var load
	
	@State private var search = ""
	@State private var filter: LoadoutItemFilter = .favoritesAndOwned
	@State private var detailSkin: WeaponSkin?
	@State private var cachedAllSkins: [ResolvedLevel] = []
	@State private var cachedVisibleSkins: [ResolvedLevel] = []
	@State private var cachedStats: (total: Int, shown: Int, favs: Int, owned: Int) = (0, 0, 0, 0)
	
	private struct ListKey: Equatable {
		let weaponID: Weapon.ID
		let search: String
		let filter: LoadoutItemFilter
		let favCount: Int
		let ownedCount: Int
		let assetsVersion: AssetVersion?
	}
	
	private var activeAccountID: User.ID? {
		accountManager.activeAccount?.id
	}
	
	var body: some View {
		AssetsUnwrappingView { assets in
			if let weapon = assets.weapons[gun.id] {
				skinList(for: weapon)
			}
		}
	}
	
	@ViewBuilder
	private func skinList(for weapon: WeaponInfo) -> some View {
		let key = ListKey(
			weaponID: weapon.id,
			search: search,
			filter: filter,
			favCount: favoritesManager.favorites(for: activeAccountID)?.favoritedContent.count ?? 0,
			ownedCount: inventory.skinLevels.count,
			assetsVersion: assets?.version
		)
		let visibleSkins = cachedVisibleSkins
		
		ScrollView {
			VStack(spacing: 14) {
				LoadoutPickerSearchField(prompt: "Search", text: $search)
				
				LoadoutPickerStatsPill(
					total: cachedStats.total,
					shown: cachedStats.shown,
					favorites: cachedStats.favs,
					owned: cachedStats.owned
				)
				
				if visibleSkins.isEmpty {
					VStack(spacing: 8) {
						Text("No matching skins")
							.font(.headline)
						Text("Adjust your search or star filter to see more skins.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 32)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
				} else {
					LazyVStack(spacing: 0) {
						ForEach(Array(visibleSkins.enumerated()), id: \.element.id) { index, item in
							skinRow(item, weapon: weapon)
							if index < visibleSkins.count - 1 {
								Divider()
									.opacity(0.25)
									.padding(.horizontal, 16)
							}
						}
					}
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Choose Skin")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				LoadoutPickerFilterMenu(filter: $filter)
			}
		}
		.navigationDestination(isPresented: Binding(
			get: { detailSkin != nil },
			set: { if !$0 { detailSkin = nil } }
		)) {
			if let detailSkin {
				SkinDetailsView(skin: detailSkin, inventory: inventory)
			}
		}
		.task(id: key) {
			let allSkins = orderedSkins(for: weapon)
			let realSkins = allSkins.filter { $0.skin.themeID != .random }
			let favCount = realSkins.count { isFavorited($0.skin) }
			let ownedCount = realSkins.count { isOwned($0.skin) }
			let visible = allSkins.filter { resolved in
				let isRandom = resolved.skin.themeID == .random
				let isStandard = resolved.skin.themeID == .standard
				let matchesFilter: Bool = {
					if isRandom {
						return filter != .onlyUnowned
					}
					return filter.matches(
						isOwned: isOwned(resolved.skin),
						isFavorited: isFavorited(resolved.skin),
						isAlwaysShownFree: isStandard
					)
				}()
				guard matchesFilter else { return false }
				guard !search.isEmpty else { return true }
				return resolved.skin.displayName.localizedCaseInsensitiveContains(search)
					|| resolved.searchableText.localizedCaseInsensitiveContains(search)
			}
			cachedAllSkins = allSkins
			cachedVisibleSkins = visible
			cachedStats = (
				total: realSkins.count,
				shown: visible.count { $0.skin.themeID != .random },
				favs: favCount,
				owned: ownedCount
			)
		}
		.valorantLoadTask(id: activeAccountID) { client in
			await favoritesManager.refreshIfNeeded(using: client)
		}
	}
	
	private func skinRow(_ item: ResolvedLevel, weapon: WeaponInfo) -> some View {
		let isRandom = item.skin.themeID == .random
		let isFree = item.skin.themeID.isFree
		let owned = isOwned(item.skin)
		let favorited = !isRandom && isFavorited(item.skin)
		let wishlisted = !isFree && wishlistManager.contains(item.skin.id)
		let isSelected = gun.skin.skin == item.skin.id
		
		return Button {
			if owned || isRandom {
				gun.skin = .init(
					skin: item.skin.id,
					level: item.level.id,
					chroma: item.skin.chromas.first?.id
				)
				dismiss()
			} else {
				detailSkin = item.skin
			}
		} label: {
			VStack(spacing: 10) {
				ZStack {
					if isRandom {
						weapon.displayIcon.view()
							.frame(height: 68)
							.frame(maxWidth: .infinity)
							.opacity(0.16)
						
						Image(systemName: "shuffle")
							.font(.system(size: 32, weight: .bold))
							.foregroundStyle(.primary)
					} else {
						item.displayIcon.view()
							.frame(height: 68)
							.frame(maxWidth: .infinity)
							.opacity(owned ? 1 : 0.55)
					}
				}
				.overlay(alignment: .topTrailing) {
					HStack(spacing: 6) {
						if favorited {
							Image(systemName: "star.fill")
								.font(.caption.bold())
								.foregroundStyle(.yellow)
						}
						if wishlisted {
							Image(systemName: "heart.fill")
								.font(.caption.bold())
								.foregroundStyle(Color.accentColor)
						}
						if isSelected {
							Image(systemName: "checkmark.circle.fill")
								.font(.system(size: 19))
								.foregroundStyle(Color.accentColor)
						}
					}
				}
				
				HStack(spacing: 6) {
					Text(item.skin.displayName)
						.font(.body)
						.foregroundStyle(owned || isRandom ? .primary : .secondary)
						.lineLimit(1)
					
					Spacer()
					
					if !owned && !isRandom {
						Text("Not Owned")
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 16)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.contextMenu {
			if !isRandom {
				Button {
					detailSkin = item.skin
				} label: {
					Label("View Details", systemImage: "info.circle")
				}
			}
			
			if owned && !isFree {
				Button {
					Task {
						await load { client in
							try await favoritesManager.toggleSkinFavorite(item.skin, using: client)
						}
					}
				} label: {
					Label(
						favorited ? "Remove Favorite" : "Favorite",
						systemImage: favorited ? "star.slash" : "star"
					)
				}
			}
			
			if !isFree {
				Button {
					wishlistManager.toggle(item.skin.id)
				} label: {
					Label(
						wishlisted ? "Remove from Wishlist" : "Add to Wishlist",
						systemImage: wishlisted ? "heart.slash" : "heart"
					)
				}
			}
		}
	}
	
	private func orderedSkins(for weapon: WeaponInfo) -> [ResolvedLevel] {
		let mapped: [ResolvedLevel] = weapon.skins.compactMap { skin in
			guard !skin.levels.isEmpty else { return nil }
			let index = skin.levels.lastIndex { inventory.owns($0.id) } ?? 0
			return ResolvedLevel(weapon: weapon, skin: skin, level: skin.levels[index], levelIndex: index)
		}
		return mapped.sorted { lhs, rhs in
			let lhsRank = sortRank(lhs.skin)
			let rhsRank = sortRank(rhs.skin)
			if lhsRank != rhsRank { return lhsRank < rhsRank }
			return lhs.skin.displayName.localizedCaseInsensitiveCompare(rhs.skin.displayName) == .orderedAscending
		}
	}
	
	private func sortRank(_ skin: WeaponSkin) -> Int {
		if skin.themeID == .random { return 0 }
		if skin.themeID == .standard { return 1 }
		if isFavorited(skin) { return 2 }
		if isOwned(skin) { return 3 }
		return 4
	}
	
	private func isOwned(_ skin: WeaponSkin) -> Bool {
		if skin.themeID.isFree { return true }
		return skin.levels.contains { inventory.owns($0.id) }
	}
	
	private func isFavorited(_ skin: WeaponSkin) -> Bool {
		favoritesManager.isSkinFavorited(skin, for: activeAccountID)
	}
}

extension WeaponSkin: Hashable {
	static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
	func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ResolvedLevel: SearchableAsset {
	var searchableText: String {
		level.displayName ?? skin.displayName
	}
	
	var sortValue: SortValue {
		.init(isFree: skin.themeID.isFree, name: searchableText)
	}
	
	struct SortValue: Comparable {
		var isFree: Bool
		var name: String
		
		static func < (lhs: Self, rhs: Self) -> Bool {
			(lhs.isFree ? 0 : 1, lhs.name)
			< (rhs.isFree ? 0 : 1, rhs.name)
		}
	}
}
