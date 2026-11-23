import Foundation
import ValorantAPI

struct LoadoutPreset: Identifiable, Codable, Equatable {
	var id = UUID()
	var name: String
	var accountID: User.ID?
	var createdAt = Date()
	var updatedAt = Date()
	var isFavoritePreset = false
	var loadout: UpdatableLoadout
}

@MainActor
final class LoadoutPresetManager: ObservableObject {
	@Published var presets: [LoadoutPreset] = []
	
	private let filename = "LoadoutPresets.v1.json"
	
	init() {
		presets = LocalJSONStore.load([LoadoutPreset].self, from: filename) ?? []
	}
	
	func presets(for accountID: User.ID?, favoritesOnly: Bool = false) -> [LoadoutPreset] {
		presets.filter { preset in
			let matchesAccount = preset.accountID == nil || accountID == nil || preset.accountID == accountID
			let matchesFav = !favoritesOnly || preset.isFavoritePreset
			return matchesAccount && matchesFav
		}
		.sorted { $0.updatedAt > $1.updatedAt }
	}
	
	func saveNewPreset(
		name: String,
		loadout: UpdatableLoadout,
		accountID: User.ID?,
		isFavoritePreset: Bool = false
	) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let preset = LoadoutPreset(
			name: trimmed.isEmpty ? "Preset \(presets.count + 1)" : trimmed,
			accountID: accountID,
			isFavoritePreset: isFavoritePreset,
			loadout: loadout
		)
		presets.insert(preset, at: 0)
		persist()
	}
	
	func update(_ preset: LoadoutPreset) {
		var updated = preset
		updated.updatedAt = Date()
		if let idx = presets.firstIndex(where: { $0.id == updated.id }) {
			presets[idx] = updated
		} else {
			presets.insert(updated, at: 0)
		}
		persist()
	}
	
	func rename(_ preset: LoadoutPreset, to newName: String) {
		let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, var copy = presets.first(where: { $0.id == preset.id }) else { return }
		copy.name = trimmed
		update(copy)
	}
	
	func delete(id: UUID) {
		presets.removeAll { $0.id == id }
		persist()
	}
	
	func deleteAll() {
		presets = []
		persist()
	}
	
	private func persist() {
		LocalJSONStore.save(presets, to: filename)
	}
	
	/// Builds a randomized loadout from the player's inventory, optionally restricted to items favorited in VALORANT.
	static func randomizedLoadout(
		from current: UpdatableLoadout,
		inventory: Inventory,
		assets: AssetCollection,
		favorites: Favorites? = nil
	) -> UpdatableLoadout {
		var next = current
		let favIDs = favorites?.itemIDs
		
		// Card & Title
		let cards = Array(inventory.cards).filter { favIDs == nil || favIDs!.contains($0.rawID) }
		if let card = cards.randomElement() ?? inventory.cards.randomElement() {
			next.identity.card = card
		}
		
		let titles = Array(inventory.titles).filter { favIDs == nil || favIDs!.contains($0.rawID) }
		if let title = titles.randomElement() {
			next.identity.title = title
		}
		
		// Weapons
		for (weaponID, existingGun) in current.guns {
			guard let weapon = assets.weapons[weaponID] else { continue }
			var updatedGun = existingGun
			
			// Find owned skin levels belonging to this weapon
			let ownedSkins: [(skin: WeaponSkin, ownedLevels: [WeaponSkin.Level], ownedChromas: [WeaponSkin.Chroma])] = weapon.skins.compactMap { skin in
				let isFavSkin = favIDs == nil || favIDs!.contains(skin.id.rawID)
				let ownedLevels = skin.levels.filter {
					inventory.owns($0.id) || skin.id == weapon.defaultSkinID
				}
				guard isFavSkin, !ownedLevels.isEmpty else { return nil }
				let ownedChromas = skin.chromas.filter {
					inventory.owns($0.id) || $0.id == skin.chromas.first?.id
				}
				return (skin, ownedLevels, ownedChromas)
			}
			
			if let picked = ownedSkins.randomElement() ?? weapon.skins.compactMap({ skin -> (WeaponSkin, [WeaponSkin.Level], [WeaponSkin.Chroma])? in
				let ownedLevels = skin.levels.filter { inventory.owns($0.id) || skin.id == weapon.defaultSkinID }
				guard !ownedLevels.isEmpty else { return nil }
				let ownedChromas = skin.chromas.filter { inventory.owns($0.id) || $0.id == skin.chromas.first?.id }
				return (skin, ownedLevels, ownedChromas)
			}).randomElement() {
				let bestLevel = picked.ownedLevels.last ?? picked.ownedLevels.first!
				let pickedChroma = picked.ownedChromas.randomElement() ?? picked.skin.chromas.first
				updatedGun.skin = Loadout.Gun.Skin(
					skin: picked.skin.id,
					level: bestLevel.id,
					chroma: pickedChroma?.id
				)
			}
			next.guns[weaponID] = updatedGun
		}
		
		// Expressions (Sprays + Flex)
		var availableExpressions: [Loadout.Expression] = []
		let sprayPool = Array(inventory.sprays).filter { favIDs == nil || favIDs!.contains($0.rawID) }
		availableExpressions += (sprayPool.isEmpty ? Array(inventory.sprays) : sprayPool).map { .spray($0) }
		let totemPool = Array(inventory.totems).filter { favIDs == nil || favIDs!.contains($0.rawID) }
		availableExpressions += (totemPool.isEmpty ? Array(inventory.totems) : totemPool).map { .totem($0) }
		
		if !availableExpressions.isEmpty {
			let shuffled = availableExpressions.shuffled()
			for index in 0..<4 {
				next.expressions[index] = shuffled[index % shuffled.count]
			}
		}
		
		return next
	}
}
