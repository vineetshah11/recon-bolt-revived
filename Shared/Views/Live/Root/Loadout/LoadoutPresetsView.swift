import SwiftUI
import UIKit
import ValorantAPI

// MARK: - Loadout Presets

struct LoadoutPresetsView: View {
	@Binding var loadout: UpdatableLoadout
	var inventory: Inventory
	
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var showingNewSheet = false
	@State private var bannerEditTarget: LoadoutPreset?
	@State private var renameTarget: LoadoutPreset?
	@State private var renameText = ""
	
	var body: some View {
		let items = presetManager.presets(for: loadout.subject, favoritesOnly: false)
		
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				infoBannerCard(
					"Save complete loadouts — weapon skins, buddies, player card, title, and expressions — and apply them with one tap, even during agent select."
				)
				
				VStack(alignment: .leading, spacing: 8) {
					Text("Saved Presets")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.secondary)
						.padding(.horizontal, 4)
					
					if items.isEmpty {
						emptyPresetsCard(
							title: "No Loadout Presets Yet",
							subtitle: "Save your equipped weapons, player card, title, and expressions to switch loadouts in one tap.",
							buttonTitle: "Create Loadout Preset"
						) {
							showingNewSheet = true
						}
					} else {
						VStack(spacing: 0) {
							ForEach(Array(items.enumerated()), id: \.element.id) { index, preset in
								NavigationLink {
									LoadoutPresetInspectorView(
										preset: preset,
										currentLoadout: loadout,
										inventory: inventory
									) { applied in
										loadout = applied
										dismiss()
									}
								} label: {
									loadoutPresetRow(preset)
								}
								.buttonStyle(.plain)
								.contextMenu {
									Button {
										loadout = preset.applying(to: loadout)
										dismiss()
									} label: {
										Label("Equip Preset", systemImage: "checkmark.circle")
									}
									
									Button {
										withAnimation {
											presetManager.togglePinned(id: preset.id)
										}
									} label: {
										Label(
											preset.isPinned ? "Unpin" : "Pin to Top",
											systemImage: preset.isPinned ? "pin.slash" : "pin"
										)
									}
									
									Button {
										bannerEditTarget = preset
									} label: {
										Label("Change Banner", systemImage: "photo")
									}
									
									Button {
										renameText = preset.name
										renameTarget = preset
									} label: {
										Label("Rename", systemImage: "pencil")
									}
									
									Button(role: .destructive) {
										withAnimation {
											presetManager.delete(id: preset.id)
										}
									} label: {
										Label("Delete", systemImage: "trash")
									}
								}
								
								if index < items.count - 1 {
									Divider()
										.opacity(0.25)
										.padding(.leading, 72)
								}
							}
						}
						.background(
							Color.secondaryGroupedBackground,
							in: RoundedRectangle(cornerRadius: 18, style: .continuous)
						)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground.ignoresSafeArea())
		.navigationTitle("Loadout Presets")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				Button { dismiss() } label: {
					Image(systemName: "xmark")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(Color.accentColor)
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					showingNewSheet = true
				} label: {
					Image(systemName: "plus")
						.font(.subheadline.weight(.semibold))
				}
			}
		}
		.sheet(isPresented: $showingNewSheet) {
			NewLoadoutPresetSheet(
				currentLoadout: loadout,
				inventory: inventory,
				defaultName: "Preset \(items.count + 1)"
			)
		}
		.sheet(item: $bannerEditTarget) { target in
			let currentTarget = presetManager.presets.first(where: { $0.id == target.id }) ?? target
			PresetBannerPickerSheet(
				currentSelection: PresetBannerChoice(
					cardID: currentTarget.bannerCardID,
					imageData: currentTarget.bannerImageData
				),
				equippedCardID: loadout.identity.card,
				inventory: inventory,
				accountID: loadout.subject
			) { choice in
				switch choice {
				case .none:
					presetManager.setBanner(id: target.id, cardID: nil, imageData: nil)
				case .card(let cardID):
					presetManager.setBanner(id: target.id, cardID: cardID, imageData: nil)
				case .image(let data):
					presetManager.setBanner(id: target.id, cardID: nil, imageData: data)
				}
			}
		}
		.alert(
			"Rename Preset",
			isPresented: Binding(
				get: { renameTarget != nil },
				set: { if !$0 { renameTarget = nil } }
			)
		) {
			TextField("Preset Name", text: $renameText)
			Button("Save") {
				if let target = renameTarget {
					presetManager.rename(target, to: renameText)
				}
				renameTarget = nil
			}
			Button("Cancel", role: .cancel) {
				renameTarget = nil
			}
		}
	}
	
	private func loadoutPresetRow(_ preset: LoadoutPreset) -> some View {
		HStack(spacing: 14) {
			PresetThumbnailView(
				bannerCardID: preset.bannerCardID,
				bannerImageData: preset.bannerImageData,
				fallbackIcon: "square.stack.3d.up.fill",
				size: 46,
				cornerRadius: 10
			)
			
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(preset.name)
						.font(.headline.weight(.medium))
						.foregroundStyle(.primary)
						.lineLimit(1)
					
					if preset.isPinned {
						Image(systemName: "pin.fill")
							.font(.caption)
							.foregroundStyle(.yellow)
					}
				}
				
				Text(preset.summaryLine)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			
			Spacer(minLength: 8)
			
			Image(systemName: "chevron.right")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.contentShape(Rectangle())
	}
}

