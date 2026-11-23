import SwiftUI
import ValorantAPI

struct ExpressionPicker: View {
	enum Tab: String, CaseIterable, Identifiable {
		case sprays = "Sprays"
		case flex = "Flex"
		
		var id: String { rawValue }
	}
	
	@Binding var selection: Loadout.Expression
	var inventory: Inventory
	
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var tab: Tab
	@State private var search = ""
	@State private var ownedOnly = true
	
	init(selection: Binding<Loadout.Expression>, inventory: Inventory) {
		self._selection = selection
		self.inventory = inventory
		self._tab = State(initialValue: selection.wrappedValue.totem != nil ? .flex : .sprays)
	}
	
	var body: some View {
		VStack(spacing: 0) {
			Picker("Type", selection: $tab) {
				ForEach(Tab.allCases) { item in
					Text(item.rawValue).tag(item)
				}
			}
			.pickerStyle(.segmented)
			.padding(.horizontal)
			.padding(.vertical, 8)
			
			List {
				Section {
					Toggle("Owned Only", isOn: $ownedOnly)
					if !selection.isEmpty {
						Button(role: .destructive) {
							selection = .empty
							dismiss()
						} label: {
							Label("Clear Slot", systemImage: "trash")
						}
					}
				}
				
				if tab == .sprays {
					spraysSection
				} else {
					flexSection
				}
			}
			.searchable(text: $search, prompt: Text(tab == .sprays ? "Search sprays" : "Search flex"))
		}
		.navigationTitle("Choose Expression")
	}
	
	@ViewBuilder
	private var spraysSection: some View {
		let allSprays = Array((assets?.sprays ?? [:]).values)
		let items = allSprays
			.filter { !ownedOnly || inventory.sprays.contains($0.id) }
			.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		
		Section {
			ForEach(items) { spray in
				let isOwned = inventory.sprays.contains(spray.id)
				SelectableRow(
					isSelected: selection.spray == spray.id,
					select: {
						guard isOwned else { return }
						selection = .spray(spray.id)
						dismiss()
					}
				) {
					HStack(spacing: 12) {
						spray.bestIcon.view()
							.frame(width: 44, height: 44)
						VStack(alignment: .leading, spacing: 2) {
							Text(spray.displayName)
							if !isOwned {
								Text("Not Owned")
									.font(.caption2)
									.foregroundStyle(.secondary)
							}
						}
					}
				}
				.disabled(!isOwned)
				.opacity(isOwned ? 1 : 0.5)
			}
		} footer: {
			Text("\(inventory.sprays.count)/\(allSprays.count) sprays owned")
		}
	}
	
	@ViewBuilder
	private var flexSection: some View {
		let allFlex = Array((assets?.flex ?? [:]).values).filter { $0.id != .none }
		let ownedFlexIDs: Set<Totem.ID> = {
			var set = inventory.totems.union(FlexInfo.defaultItems)
			if let equipped = selection.totem, equipped != .none {
				set.insert(equipped)
			}
			set.remove(.none)
			return set
		}()
		let items = allFlex
			.filter { !ownedOnly || ownedFlexIDs.contains($0.id) }
			.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		
		Section {
			if items.isEmpty {
				Text(ownedOnly ? "You do not own any Flex items yet, or switch off Owned Only to browse all Flex." : "No matching Flex items found.")
					.foregroundStyle(.secondary)
			} else {
				ForEach(items) { flex in
					let isOwned = ownedFlexIDs.contains(flex.id)
					SelectableRow(
						isSelected: selection.totem == flex.id,
						select: {
							guard isOwned else { return }
							selection = .totem(flex.id)
							dismiss()
						}
					) {
						HStack(spacing: 12) {
							flex.displayIcon?.view()
								.frame(width: 44, height: 44)
							VStack(alignment: .leading, spacing: 2) {
								Text(flex.displayName)
								if !isOwned {
									Text("Not Owned")
										.font(.caption2)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
					.disabled(!isOwned)
					.opacity(isOwned ? 1 : 0.5)
				}
			}
		} footer: {
			let ownedCount = allFlex.filter { ownedFlexIDs.contains($0.id) }.count
			Text("\(ownedCount)/\(allFlex.count) flex owned")
		}
	}
}
