import SwiftUI
import ValorantAPI

struct ExpressionPicker: View {
	enum Tab: String, CaseIterable, Identifiable {
		case sprays = "Sprays"
		case totems = "Totems"
		
		var id: String { rawValue }
	}
	
	private enum DetailTarget: Identifiable, Hashable {
		case spray(Spray.ID)
		case totem(Totem.ID)
		
		var id: String {
			switch self {
			case .spray(let id): return "spray-\(id)"
			case .totem(let id): return "totem-\(id)"
			}
		}
	}
	
	@Binding var selection: Loadout.Expression
	var inventory: Inventory
	
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var favoritesManager: FavoritesManager
	@EnvironmentObject private var wishlistManager: WishlistManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@Environment(\.valorantLoad) private var load
	
	@State private var tab: Tab
	@State private var search = ""
	@State private var filter: LoadoutItemFilter = .favoritesAndOwned
	@State private var detailTarget: DetailTarget?
	
	init(selection: Binding<Loadout.Expression>, inventory: Inventory) {
		self._selection = selection
		self.inventory = inventory
		self._tab = State(initialValue: selection.wrappedValue.totem != nil ? .totems : .sprays)
	}
	
	private var activeAccountID: User.ID? {
		accountManager.activeAccount?.id
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 14) {
				LoadoutPickerSearchField(
					prompt: "Search",
					text: $search
				)
				
				Picker("Type", selection: $tab) {
					ForEach(Tab.allCases) { item in
						Text(item.rawValue).tag(item)
					}
				}
				.pickerStyle(.segmented)
				
				if tab == .sprays {
					spraysContent
				} else {
					totemsContent
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Choose Expression")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				LoadoutPickerFilterMenu(filter: $filter)
			}
		}
		.navigationDestination(isPresented: Binding(
			get: { detailTarget != nil },
			set: { if !$0 { detailTarget = nil } }
		)) {
			if let assets, let detailTarget {
				switch detailTarget {
				case .spray(let id):
					if let spray = assets.sprays[id] {
						ExpressionDetailsView(subject: .spray(spray), inventory: inventory)
					}
				case .totem(let id):
					if let totem = assets.flex[id] {
						ExpressionDetailsView(subject: .totem(totem), inventory: inventory)
					}
				}
			}
		}
		.valorantLoadTask(id: activeAccountID) { client in
			await favoritesManager.refreshIfNeeded(using: client)
		}
	}
	
	// MARK: - Sprays
	
	@ViewBuilder
	private var spraysContent: some View {
		let allSprays = Array((assets?.sprays ?? [:]).values)
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		let ownedCount = allSprays.count { inventory.sprays.contains($0.id) }
		let favCount = allSprays.count { favoritesManager.isFavorited($0.id.rawID, for: activeAccountID) }
		
		let visible = allSprays.filter { spray in
			let owned = inventory.sprays.contains(spray.id)
			let favorited = favoritesManager.isFavorited(spray.id.rawID, for: activeAccountID)
			guard filter.matches(isOwned: owned, isFavorited: favorited) else { return false }
			return search.isEmpty || spray.displayName.localizedCaseInsensitiveContains(search)
		}
		
		LoadoutPickerStatsPill(
			total: allSprays.count,
			shown: visible.count,
			favorites: favCount,
			owned: ownedCount
		)
		
		VStack(spacing: 0) {
			clearExpressionRow
			
			ForEach(visible) { spray in
				Divider()
					.opacity(0.25)
					.padding(.leading, 16)
				
				sprayRow(spray)
			}
			
			if visible.isEmpty {
				Divider()
					.opacity(0.25)
					.padding(.leading, 16)
				emptyFilterRow(label: "No matching sprays found.")
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
	}
	
	private func sprayRow(_ spray: SprayInfo) -> some View {
		let isOwned = inventory.sprays.contains(spray.id)
		let isFavorited = favoritesManager.isFavorited(spray.id.rawID, for: activeAccountID)
		let isWishlisted = wishlistManager.contains(kind: .spray, itemID: spray.id.rawID)
		let isSelected = selection.spray == spray.id
		
		return Button {
			if isOwned {
				selection = .spray(spray.id)
				dismiss()
			} else {
				detailTarget = .spray(spray.id)
			}
		} label: {
			HStack(spacing: 14) {
				spray.bestIcon.view()
					.frame(width: 44, height: 44)
					.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
					.opacity(isOwned ? 1 : 0.5)
				
				HStack(spacing: 6) {
					Text(spray.displayName)
						.font(.body)
						.foregroundStyle(isOwned ? .primary : .secondary)
						.lineLimit(1)
					
					if spray.category == .contextual {
						Image(systemName: "exclamationmark.triangle")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				
				Spacer(minLength: 6)
				
				if isFavorited {
					Image(systemName: "star.fill")
						.font(.caption)
						.foregroundStyle(.yellow)
				}
				if isWishlisted {
					Image(systemName: "heart.fill")
						.font(.caption)
						.foregroundStyle(Color.accentColor)
				}
				if isSelected {
					Image(systemName: "checkmark.circle.fill")
						.font(.system(size: 19))
						.foregroundStyle(Color.accentColor)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.contextMenu {
			Button {
				detailTarget = .spray(spray.id)
			} label: {
				Label("View Details", systemImage: "info.circle")
			}
			
			if isOwned {
				Button {
					Task {
						await load { client in
							try await favoritesManager.toggleFavorite(itemID: spray.id.rawID, using: client)
						}
					}
				} label: {
					Label(
						isFavorited ? "Remove Favorite" : "Favorite",
						systemImage: isFavorited ? "star.slash" : "star"
					)
				}
			}
			
			Button {
				wishlistManager.toggle(kind: .spray, itemID: spray.id.rawID)
			} label: {
				Label(
					isWishlisted ? "Remove from Wishlist" : "Add to Wishlist",
					systemImage: isWishlisted ? "heart.slash" : "heart"
				)
			}
		}
	}
	
	// MARK: - Totems (Flex)
	
	@ViewBuilder
	private var totemsContent: some View {
		let allFlex = Array((assets?.flex ?? [:]).values)
			.filter { $0.id != .none }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		let ownedFlexIDs: Set<Totem.ID> = {
			var set = inventory.totems.union(FlexInfo.defaultItems)
			if let equipped = selection.totem, equipped != .none {
				set.insert(equipped)
			}
			set.remove(.none)
			return set
		}()
		let ownedCount = allFlex.count { ownedFlexIDs.contains($0.id) }
		let favCount = allFlex.count { favoritesManager.isFavorited($0.id.rawID, for: activeAccountID) }
		
		let visible = allFlex.filter { flex in
			let owned = ownedFlexIDs.contains(flex.id)
			let favorited = favoritesManager.isFavorited(flex.id.rawID, for: activeAccountID)
			guard filter.matches(isOwned: owned, isFavorited: favorited) else { return false }
			return search.isEmpty || flex.displayName.localizedCaseInsensitiveContains(search)
		}
		
		LoadoutPickerStatsPill(
			total: allFlex.count,
			shown: visible.count,
			favorites: favCount,
			owned: ownedCount
		)
		
		VStack(spacing: 0) {
			clearExpressionRow
			
			ForEach(visible) { flex in
				Divider()
					.opacity(0.25)
					.padding(.leading, 16)
				
				totemRow(flex, isOwned: ownedFlexIDs.contains(flex.id))
			}
			
			if visible.isEmpty {
				Divider()
					.opacity(0.25)
					.padding(.leading, 16)
				emptyFilterRow(label: "No matching totems found.")
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
	}
	
	private func totemRow(_ flex: FlexInfo, isOwned: Bool) -> some View {
		let isFavorited = favoritesManager.isFavorited(flex.id.rawID, for: activeAccountID)
		let isWishlisted = wishlistManager.contains(kind: .flex, itemID: flex.id.rawID)
		let isSelected = selection.totem == flex.id
		
		return Button {
			if isOwned {
				selection = .totem(flex.id)
				dismiss()
			} else {
				detailTarget = .totem(flex.id)
			}
		} label: {
			HStack(spacing: 14) {
				flex.displayIcon?.view()
					.frame(width: 44, height: 44)
					.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
					.opacity(isOwned ? 1 : 0.5)
				
				Text(flex.displayName)
					.font(.body)
					.foregroundStyle(isOwned ? .primary : .secondary)
					.lineLimit(1)
				
				Spacer(minLength: 6)
				
				if isFavorited {
					Image(systemName: "star.fill")
						.font(.caption)
						.foregroundStyle(.yellow)
				}
				if isWishlisted {
					Image(systemName: "heart.fill")
						.font(.caption)
						.foregroundStyle(Color.accentColor)
				}
				if isSelected {
					Image(systemName: "checkmark.circle.fill")
						.font(.system(size: 19))
						.foregroundStyle(Color.accentColor)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.contextMenu {
			Button {
				detailTarget = .totem(flex.id)
			} label: {
				Label("View Details", systemImage: "info.circle")
			}
			
			if isOwned {
				Button {
					Task {
						await load { client in
							try await favoritesManager.toggleFavorite(itemID: flex.id.rawID, using: client)
						}
					}
				} label: {
					Label(
						isFavorited ? "Remove Favorite" : "Favorite",
						systemImage: isFavorited ? "star.slash" : "star"
					)
				}
			}
			
			Button {
				wishlistManager.toggle(kind: .flex, itemID: flex.id.rawID)
			} label: {
				Label(
					isWishlisted ? "Remove from Wishlist" : "Add to Wishlist",
					systemImage: isWishlisted ? "heart.slash" : "heart"
				)
			}
		}
	}
	
	// MARK: - Shared Rows
	
	private var clearExpressionRow: some View {
		Button {
			selection = .empty
			dismiss()
		} label: {
			HStack(spacing: 14) {
				Image(systemName: "xmark")
					.font(.system(size: 18, weight: .medium))
					.foregroundStyle(Color.accentColor)
					.frame(width: 44, height: 32)
				
				Text("No Expression")
					.font(.body)
					.foregroundStyle(.primary)
				
				Spacer()
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
	
	private func emptyFilterRow(label: String) -> some View {
		Text(label)
			.font(.subheadline)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 24)
			.padding(.horizontal, 16)
	}
}