private struct NewLoadoutPresetSheet: View {
	let currentLoadout: UpdatableLoadout
	let inventory: Inventory
	let defaultName: String
	
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var name: String = ""
	@State private var isPinned = false
	@State private var bannerCardID: PlayerCard.ID?
	@State private var bannerImageData: Data?
	@State private var showingBannerPicker = false
	
	@State private var includeCard = true
	@State private var includeTitle = true
	@State private var includeExpressions = true
	@State private var includeAllWeapons = true
	@State private var selectedWeapons: Set<Weapon.ID> = Set(Weapon.ID.orderInCollection)
	
	var body: some View {
		NavigationStack {
			Form {
				Section("Details") {
					TextField("Preset Name", text: $name)
					
					Button {
						showingBannerPicker = true
					} label: {
						HStack(spacing: 12) {
							PresetThumbnailView(
								bannerCardID: bannerCardID,
								bannerImageData: bannerImageData,
								fallbackIcon: "square.stack.3d.up.fill",
								size: 40,
								cornerRadius: 8
							)
							
							VStack(alignment: .leading, spacing: 2) {
								Text("Banner Image")
									.foregroundStyle(.primary)
								Text(bannerDescription)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							Text("Choose")
								.font(.subheadline.weight(.medium))
								.foregroundStyle(Color.accentColor)
						}
					}
					
					if bannerCardID != nil || bannerImageData != nil {
						Button("Remove Banner", role: .destructive) {
							bannerCardID = nil
							bannerImageData = nil
						}
					}
					
					Toggle(isOn: $isPinned) {
						Label("Pin to Top", systemImage: "pin")
					}
				}
				
				Section("Included Items") {
					Toggle("Player Card", isOn: $includeCard)
					Toggle("Player Title", isOn: $includeTitle)
					Toggle("Expressions", isOn: $includeExpressions)
					Toggle("All Weapons", isOn: $includeAllWeapons)
					
					if !includeAllWeapons {
						ForEach(Weapon.ID.orderInCollection, id: \.self) { weaponID in
							if currentLoadout.guns[weaponID] != nil,
							   let weapon = assets?.weapons[weaponID] {
								let isSelected = selectedWeapons.contains(weaponID)
								Button {
									if isSelected {
										selectedWeapons.remove(weaponID)
									} else {
										selectedWeapons.insert(weaponID)
									}
								} label: {
									HStack {
										Text(weapon.displayName)
											.foregroundStyle(.primary)
										Spacer()
										if let gun = currentLoadout.guns[weaponID],
										   let resolved = assets?.resolveSkin(gun.skin.level) {
											Text(resolved.skin.displayName)
												.font(.caption)
												.foregroundStyle(.secondary)
												.lineLimit(1)
										}
										Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
											.foregroundStyle(isSelected ? Color.accentColor : .secondary)
									}
								}
							}
						}
					}
				}
			}
			.navigationTitle("New Loadout Preset")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						let chosenWeapons: [Weapon.ID]? = includeAllWeapons
							? nil
							: Weapon.ID.orderInCollection.filter {
								selectedWeapons.contains($0) && currentLoadout.guns[$0] != nil
							}
						presetManager.saveNewPreset(
							name: name.isEmpty ? defaultName : name,
							loadout: currentLoadout,
							accountID: currentLoadout.subject,
							isPinned: isPinned,
							bannerCardID: bannerCardID,
							bannerImageData: bannerImageData,
							includeCard: includeCard,
							includeTitle: includeTitle,
							includeExpressions: includeExpressions,
							includedWeapons: chosenWeapons
						)
						dismiss()
					}
					.disabled(!includeCard && !includeTitle && !includeExpressions && !includeAllWeapons && selectedWeapons.isEmpty)
				}
			}
			.onAppear {
				if name.isEmpty {
					name = defaultName
				}
			}
			.sheet(isPresented: $showingBannerPicker) {
				PresetBannerPickerSheet(
					currentSelection: PresetBannerChoice(
						cardID: bannerCardID,
						imageData: bannerImageData
					),
					equippedCardID: currentLoadout.identity.card,
					inventory: inventory,
					accountID: currentLoadout.subject
				) { choice in
					switch choice {
					case .none:
						bannerCardID = nil
						bannerImageData = nil
					case .card(let cardID):
						bannerCardID = cardID
						bannerImageData = nil
					case .image(let data):
						bannerCardID = nil
						bannerImageData = data
					}
				}
			}
		}
	}
	
	private var bannerDescription: String {
		if bannerImageData != nil {
			return "Custom photo"
		} else if let bannerCardID, let card = assets?.playerCards[bannerCardID] {
			return card.displayName
		}
		return "None (default icon)"
	}
}

