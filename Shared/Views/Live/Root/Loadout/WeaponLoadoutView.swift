import SwiftUI
import ValorantAPI

struct WeaponLoadoutView: View {
	@Binding var loadout: UpdatableLoadout
	var inventory: Inventory
	
	var body: some View {
		AssetsUnwrappingView { assets in
			List {
				ForEach(Weapon.ID.orderInCollection, id: \.self) { gunID in
					let gun = $loadout[dynamicMember: \.guns[gunID]!]
					Section {
						GunCell(gun: gun, loadout: $loadout, inventory: inventory)
					} header: {
						Text(assets.weapons[gunID]?.displayName ?? "")
					}
				}
			}
		}
		.navigationTitle("Weapons")
	}
	
	struct GunCell: View {
		@Binding var gun: Loadout.Gun
		@Binding var loadout: UpdatableLoadout
		var inventory: Inventory
		
		@Environment(\.assets) private var assets
		
		var body: some View {
			if let resolved = assets?.resolveSkin(gun.skin.level) {
				NavigationLink {
					GunCustomizer(gun: $gun, loadout: $loadout, resolved: resolved, inventory: inventory)
				} label: {
					let chroma = resolved.chroma(gun.skin.chroma)
					HStack {
						if let buddy = gun.buddy {
							(assets?.buddies[buddy.buddy]?.displayIcon)
								.view()
								.frame(width: 60)
						}
						let icon = chroma?.fullRender ?? chroma?.displayIcon ?? resolved.displayIcon
						icon.view()
							.frame(maxWidth: .infinity)
					}
					.frame(height: 80)
					.padding(.vertical, 8)
				}
			} else {
				// The skin's assets are missing (outdated assets, or a skin that isn't in them yet).
				// Keep the row visible instead of quietly dropping the weapon from the list.
				HStack(spacing: 12) {
					Image(systemName: "questionmark.square.dashed")
						.font(.title3)
						.foregroundColor(.secondary)
						.frame(width: 60)
					
					VStack(alignment: .leading, spacing: 2) {
						Text(assets?.weapons[gun.id]?.displayName ?? String(localized: "Weapon", comment: "Weapon Loadout: fallback name"))
						Text("This skin couldn't be loaded. Try refreshing the app's assets.", comment: "Weapon Loadout: shown when a skin's assets are missing")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.frame(height: 80)
			}
		}
	}
}

#if DEBUG
struct WeaponLoadoutView_Previews: PreviewProvider {
	static var previews: some View {
		WeaponLoadoutView(
			loadout: .constant(.init(PreviewData.loadout)),
			inventory: PreviewData.inventory
		)
		.withToolbar()
    }
}
#endif
