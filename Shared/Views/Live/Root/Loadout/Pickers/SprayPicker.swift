import SwiftUI
import ValorantAPI

struct SprayPicker: View {
	/// sprays and totems share the same loadout slots, so they share this picker
	enum Kind: Hashable {
		case sprays
		case totems
	}
	
	@Binding var selection: Loadout.Expression?
	var inventory: Inventory
	
	@State private var kind = Kind.sprays
	
	var body: some View {
		AssetsUnwrappingView { assets in
			VStack(spacing: 0) {
				Picker("Expression Type", selection: $kind) {
					Text("Sprays", comment: "Expression picker: sprays tab")
						.tag(Kind.sprays)
					Text("Totems", comment: "Expression picker: totems tab")
						.tag(Kind.totems)
				}
				.pickerStyle(.segmented)
				.padding(.horizontal)
				.padding(.vertical, 8)
				
				switch kind {
				case .sprays:
					sprayList(assets: assets)
				case .totems:
					totemList(assets: assets)
				}
			}
			.onAppear {
				// open on the totems tab if that's what the current selection is
				if selection?.totem != nil {
					kind = .totems
				}
			}
		}
		.navigationTitle("Choose Expression")
	}
	
	private func sprayList(assets: AssetCollection) -> some View {
		SearchableAssetPicker(
			allItems: assets.sprays,
			ownedItems: inventory.sprays
		) { spray in
			SelectableRow(selection: $selection, item: Loadout.Expression.spray(spray.id)) {
				spray.displayIcon.view()
					.frame(width: 48, height: 48)
				Text(spray.displayName)
				if spray.category == .contextual {
					Image(systemName: "exclamationmark.triangle")
						.foregroundStyle(.secondary)
				}
			}
		} deselector: {
			SelectableRow(selection: $selection, item: nil) {
				Label("No Spray", systemImage: "xmark")
			}
		}
	}
	
	private func totemList(assets: AssetCollection) -> some View {
		let totems = assets.totems ?? [:]
		// only the totems Riot reports as owned—plus whatever is currently equipped
		var owned = inventory.totems
		if let totem = selection?.totem, totems[totem] != nil {
			owned.insert(totem)
		}
		return SearchableAssetPicker(
			allItems: totems,
			ownedItems: owned
		) { totem in
			SelectableRow(selection: $selection, item: Loadout.Expression.totem(totem.id)) {
				totem.displayIcon.view()
					.frame(width: 48, height: 48)
				Text(totem.displayName)
			}
		} deselector: {
			SelectableRow(selection: $selection, item: nil) {
				Label("No Totem", systemImage: "xmark")
			}
		}
	}
}

extension SprayInfo: SearchableAsset {
	var searchableText: String { displayName }
}

extension TotemInfo: SearchableAsset {
	var searchableText: String { displayName }
}

#if DEBUG
struct SprayPicker_Previews: PreviewProvider, PreviewProviderWithAssets {
	static func previews(assets: AssetCollection) -> some View {
		SprayPicker(
			selection: .constant(Loadout.Expression.spray(PreviewData.inventory.sprays.first!)),
			inventory: PreviewData.inventory
		)
		.withToolbar()
	}
}
#endif