struct LoadoutPresetInspectorView: View {
	@State var preset: LoadoutPreset
	var currentLoadout: UpdatableLoadout
	var inventory: Inventory
	var onApply: (UpdatableLoadout) -> Void
	
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var showingRename = false
	@State private var renameText = ""
	@State private var showingBannerPicker = false
	
	var body: some View {
		List {
			Section {
				HStack(spacing: 14) {
					PresetThumbnailView(
						bannerCardID: preset.bannerCardID,
						bannerImageData: preset.bannerImageData,
						fallbackIcon: "square.stack.3d.up.fill",
						size: 58,
						cornerRadius: 12
					)
					
					VStack(alignment: .leading, spacing: 4) {
						HStack(spacing: 6) {
							Text(preset.name)
								.font(.title3.weight(.semibold))
							if preset.isPinned {
								Image(systemName: "pin.fill")
									.font(.caption)
									.foregroundStyle(.yellow)
							}
						}
						Text(preset.summaryLine)
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Text("Updated \(preset.updatedAt.formatted(date: .abbreviated, time: .shortened))")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.vertical, 4)
				
				Button {
					onApply(preset.applying(to: currentLoadout))
					dismiss()
				} label: {
					Label("Equip Preset", systemImage: "checkmark.circle.fill")
						.font(.headline)
						.foregroundStyle(Color.accentColor)
				}
			}
			
			Section("Customize") {
				Toggle(
					isOn: Binding(
						get: { preset.isPinned },
						set: { newValue in
							preset.isPinned = newValue
							presetManager.update(preset, refreshTimestamp: false)
						}
					)
				) {
					Label("Pin to Top", systemImage: "pin")
				}
				
				Button {
					showingBannerPicker = true
				} label: {
					Label("Change Banner", systemImage: "photo")
				}
				
				Button {
					renameText = preset.name
					showingRename = true
				} label: {
					Label("Rename Preset", systemImage: "pencil")
				}
				
				Button {
					preset.loadout = currentLoadout
					presetManager.update(preset)
				} label: {
					Label("Overwrite with Current Loadout", systemImage: "arrow.triangle.2.circlepath")
				}
				
				Button(role: .destructive) {
					presetManager.delete(id: preset.id)
					dismiss()
				} label: {
					Label("Delete Preset", systemImage: "trash")
				}
			}
			
			Section("Included Sections") {
				Toggle(
					"Player Card",
					isOn: Binding(
						get: { preset.includeCard },
						set: { newValue in
							preset.includeCard = newValue
							presetManager.update(preset)
						}
					)
				)
				Toggle(
					"Player Title",
					isOn: Binding(
						get: { preset.includeTitle },
						set: { newValue in
							preset.includeTitle = newValue
							presetManager.update(preset)
						}
					)
				)
				Toggle(
					"Expressions",
					isOn: Binding(
						get: { preset.includeExpressions },
						set: { newValue in
							preset.includeExpressions = newValue
							presetManager.update(preset)
						}
					)
				)
			}
			
			if preset.includeCard || preset.includeTitle {
				Section("Identity") {
					if preset.includeCard {
						PlayerCardImage.wide(preset.loadout.identity.card)
							.cornerRadius(8)
					}
					if preset.includeTitle {
						HStack {
							Text("Title")
							Spacer()
							PlayerTitleLabel(titleID: preset.loadout.identity.title)
								.foregroundStyle(.secondary)
						}
					}
				}
			}
			
			if preset.includeExpressions {
				Section("Expressions") {
					ForEach(0..<4, id: \.self) { index in
						let expr = preset.loadout.expressions[index] ?? .empty
						HStack {
							Text("Slot \(index + 1)")
							Spacer()
							if expr.isEmpty {
								Text("Empty")
									.foregroundStyle(.secondary)
							} else {
								ExpressionImageView(expression: expr)
									.frame(width: 28, height: 28)
							}
						}
					}
				}
			}
			
			Section("Weapons (\(preset.activeWeaponIDs.count))") {
				ForEach(preset.activeWeaponIDs, id: \.self) { gunID in
					if let gun = preset.loadout.guns[gunID],
					   let weapon = assets?.weapons[gunID],
					   let resolved = assets?.resolveSkin(gun.skin.level) {
						HStack {
							Text(weapon.displayName)
							Spacer()
							Text(resolved.skin.displayName)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					}
				}
			}
		}
		.navigationTitle(preset.name)
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $showingBannerPicker) {
			PresetBannerPickerSheet(
				currentSelection: PresetBannerChoice(
					cardID: preset.bannerCardID,
					imageData: preset.bannerImageData
				),
				equippedCardID: currentLoadout.identity.card,
				inventory: inventory,
				accountID: preset.accountID ?? currentLoadout.subject
			) { choice in
				switch choice {
				case .none:
					preset.bannerCardID = nil
					preset.bannerImageData = nil
				case .card(let cardID):
					preset.bannerCardID = cardID
					preset.bannerImageData = nil
				case .image(let data):
					preset.bannerCardID = nil
					preset.bannerImageData = data
				}
				presetManager.update(preset)
			}
		}
		.alert("Rename Preset", isPresented: $showingRename) {
			TextField("Name", text: $renameText)
			Button("Save") {
				preset.name = renameText
				presetManager.update(preset)
			}
			Button("Cancel", role: .cancel) {}
		}
	}
}

// MARK: - Favorites Presets

struct FavoritesPresetsView: View {
	let accountID: User.ID
	var equippedCardID: PlayerCard.ID?
	var inventory: Inventory
	
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@EnvironmentObject private var favoritesManager: FavoritesManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@Environment(\.valorantLoad) private var load
	
