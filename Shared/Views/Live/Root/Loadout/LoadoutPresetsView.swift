import SwiftUI
import ValorantAPI

struct LoadoutPresetsView: View {
	@Binding var loadout: UpdatableLoadout
	var inventory: Inventory
	var favoritesOnly: Bool = false
	
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@Environment(\.valorantLoad) private var load
	
	@State private var showingNewPrompt = false
	@State private var newPresetName = ""
	@State private var isCreatingFromFavorites = false
	
	var body: some View {
		let items = presetManager.presets(for: loadout.subject, favoritesOnly: favoritesOnly)
		
		List {
			Section {
				Button {
					newPresetName = favoritesOnly ? "Favorites Preset \(items.count + 1)" : "Preset \(items.count + 1)"
					isCreatingFromFavorites = false
					showingNewPrompt = true
				} label: {
					Label("Save Current Loadout as Preset", systemImage: "plus.circle.fill")
				}
				
				if favoritesOnly {
					AsyncButton {
						await load { client in
							let favs = try await client.getFavorites()
							if let assets {
								let generated = LoadoutPresetManager.randomizedLoadout(
									from: loadout,
									inventory: inventory,
									assets: assets,
									favorites: favs
								)
								presetManager.saveNewPreset(
									name: "In-Game Favorites (\(Date().formatted(date: .abbreviated, time: .omitted)))",
									loadout: generated,
									accountID: loadout.subject,
									isFavoritePreset: true
								)
							}
						}
					} label: {
						Label("Create Preset from VALORANT Favorites", systemImage: "star.fill")
					}
				}
			}
			
			Section {
				if items.isEmpty {
					Text(favoritesOnly
						? "No Favorites Presets saved yet. Save one from your current loadout or pull from your in-game VALORANT Favorites."
						: "No Loadout Presets saved yet. Tap above to snapshot your equipped weapons, card, title, and expressions.")
						.foregroundStyle(.secondary)
				} else {
					ForEach(items) { preset in
						NavigationLink {
							LoadoutPresetInspectorView(
								preset: preset,
								inventory: inventory,
								onApply: { applied in
									loadout = applied
									dismiss()
								}
							)
						} label: {
							VStack(alignment: .leading, spacing: 4) {
								HStack {
									Text(preset.name)
										.font(.headline)
									if preset.isFavoritePreset {
										Image(systemName: "star.fill")
											.font(.caption)
											.foregroundStyle(.yellow)
									}
								}
								Text("Updated \(preset.updatedAt.formatted(date: .abbreviated, time: .shortened))")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.padding(.vertical, 4)
						}
						.swipeActions(edge: .trailing) {
							Button(role: .destructive) {
								presetManager.delete(id: preset.id)
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
				}
			} header: {
				Text("Saved Presets")
			}
		}
		.navigationTitle(favoritesOnly ? "Favorites Presets" : "Loadout Presets")
		.alert("New Preset", isPresented: $showingNewPrompt) {
			TextField("Preset Name", text: $newPresetName)
			Button("Save") {
				presetManager.saveNewPreset(
					name: newPresetName,
					loadout: loadout,
					accountID: loadout.subject,
					isFavoritePreset: favoritesOnly
				)
			}
			Button("Cancel", role: .cancel) {}
		}
	}
}

struct LoadoutPresetInspectorView: View {
	@State var preset: LoadoutPreset
	var inventory: Inventory
	var onApply: (UpdatableLoadout) -> Void
	
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var showingRename = false
	@State private var renameText = ""
	
	var body: some View {
		List {
			Section {
				Button {
					onApply(preset.loadout)
					dismiss()
				} label: {
					Label("Equip Preset", systemImage: "checkmark.circle.fill")
						.font(.headline)
				}
				
				Button {
					renameText = preset.name
					showingRename = true
				} label: {
					Label("Rename Preset", systemImage: "pencil")
				}
				
				Toggle("Favorites Collection", isOn: Binding(
					get: { preset.isFavoritePreset },
					set: { newValue in
						preset.isFavoritePreset = newValue
						presetManager.update(preset)
					}
				))
			}
			
			Section("Identity") {
				PlayerCardImage.wide(preset.loadout.identity.card)
					.cornerRadius(8)
				HStack {
					Text("Title")
					Spacer()
					PlayerTitleLabel(titleID: preset.loadout.identity.title)
						.foregroundStyle(.secondary)
				}
			}
			
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
			
			Section("Weapons") {
				ForEach(Weapon.ID.orderInCollection, id: \.self) { gunID in
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

struct LoadoutShareSheet: View {
	var loadout: UpdatableLoadout
	
	@EnvironmentObject private var imageManager: ImageManager
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
				Text("Vantage")
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
		for asset in targets {
			if let cached = asset.load() {
				loaded[asset] = cached
			} else {
				_ = try? await asset.ensureDownloaded()
				if let downloaded = asset.load() {
					loaded[asset] = downloaded
				}
			}
		}
		preloadedImages = loaded
		
		let renderer = ImageRenderer(
			content: snapshotCardView(images: loaded, useLiveFallback: false)
				.environment(\.assets, assets)
				.environmentObject(imageManager)
				.frame(width: 360)
				.preferredColorScheme(.dark)
		)
		renderer.scale = 3.0
		renderedImage = renderer.uiImage
		isRendering = false
	}
}