	@State private var showingNewSheet = false
	@State private var bannerEditTarget: FavoritesPreset?
	@State private var renameTarget: FavoritesPreset?
	@State private var renameText = ""
	@State private var applyingStatus: String?
	@State private var applyError: String?
	
	var body: some View {
		let items = presetManager.favoritesPresets(for: accountID)
		
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				infoBannerCard(
					"Save your full set of favorites — skin chromas, player cards, sprays, buddies, and titles — as presets, and switch between them with one tap."
				)
				
				if let applyingStatus {
					HStack(spacing: 10) {
						ProgressView()
							.controlSize(.small)
						Text(applyingStatus)
							.font(.subheadline.weight(.medium))
						Spacer()
					}
					.padding(14)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				}
				
				VStack(alignment: .leading, spacing: 8) {
					Text("Saved Presets")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.secondary)
						.padding(.horizontal, 4)
					
					if items.isEmpty {
						emptyPresetsCard(
							title: "No Favorites Presets Yet",
							subtitle: "Snapshot your current in-game VALORANT favorites so you can swap collections anytime in one tap.",
							buttonTitle: "Save Current Favorites"
						) {
							showingNewSheet = true
						}
					} else {
						VStack(spacing: 0) {
							ForEach(Array(items.enumerated()), id: \.element.id) { index, preset in
								NavigationLink {
									FavoritesPresetInspectorView(
										preset: preset,
										accountID: accountID,
										equippedCardID: equippedCardID,
										inventory: inventory
									)
								} label: {
									favoritesPresetRow(preset)
								}
								.buttonStyle(.plain)
								.contextMenu {
									Button {
										Task { await applyPreset(preset) }
									} label: {
										Label("Apply Favorites Preset", systemImage: "checkmark.circle")
									}
									
									Button {
										withAnimation {
											presetManager.toggleFavoritesPresetPinned(id: preset.id)
										}
									} label: {
										Label(
											preset.isPinned ? "Unpin" : "Pin to Top",
											systemImage: preset.isPinned ? "pin.slash" : "pin"
										)
									}
									
									Button {
										bannerEditTarget = preset
									} label: {
										Label("Change Banner", systemImage: "photo")
									}
									
									Button {
										renameText = preset.name
										renameTarget = preset
									} label: {
										Label("Rename", systemImage: "pencil")
									}
									
									Button(role: .destructive) {
										withAnimation {
											presetManager.deleteFavoritesPreset(id: preset.id)
										}
									} label: {
										Label("Delete", systemImage: "trash")
									}
								}
								
								if index < items.count - 1 {
									Divider()
										.opacity(0.25)
										.padding(.leading, 72)
								}
							}
						}
						.background(
							Color.secondaryGroupedBackground,
							in: RoundedRectangle(cornerRadius: 18, style: .continuous)
						)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground.ignoresSafeArea())
		.navigationTitle("Favorites Presets")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				Button { dismiss() } label: {
					Image(systemName: "xmark")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(Color.accentColor)
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					showingNewSheet = true
				} label: {
					Image(systemName: "plus")
						.font(.subheadline.weight(.semibold))
				}
			}
		}
		.task {
			await load { client in
				await favoritesManager.refreshIfNeeded(using: client)
			}
		}
		.sheet(isPresented: $showingNewSheet) {
			NewFavoritesPresetSheet(
				accountID: accountID,
				equippedCardID: equippedCardID,
				inventory: inventory,
				defaultName: "Favorites Preset \(items.count + 1)"
			)
		}
		.sheet(item: $bannerEditTarget) { target in
			let currentTarget = presetManager.favoritesPresets.first(where: { $0.id == target.id }) ?? target
			PresetBannerPickerSheet(
				currentSelection: PresetBannerChoice(
					cardID: currentTarget.bannerCardID,
					imageData: currentTarget.bannerImageData
				),
				equippedCardID: equippedCardID,
				inventory: inventory,
				accountID: accountID
			) { choice in
				switch choice {
				case .none:
					presetManager.setFavoritesPresetBanner(id: target.id, cardID: nil, imageData: nil)
				case .card(let cardID):
					presetManager.setFavoritesPresetBanner(id: target.id, cardID: cardID, imageData: nil)
				case .image(let data):
					presetManager.setFavoritesPresetBanner(id: target.id, cardID: nil, imageData: data)
				}
			}
		}
		.alert(
			"Rename Preset",
			isPresented: Binding(
				get: { renameTarget != nil },
				set: { if !$0 { renameTarget = nil } }
			)
		) {
			TextField("Preset Name", text: $renameText)
			Button("Save") {
				if let target = renameTarget {
					presetManager.renameFavoritesPreset(target, to: renameText)
				}
				renameTarget = nil
			}
			Button("Cancel", role: .cancel) {
				renameTarget = nil
			}
		}
		.alert(
			"Could Not Apply Favorites",
			isPresented: Binding(
				get: { applyError != nil },
				set: { if !$0 { applyError = nil } }
			)
		) {
			Button("OK", role: .cancel) {}
		} message: {
			if let applyError {
				Text(applyError)
			}
		}
	}
	
	private func favoritesPresetRow(_ preset: FavoritesPreset) -> some View {
		HStack(spacing: 14) {
			PresetThumbnailView(
				bannerCardID: preset.bannerCardID,
				bannerImageData: preset.bannerImageData,
				fallbackIcon: "star.square.on.square",
				size: 46,
				cornerRadius: 10
			)
			
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(preset.name)
						.font(.headline.weight(.medium))
						.foregroundStyle(.primary)
						.lineLimit(1)
					
					if preset.isPinned {
						Image(systemName: "pin.fill")
							.font(.caption)
							.foregroundStyle(.yellow)
					}
				}
				
				Text(preset.subtitleLine)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			
			Spacer(minLength: 8)
			
			Image(systemName: "chevron.right")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.contentShape(Rectangle())
	}
	
	@MainActor
	private func applyPreset(_ preset: FavoritesPreset) async {
		applyingStatus = "Syncing \(preset.name)..."
		defer { applyingStatus = nil }
		await load { client in
			do {
				try await favoritesManager.applyFavoritesPreset(
					itemIDs: preset.itemIDs,
					using: client
				) { completed, total in
					Task { @MainActor in
						applyingStatus = "Syncing \(completed) / \(total)..."
					}
				}
			} catch {
				applyError = error.localizedDescription
			}
		}
	}
}

private struct NewFavoritesPresetSheet: View {
	let accountID: User.ID
	let equippedCardID: PlayerCard.ID?
	let inventory: Inventory
	let defaultName: String
	
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@EnvironmentObject private var favoritesManager: FavoritesManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@Environment(\.valorantLoad) private var load
	
	@State private var name = ""
	@State private var isPinned = false
	@State private var bannerCardID: PlayerCard.ID?
	@State private var bannerImageData: Data?
	@State private var showingBannerPicker = false
	@State private var isRefreshingFavorites = false
	
	private var currentFavoriteIDs: [LowercaseUUID] {
		let set = favoritesManager.itemIDs(for: accountID)
		return set.sorted { $0.description < $1.description }
	}
	
	private var currentFavoriteCount: Int {
		favoritesManager.itemIDs(for: accountID).count
	}
	
	var body: some View {
		NavigationStack {
			Form {
				Section("Details") {
					TextField("Preset Name", text: $name)
					
					Button {
						showingBannerPicker = true
					} label: {
						HStack(spacing: 12) {
							PresetThumbnailView(
								bannerCardID: bannerCardID,
								bannerImageData: bannerImageData,
								fallbackIcon: "star.square.on.square",
								size: 40,
								cornerRadius: 8
							)
							
							VStack(alignment: .leading, spacing: 2) {
								Text("Banner Image")
									.foregroundStyle(.primary)
								Text(bannerDescription)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							Text("Choose")
								.font(.subheadline.weight(.medium))
								.foregroundStyle(Color.accentColor)
						}
					}
					
					if bannerCardID != nil || bannerImageData != nil {
						Button("Remove Banner", role: .destructive) {
							bannerCardID = nil
							bannerImageData = nil
						}
					}
					
					Toggle(isOn: $isPinned) {
						Label("Pin to Top", systemImage: "pin")
					}
				}
				
				Section {
					HStack {
						Text("In-Game Favorites")
						Spacer()
						if isRefreshingFavorites {
							ProgressView()
								.controlSize(.small)
						} else {
							Text("\(currentFavoriteCount) items")
								.foregroundStyle(.secondary)
								.monospacedDigit()
						}
					}
					
					Button {
						Task {
							isRefreshingFavorites = true
							await load { client in
								await favoritesManager.refresh(using: client)
							}
							isRefreshingFavorites = false
						}
					} label: {
						Label("Refresh From VALORANT", systemImage: "arrow.clockwise")
					}
					.disabled(isRefreshingFavorites)
				} footer: {
					Text("Captures your current in-game VALORANT favorites (skins, cards, sprays, buddies, and titles).")
				}
			}
			.navigationTitle("New Favorites Preset")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						presetManager.saveNewFavoritesPreset(
							name: name.isEmpty ? defaultName : name,
							itemIDs: currentFavoriteIDs,
							accountID: accountID,
							isPinned: isPinned,
							bannerCardID: bannerCardID,
							bannerImageData: bannerImageData
						)
						dismiss()
					}
				}
			}
			.onAppear {
				if name.isEmpty {
					name = defaultName
				}
			}
			.task {
				if favoritesManager.favorites(for: accountID) == nil {
					isRefreshingFavorites = true
					await load { client in
						await favoritesManager.refresh(using: client)
					}
					isRefreshingFavorites = false
				}
			}
			.sheet(isPresented: $showingBannerPicker) {
				PresetBannerPickerSheet(
					currentSelection: PresetBannerChoice(
						cardID: bannerCardID,
						imageData: bannerImageData
					),
					equippedCardID: equippedCardID,
					inventory: inventory,
					accountID: accountID
				) { choice in
					switch choice {
					case .none:
						bannerCardID = nil
						bannerImageData = nil
					case .card(let cardID):
						bannerCardID = cardID
						bannerImageData = nil
					case .image(let data):
						bannerCardID = nil
						bannerImageData = data
					}
				}
			}
		}
	}
	
	private var bannerDescription: String {
		if bannerImageData != nil {
			return "Custom photo"
		} else if let bannerCardID, let card = assets?.playerCards[bannerCardID] {
			return card.displayName
		}
		return "None (default icon)"
	}
}

struct FavoritesPresetInspectorView: View {
	@State var preset: FavoritesPreset
	let accountID: User.ID
	var equippedCardID: PlayerCard.ID?
	var inventory: Inventory
	
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@EnvironmentObject private var favoritesManager: FavoritesManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@Environment(\.valorantLoad) private var load
	
	@State private var showingRename = false
	@State private var renameText = ""
	@State private var showingBannerPicker = false
	@State private var applyProgress: (completed: Int, total: Int)?
	@State private var applyError: String?
	@State private var cachedResolvedItems: [ResolvedFavoriteRow] = []
	
	private struct ResolvedFavoriteRow: Identifiable {
		let id: LowercaseUUID
		let title: String
		let category: String
		let icon: AssetImage?
	}
	
	private struct ItemsKey: Equatable {
		let itemIDs: [LowercaseUUID]
		let version: AssetVersion?
	}
	
	var body: some View {
		let resolved = cachedResolvedItems
		
		List {
			Section {
				HStack(spacing: 14) {
					PresetThumbnailView(
						bannerCardID: preset.bannerCardID,
						bannerImageData: preset.bannerImageData,
						fallbackIcon: "star.square.on.square",
						size: 58,
						cornerRadius: 12
					)
					
					VStack(alignment: .leading, spacing: 4) {
						HStack(spacing: 6) {
							Text(preset.name)
								.font(.title3.weight(.semibold))
							if preset.isPinned {
								Image(systemName: "pin.fill")
									.font(.caption)
									.foregroundStyle(.yellow)
							}
						}
						Text(preset.subtitleLine)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.vertical, 4)
				
				Button {
					Task { await applyPreset() }
				} label: {
					HStack {
						Label(
							applyProgress == nil ? "Apply Favorites Preset" : "Applying...",
							systemImage: "checkmark.circle.fill"
						)
						.font(.headline)
						.foregroundStyle(Color.accentColor)
						
						Spacer()
						
						if let applyProgress {
							Text("\(applyProgress.completed)/\(applyProgress.total)")
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
						}
					}
				}
				.disabled(favoritesManager.isApplyingPreset)
			}
			
			Section("Customize") {
				Toggle(
					isOn: Binding(
						get: { preset.isPinned },
						set: { newValue in
							preset.isPinned = newValue
							presetManager.updateFavoritesPreset(preset, refreshTimestamp: false)
						}
					)
				) {
					Label("Pin to Top", systemImage: "pin")
				}
				
				Button {
					showingBannerPicker = true
				} label: {
					Label("Change Banner", systemImage: "photo")
				}
				
				Button {
					renameText = preset.name
					showingRename = true
				} label: {
					Label("Rename Preset", systemImage: "pencil")
				}
				
				Button {
					Task {
						await load { client in
							await favoritesManager.refresh(using: client)
							let updatedIDs = favoritesManager.itemIDs(for: accountID)
								.sorted { $0.description < $1.description }
							preset.itemIDs = updatedIDs
							presetManager.updateFavoritesPreset(preset)
						}
					}
				} label: {
					Label("Overwrite with Current In-Game Favorites", systemImage: "arrow.triangle.2.circlepath")
				}
				
				Button(role: .destructive) {
					presetManager.deleteFavoritesPreset(id: preset.id)
					dismiss()
				} label: {
					Label("Delete Preset", systemImage: "trash")
				}
			}
			
			Section("Items (\(preset.itemIDs.count))") {
				if resolved.isEmpty {
					Text("No items in this preset.")
						.foregroundStyle(.secondary)
				} else {
					ForEach(resolved) { item in
						HStack(spacing: 12) {
							if let icon = item.icon {
								icon.view()
									.frame(width: 34, height: 34)
									.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
							} else {
								RoundedRectangle(cornerRadius: 6, style: .continuous)
									.fill(Color.tertiaryGroupedBackground)
									.frame(width: 34, height: 34)
									.overlay {
										Image(systemName: "star.fill")
											.font(.caption)
											.foregroundStyle(.secondary)
									}
							}
							
							VStack(alignment: .leading, spacing: 2) {
								Text(item.title)
									.font(.subheadline.weight(.medium))
									.lineLimit(1)
								Text(item.category)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						.swipeActions(edge: .trailing) {
							Button(role: .destructive) {
								preset.itemIDs.removeAll { $0 == item.id }
								presetManager.updateFavoritesPreset(preset)
							} label: {
								Label("Remove", systemImage: "trash")
							}
						}
					}
				}
			}
		}
		.navigationTitle(preset.name)
		.navigationBarTitleDisplayMode(.inline)
		.task(id: ItemsKey(itemIDs: preset.itemIDs, version: assets?.version)) {
			cachedResolvedItems = resolvedItems()
		}
		.sheet(isPresented: $showingBannerPicker) {
			PresetBannerPickerSheet(
				currentSelection: PresetBannerChoice(
					cardID: preset.bannerCardID,
					imageData: preset.bannerImageData
				),
				equippedCardID: equippedCardID,
				inventory: inventory,
				accountID: accountID
			) { choice in
				switch choice {
				case .none:
					preset.bannerCardID = nil
					preset.bannerImageData = nil
				case .card(let cardID):
					preset.bannerCardID = cardID
					preset.bannerImageData = nil
				case .image(let data):
					preset.bannerCardID = nil
					preset.bannerImageData = data
				}
				presetManager.updateFavoritesPreset(preset)
			}
		}
		.alert("Rename Preset", isPresented: $showingRename) {
			TextField("Name", text: $renameText)
			Button("Save") {
				preset.name = renameText
				presetManager.updateFavoritesPreset(preset)
			}
			Button("Cancel", role: .cancel) {}
		}
		.alert(
			"Could Not Apply Favorites",
			isPresented: Binding(
				get: { applyError != nil },
				set: { if !$0 { applyError = nil } }
			)
		) {
			Button("OK", role: .cancel) {}
		} message: {
			if let applyError {
				Text(applyError)
			}
		}
	}
	
	@MainActor
	private func applyPreset() async {
		applyProgress = (0, max(1, preset.itemIDs.count))
		defer { applyProgress = nil }
		await load { client in
			do {
				try await favoritesManager.applyFavoritesPreset(
					itemIDs: preset.itemIDs,
					using: client
				) { completed, total in
					applyProgress = (completed, total)
				}
			} catch {
				applyError = error.localizedDescription
			}
		}
	}
	
	private func resolvedItems() -> [ResolvedFavoriteRow] {
		guard let assets else {
			return preset.itemIDs.map {
				ResolvedFavoriteRow(id: $0, title: $0.description, category: "Item", icon: nil)
			}
		}
		
		var skinByID: [LowercaseUUID: WeaponSkin] = [:]
		var chromaIconByID: [LowercaseUUID: AssetImage] = [:]
		for weapon in assets.weapons.values {
			for skin in weapon.skins {
				skinByID[skin.id.rawID] = skin
				for level in skin.levels {
					skinByID[level.id.rawID] = skin
				}
				for chroma in skin.chromas {
					skinByID[chroma.id.rawID] = skin
					chromaIconByID[chroma.id.rawID] = chroma.displayIcon ?? chroma.fullRender
				}
			}
		}
		
		return preset.itemIDs.map { rawID in
			if let card = assets.playerCards[PlayerCard.ID(rawID: rawID)] {
				return ResolvedFavoriteRow(
					id: rawID,
					title: card.displayName,
					category: "Player Card",
					icon: card.smallArt
				)
			}
			if let spray = assets.sprays[Spray.ID(rawID: rawID)] {
				return ResolvedFavoriteRow(
					id: rawID,
					title: spray.displayName,
					category: "Spray",
					icon: spray.bestIcon
				)
			}
			if let buddy = assets.buddies[Weapon.Buddy.ID(rawID: rawID)]
				?? assets.resolveBuddy(Weapon.Buddy.Level.ID(rawID: rawID)) {
				return ResolvedFavoriteRow(
					id: rawID,
					title: buddy.displayName,
					category: "Gun Buddy",
					icon: buddy.displayIcon
				)
			}
			if let title = assets.playerTitles[PlayerTitle.ID(rawID: rawID)] {
				return ResolvedFavoriteRow(
					id: rawID,
					title: title.titleText ?? title.displayName ?? "Title",
					category: "Player Title",
					icon: nil
				)
			}
			if let flex = assets.flex[Totem.ID(rawID: rawID)] {
				return ResolvedFavoriteRow(
					id: rawID,
					title: flex.displayName,
					category: "Flex",
					icon: flex.displayIcon
				)
			}
			if let skin = skinByID[rawID] {
				let icon = chromaIconByID[rawID] ?? skin.displayIcon
				return ResolvedFavoriteRow(
					id: rawID,
					title: skin.displayName,
					category: "Weapon Skin",
					icon: icon
				)
			}
			return ResolvedFavoriteRow(
				id: rawID,
				title: String(rawID.description.prefix(8)) + "…",
				category: "Item",
				icon: nil
			)
		}
	}
}

// MARK: - Shared Helpers

@ViewBuilder
private func infoBannerCard(_ text: LocalizedStringKey) -> some View {
	Text(text)
		.font(.subheadline)
		.foregroundStyle(.secondary)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
}

private func emptyPresetsCard(
	title: LocalizedStringKey,
	subtitle: LocalizedStringKey,
	buttonTitle: LocalizedStringKey,
	action: @escaping () -> Void
) -> some View {
	VStack(spacing: 12) {
		Text(title)
			.font(.headline)
		Text(subtitle)
			.font(.subheadline)
			.foregroundStyle(.secondary)
			.multilineTextAlignment(.center)
		Button(action: action) {
			Text(buttonTitle)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.white)
				.padding(.horizontal, 18)
				.padding(.vertical, 10)
				.background(Color.accentColor, in: Capsule())
		}
		.buttonStyle(.plain)
		.padding(.top, 2)
	}
	.frame(maxWidth: .infinity)
	.padding(22)
	.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
}

struct LoadoutShareSheet: View {
	var loadout: UpdatableLoadout
	
	@Environment(\.imageManager) private var imageManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@State private var preloadedImages: [AssetImage: UIImage] = [:]
	@State private var renderedImage: UIImage?
	@State private var isRendering = true
	
	private let showcaseWeapons: [Weapon.ID] = [
		.vandal, .phantom, .operator, .sheriff, .ghost, .melee
	]
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 16) {
					snapshotCardView(images: preloadedImages, useLiveFallback: true)
					
					if let renderedImage {
						let swiftUIImage = Image(uiImage: renderedImage)
						ShareLink(
							item: swiftUIImage,
							preview: SharePreview("VALORANT Loadout", image: swiftUIImage)
						) {
							Label("Share Loadout Image", systemImage: "square.and.arrow.up")
								.font(.headline)
								.frame(maxWidth: .infinity)
								.padding()
								.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
								.foregroundStyle(.white)
						}
					} else if isRendering {
						ProgressView("Preparing image...")
							.padding(.vertical, 8)
					}
				}
				.padding()
			}
			.navigationTitle("Share Loadout")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
			.task {
				await prepareAndRenderSnapshot()
			}
		}
	}
	
	private func snapshotCardView(images: [AssetImage: UIImage], useLiveFallback: Bool) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			let cardAsset = assets?.playerCards[loadout.identity.card]?.wideArt
			Group {
				if let cardAsset, let uiImage = images[cardAsset] {
					Image(uiImage: uiImage)
						.resizable()
						.aspectRatio(452.0 / 128.0, contentMode: .fit)
				} else if useLiveFallback {
					PlayerCardImage.wide(loadout.identity.card)
				} else {
					Color.secondaryGroupedBackground
						.aspectRatio(452.0 / 128.0, contentMode: .fit)
				}
			}
			.cornerRadius(12)
			
			HStack {
				Text(assets?.playerTitles[loadout.identity.title]?.displayName ?? "No Title")
					.font(.headline)
				Spacer()
				Text("Recon Bolt")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			
			LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
				ForEach(showcaseWeapons, id: \.self) { gunID in
					if let gun = loadout.guns[gunID],
					   let weapon = assets?.weapons[gunID],
					   let resolved = assets?.resolveSkin(gun.skin.level) {
						let weaponAsset = resolved.chroma(gun.skin.chroma)?.fullRender ?? resolved.displayIcon
						VStack(alignment: .leading, spacing: 4) {
							Text(weapon.displayName)
								.font(.caption2.weight(.semibold))
								.foregroundStyle(.secondary)
							Group {
								if let weaponAsset, let uiImage = images[weaponAsset] {
									Image(uiImage: uiImage)
										.resizable()
										.scaledToFit()
								} else if useLiveFallback, let weaponAsset {
									weaponAsset.view(preferFullResolution: true)
								} else {
									Color.clear
								}
							}
							.frame(height: 36)
							.frame(maxWidth: .infinity)
							Text(resolved.skin.displayName)
								.font(.caption.weight(.medium))
								.lineLimit(1)
						}
						.padding(8)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
					}
				}
			}
		}
		.padding()
		.background(Color.groupedBackground, in: RoundedRectangle(cornerRadius: 16))
		.roundedAndStroked(cornerRadius: 16)
	}
	
	@MainActor
	private func prepareAndRenderSnapshot() async {
		isRendering = true
		var targets: [AssetImage] = []
		if let card = assets?.playerCards[loadout.identity.card]?.wideArt {
			targets.append(card)
		}
		for gunID in showcaseWeapons {
			if let gun = loadout.guns[gunID],
			   let resolved = assets?.resolveSkin(gun.skin.level),
			   let icon = resolved.chroma(gun.skin.chroma)?.fullRender ?? resolved.displayIcon {
				targets.append(icon)
			}
		}
		
		var loaded: [AssetImage: UIImage] = [:]
		await withTaskGroup(of: (AssetImage, UIImage?).self) { group in
			for asset in targets {
				group.addTask { [imageManager] in
					let img = await imageManager.awaitImage(for: asset, bucket: .full)
					return (asset, img)
				}
			}
			for await (asset, img) in group {
				if let img {
					loaded[asset] = img
				}
			}
		}
		preloadedImages = loaded
		
		let renderer = ImageRenderer(
			content: snapshotCardView(images: loaded, useLiveFallback: false)
				.environment(\.assets, assets)
				.environment(\.imageManager, imageManager)
				.frame(width: 360)
				.preferredColorScheme(.dark)
		)
		renderer.scale = 3.0
		renderedImage = renderer.uiImage
		isRendering = false
	}
}
