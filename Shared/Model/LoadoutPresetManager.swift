import Foundation
import ValorantAPI

struct LoadoutPreset: Identifiable, Codable, Equatable {
	var id = UUID()
	var name: String
	var accountID: User.ID?
	var createdAt = Date()
	var updatedAt = Date()
	var isFavoritePreset = false
	var isPinned = false
	var bannerCardID: PlayerCard.ID?
	var bannerImageData: Data?
	var includeCard = true
	var includeTitle = true
	var includeExpressions = true
	var includedWeapons: [Weapon.ID]?
	var loadout: UpdatableLoadout
	
	private enum CodingKeys: String, CodingKey {
		case id
		case name
		case accountID
		case createdAt
		case updatedAt
		case isFavoritePreset
		case isPinned
		case bannerCardID
		case bannerImageData
		case includeCard
		case includeTitle
		case includeExpressions
		case includedWeapons
		case loadout
	}
	
	init(
		id: UUID = UUID(),
		name: String,
		accountID: User.ID? = nil,
		createdAt: Date = Date(),
		updatedAt: Date = Date(),
		isFavoritePreset: Bool = false,
		isPinned: Bool = false,
		bannerCardID: PlayerCard.ID? = nil,
		bannerImageData: Data? = nil,
		includeCard: Bool = true,
		includeTitle: Bool = true,
		includeExpressions: Bool = true,
		includedWeapons: [Weapon.ID]? = nil,
		loadout: UpdatableLoadout
	) {
		self.id = id
		self.name = name
		self.accountID = accountID
		self.createdAt = createdAt
		self.updatedAt = updatedAt
		self.isFavoritePreset = isFavoritePreset
		self.isPinned = isPinned
		self.bannerCardID = bannerCardID
		self.bannerImageData = bannerImageData
		self.includeCard = includeCard
		self.includeTitle = includeTitle
		self.includeExpressions = includeExpressions
		self.includedWeapons = includedWeapons
		self.loadout = loadout
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		name = try container.decode(String.self, forKey: .name)
		accountID = try container.decodeIfPresent(User.ID.self, forKey: .accountID)
		createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
		updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
		isFavoritePreset = try container.decodeIfPresent(Bool.self, forKey: .isFavoritePreset) ?? false
		isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
		bannerCardID = try container.decodeIfPresent(PlayerCard.ID.self, forKey: .bannerCardID)
		bannerImageData = try container.decodeIfPresent(Data.self, forKey: .bannerImageData)
		includeCard = try container.decodeIfPresent(Bool.self, forKey: .includeCard) ?? true
		includeTitle = try container.decodeIfPresent(Bool.self, forKey: .includeTitle) ?? true
		includeExpressions = try container.decodeIfPresent(Bool.self, forKey: .includeExpressions) ?? true
		includedWeapons = try container.decodeIfPresent([Weapon.ID].self, forKey: .includedWeapons)
		loadout = try container.decode(UpdatableLoadout.self, forKey: .loadout)
	}
	
	var activeWeaponIDs: [Weapon.ID] {
		if let includedWeapons {
			return includedWeapons.filter { loadout.guns[$0] != nil }
		}
		return Weapon.ID.orderInCollection.filter { loadout.guns[$0] != nil }
	}
	
	var summaryLine: String {
		var parts: [String] = []
		if includeCard {
			parts.append("Card")
		}
		if includeTitle {
			parts.append("Title")
		}
		let weaponCount = activeWeaponIDs.count
		if weaponCount > 0 {
			parts.append(weaponCount == 1 ? "1 Weapon" : "\(weaponCount) Weapons")
		}
		if includeExpressions {
			parts.append("Expressions")
		}
		return parts.isEmpty ? "Empty Preset" : parts.joined(separator: ", ")
	}
	
	func applying(to current: UpdatableLoadout) -> UpdatableLoadout {
		var next = current
		if includeCard {
			next.identity.card = loadout.identity.card
		}
		if includeTitle {
			next.identity.title = loadout.identity.title
		}
		if includeExpressions {
			next.expressions = loadout.expressions
		}
		if let includedWeapons {
			for weaponID in includedWeapons {
				if let gun = loadout.guns[weaponID] {
					next.guns[weaponID] = gun
				}
			}
		} else {
			next.guns = loadout.guns
		}
		return next
	}
}

struct FavoritesPreset: Identifiable, Codable, Equatable {
	var id = UUID()
	var name: String
	var accountID: User.ID?
	var createdAt = Date()
	var updatedAt = Date()
	var isPinned = false
	var bannerCardID: PlayerCard.ID?
	var bannerImageData: Data?
	var itemIDs: [LowercaseUUID]
	
	private enum CodingKeys: String, CodingKey {
		case id
		case name
		case accountID
		case createdAt
		case updatedAt
		case isPinned
		case bannerCardID
		case bannerImageData
		case itemIDs
	}
	
	init(
		id: UUID = UUID(),
		name: String,
		accountID: User.ID? = nil,
		createdAt: Date = Date(),
		updatedAt: Date = Date(),
		isPinned: Bool = false,
		bannerCardID: PlayerCard.ID? = nil,
		bannerImageData: Data? = nil,
		itemIDs: [LowercaseUUID]
	) {
		self.id = id
		self.name = name
		self.accountID = accountID
		self.createdAt = createdAt
		self.updatedAt = updatedAt
		self.isPinned = isPinned
		self.bannerCardID = bannerCardID
		self.bannerImageData = bannerImageData
		self.itemIDs = itemIDs
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		name = try container.decode(String.self, forKey: .name)
		accountID = try container.decodeIfPresent(User.ID.self, forKey: .accountID)
		createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
		updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
		isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
		bannerCardID = try container.decodeIfPresent(PlayerCard.ID.self, forKey: .bannerCardID)
		bannerImageData = try container.decodeIfPresent(Data.self, forKey: .bannerImageData)
		itemIDs = try container.decodeIfPresent([LowercaseUUID].self, forKey: .itemIDs) ?? []
	}
	
	var subtitleLine: String {
		let count = itemIDs.count
		let countText = count == 1 ? "1 item" : "\(count) items"
		let dateText = updatedAt.formatted(.dateTime.day().month(.abbreviated).year())
		return "\(countText) · \(dateText)"
	}
}

@MainActor
final class LoadoutPresetManager: ObservableObject {
	@Published var presets: [LoadoutPreset] = []
	@Published var favoritesPresets: [FavoritesPreset] = []
	
	private let filename = "LoadoutPresets.v1.json"
	private let favoritesFilename = "FavoritesPresets.v1.json"
	private var hasLoadedFromDisk = false
	private var initialLoadTask: Task<Void, Never>?
	private var pendingRemovedPresetIDs: Set<UUID> = []
	private var pendingRemovedFavPresetIDs: Set<UUID> = []
	private var pendingSavePresetsTask: Task<Void, Never>?
	private var pendingSaveFavsTask: Task<Void, Never>?
	
	init() {
		initialLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			async let loadedPresets = LocalJSONStore.loadAsync([LoadoutPreset].self, from: self.filename)
			async let loadedFavs = LocalJSONStore.loadAsync([FavoritesPreset].self, from: self.favoritesFilename)
			let (diskPresets, diskFavs) = await (loadedPresets ?? [], loadedFavs ?? [])
			self.mergeDiskData(presets: diskPresets, favoritesPresets: diskFavs)
		}
	}
	
	func waitUntilLoaded() async {
		if let initialLoadTask, !hasLoadedFromDisk {
			await initialLoadTask.value
		}
	}
	
	private static func sortPresets(_ list: [LoadoutPreset]) -> [LoadoutPreset] {
		list.sorted { lhs, rhs in
			if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
			return lhs.updatedAt > rhs.updatedAt
		}
	}
	
	private static func sortFavoritesPresets(_ list: [FavoritesPreset]) -> [FavoritesPreset] {
		list.sorted { lhs, rhs in
			if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
			return lhs.updatedAt > rhs.updatedAt
		}
	}
	
	private func mergeDiskData(presets diskPresets: [LoadoutPreset], favoritesPresets diskFavs: [FavoritesPreset]) {
		hasLoadedFromDisk = true
		if presets.isEmpty && pendingRemovedPresetIDs.isEmpty {
			presets = Self.sortPresets(diskPresets)
		} else {
			var working = presets
			var seen = Set(working.map(\.id))
			for item in diskPresets {
				guard !pendingRemovedPresetIDs.contains(item.id), seen.insert(item.id).inserted else { continue }
				working.append(item)
			}
			presets = Self.sortPresets(working)
		}
		if favoritesPresets.isEmpty && pendingRemovedFavPresetIDs.isEmpty {
			favoritesPresets = Self.sortFavoritesPresets(diskFavs)
		} else {
			var working = favoritesPresets
			var seen = Set(working.map(\.id))
			for item in diskFavs {
				guard !pendingRemovedFavPresetIDs.contains(item.id), seen.insert(item.id).inserted else { continue }
				working.append(item)
			}
			favoritesPresets = Self.sortFavoritesPresets(working)
		}
		pendingRemovedPresetIDs.removeAll()
		pendingRemovedFavPresetIDs.removeAll()
	}
	
	func presets(for accountID: User.ID?, favoritesOnly: Bool = false) -> [LoadoutPreset] {
		presets.filter { preset in
			let matchesAccount = preset.accountID == nil || accountID == nil || preset.accountID == accountID
			let matchesFav = !favoritesOnly || preset.isFavoritePreset
			return matchesAccount && matchesFav
		}
	}
	
	func favoritesPresets(for accountID: User.ID?) -> [FavoritesPreset] {
		favoritesPresets.filter { preset in
			preset.accountID == nil || accountID == nil || preset.accountID == accountID
		}
	}
	
	func saveNewPreset(
		name: String,
		loadout: UpdatableLoadout,
		accountID: User.ID?,
		isFavoritePreset: Bool = false,
		isPinned: Bool = false,
		bannerCardID: PlayerCard.ID? = nil,
		bannerImageData: Data? = nil,
		includeCard: Bool = true,
		includeTitle: Bool = true,
		includeExpressions: Bool = true,
		includedWeapons: [Weapon.ID]? = nil
	) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let preset = LoadoutPreset(
			name: trimmed.isEmpty ? "Preset \(presets.count + 1)" : trimmed,
			accountID: accountID,
			isFavoritePreset: isFavoritePreset,
			isPinned: isPinned,
			bannerCardID: bannerCardID,
			bannerImageData: bannerImageData,
			includeCard: includeCard,
			includeTitle: includeTitle,
			includeExpressions: includeExpressions,
			includedWeapons: includedWeapons,
			loadout: loadout
		)
		presets = Self.sortPresets([preset] + presets)
		persist()
	}
	
	func update(_ preset: LoadoutPreset, refreshTimestamp: Bool = true) {
		var updated = preset
		if refreshTimestamp {
			updated.updatedAt = Date()
		}
		if let idx = presets.firstIndex(where: { $0.id == updated.id }) {
			presets[idx] = updated
		} else {
			presets.insert(updated, at: 0)
		}
		presets = Self.sortPresets(presets)
		persist()
	}
	
	func togglePinned(id: UUID) {
		guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
		presets[idx].isPinned.toggle()
		presets = Self.sortPresets(presets)
		persist()
	}
	
	func setBanner(id: UUID, cardID: PlayerCard.ID?, imageData: Data?) {
		guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
		presets[idx].bannerCardID = cardID
		presets[idx].bannerImageData = imageData
		presets[idx].updatedAt = Date()
		presets = Self.sortPresets(presets)
		persist()
	}
	
	func rename(_ preset: LoadoutPreset, to newName: String) {
		let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, var copy = presets.first(where: { $0.id == preset.id }) else { return }
		copy.name = trimmed
		update(copy)
	}
	
	func delete(id: UUID) {
		if !hasLoadedFromDisk {
			pendingRemovedPresetIDs.insert(id)
		}
		let before = presets.count
		presets.removeAll { $0.id == id }
		guard presets.count != before else { return }
		persist()
	}
	
	// MARK: - Favorites Presets CRUD
	
	func saveNewFavoritesPreset(
		name: String,
		itemIDs: [LowercaseUUID],
		accountID: User.ID?,
		isPinned: Bool = false,
		bannerCardID: PlayerCard.ID? = nil,
		bannerImageData: Data? = nil
	) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		var seen = Set<LowercaseUUID>()
		let deduped = itemIDs.filter { seen.insert($0).inserted }
		let preset = FavoritesPreset(
			name: trimmed.isEmpty ? "Favorites \(favoritesPresets.count + 1)" : trimmed,
			accountID: accountID,
			isPinned: isPinned,
			bannerCardID: bannerCardID,
			bannerImageData: bannerImageData,
			itemIDs: deduped
		)
		favoritesPresets = Self.sortFavoritesPresets([preset] + favoritesPresets)
		persistFavorites()
	}
	
	func updateFavoritesPreset(_ preset: FavoritesPreset, refreshTimestamp: Bool = true) {
		var updated = preset
		if refreshTimestamp {
			updated.updatedAt = Date()
		}
		if let idx = favoritesPresets.firstIndex(where: { $0.id == updated.id }) {
			favoritesPresets[idx] = updated
		} else {
			favoritesPresets.insert(updated, at: 0)
		}
		favoritesPresets = Self.sortFavoritesPresets(favoritesPresets)
		persistFavorites()
	}
	
	func toggleFavoritesPresetPinned(id: UUID) {
		guard let idx = favoritesPresets.firstIndex(where: { $0.id == id }) else { return }
		favoritesPresets[idx].isPinned.toggle()
		favoritesPresets = Self.sortFavoritesPresets(favoritesPresets)
		persistFavorites()
	}
	
	func setFavoritesPresetBanner(id: UUID, cardID: PlayerCard.ID?, imageData: Data?) {
		guard let idx = favoritesPresets.firstIndex(where: { $0.id == id }) else { return }
		favoritesPresets[idx].bannerCardID = cardID
		favoritesPresets[idx].bannerImageData = imageData
		favoritesPresets[idx].updatedAt = Date()
		favoritesPresets = Self.sortFavoritesPresets(favoritesPresets)
		persistFavorites()
	}
	
	func renameFavoritesPreset(_ preset: FavoritesPreset, to newName: String) {
		let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, var copy = favoritesPresets.first(where: { $0.id == preset.id }) else { return }
		copy.name = trimmed
		updateFavoritesPreset(copy)
	}
	
	func deleteFavoritesPreset(id: UUID) {
		if !hasLoadedFromDisk {
			pendingRemovedFavPresetIDs.insert(id)
		}
		let before = favoritesPresets.count
		favoritesPresets.removeAll { $0.id == id }
		guard favoritesPresets.count != before else { return }
		persistFavorites()
	}
	
	func deleteAll() {
		presets = []
		favoritesPresets = []
		persist()
		persistFavorites()
	}
	
	func exportPresets(for playerIDs: Set<User.ID>?) -> [LoadoutPreset] {
		guard let playerIDs else { return presets }
		return presets.filter { preset in
			guard let accountID = preset.accountID else { return !playerIDs.isEmpty }
			return playerIDs.contains(accountID)
		}
	}
	
	@discardableResult
	func importPresets(_ incoming: [LoadoutPreset], replaceAll: Bool) async -> Int {
		await waitUntilLoaded()
		pendingSavePresetsTask?.cancel()
		var workingByID = replaceAll
			? [:]
			: Dictionary(presets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		var changedCount = 0
		
		for preset in incoming {
			if let existing = workingByID[preset.id] {
				if preset.updatedAt > existing.updatedAt {
					workingByID[preset.id] = preset
					changedCount += 1
				}
			} else {
				workingByID[preset.id] = preset
				changedCount += 1
			}
		}
		
		let working = Self.sortPresets(Array(workingByID.values))
		presets = working
		await LocalJSONStore.saveAndWait(presets, to: filename)
		return replaceAll ? working.count : changedCount
	}
	
	func exportFavoritesPresets(for playerIDs: Set<User.ID>?) -> [FavoritesPreset] {
		guard let playerIDs else { return favoritesPresets }
		return favoritesPresets.filter { preset in
			guard let accountID = preset.accountID else { return !playerIDs.isEmpty }
			return playerIDs.contains(accountID)
		}
	}
	
	@discardableResult
	func importFavoritesPresets(_ incoming: [FavoritesPreset], replaceAll: Bool) async -> Int {
		await waitUntilLoaded()
		pendingSaveFavsTask?.cancel()
		var workingByID = replaceAll
			? [:]
			: Dictionary(favoritesPresets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		var changedCount = 0
		
		for preset in incoming {
			if let existing = workingByID[preset.id] {
				if preset.updatedAt > existing.updatedAt {
					workingByID[preset.id] = preset
					changedCount += 1
				}
			} else {
				workingByID[preset.id] = preset
				changedCount += 1
			}
		}
		
		let working = Self.sortFavoritesPresets(Array(workingByID.values))
		favoritesPresets = working
		await LocalJSONStore.saveAndWait(favoritesPresets, to: favoritesFilename)
		return replaceAll ? working.count : changedCount
	}
	
	private func persist() {
		if hasLoadedFromDisk {
			LocalJSONStore.save(presets, to: filename)
		} else {
			pendingSavePresetsTask?.cancel()
			pendingSavePresetsTask = Task { @MainActor [weak self] in
				await self?.waitUntilLoaded()
				guard let self, !Task.isCancelled else { return }
				LocalJSONStore.save(self.presets, to: self.filename)
			}
		}
	}
	
	private func persistFavorites() {
		if hasLoadedFromDisk {
			LocalJSONStore.save(favoritesPresets, to: favoritesFilename)
		} else {
			pendingSaveFavsTask?.cancel()
			pendingSaveFavsTask = Task { @MainActor [weak self] in
				await self?.waitUntilLoaded()
				guard let self, !Task.isCancelled else { return }
				LocalJSONStore.save(self.favoritesPresets, to: self.favoritesFilename)
			}
		}
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
		let favCards = favIDs.map { favs in inventory.cards.filter { favs.contains($0.rawID) } } ?? []
		if let card = favCards.randomElement() ?? inventory.cards.randomElement() {
			next.identity.card = card
		}
		
		let favTitles = favIDs.map { favs in inventory.titles.filter { favs.contains($0.rawID) } } ?? []
		if let title = favTitles.randomElement() ?? inventory.titles.randomElement() {
			next.identity.title = title
		}
		
		// Weapons (single pass per weapon collecting both favorite-owned and all-owned candidates)
		for (weaponID, existingGun) in current.guns {
			guard let weapon = assets.weapons[weaponID] else { continue }
			var updatedGun = existingGun
			
			typealias SkinCandidate = (skin: WeaponSkin, ownedLevels: [WeaponSkin.Level], ownedChromas: [WeaponSkin.Chroma])
			var favOwned: [SkinCandidate] = []
			var allOwned: [SkinCandidate] = []
			
			for skin in weapon.skins {
				let ownedLevels = skin.levels.filter {
					inventory.owns($0.id) || skin.id == weapon.defaultSkinID
				}
				guard !ownedLevels.isEmpty else { continue }
				let ownedChromas = skin.chromas.filter {
					inventory.owns($0.id) || $0.id == skin.chromas.first?.id
				}
				let candidate: SkinCandidate = (skin, ownedLevels, ownedChromas)
				allOwned.append(candidate)
				if favIDs == nil
					|| favIDs!.contains(skin.id.rawID)
					|| skin.levels.contains(where: { favIDs!.contains($0.id.rawID) }) {
					favOwned.append(candidate)
				}
			}
			
			if let picked = (favOwned.isEmpty ? allOwned : favOwned).randomElement() {
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
		
		// Expressions (Sprays + Flex) — sample 4 without shuffling the entire pool
		var availableExpressions: [Loadout.Expression] = []
		if let favIDs {
			let favSprays = inventory.sprays.filter { favIDs.contains($0.rawID) }
			if favSprays.isEmpty {
				availableExpressions.append(contentsOf: inventory.sprays.map { .spray($0) })
			} else {
				availableExpressions.append(contentsOf: favSprays.map { .spray($0) })
			}
			let favTotems = inventory.totems.filter { favIDs.contains($0.rawID) }
			if favTotems.isEmpty {
				availableExpressions.append(contentsOf: inventory.totems.map { .totem($0) })
			} else {
				availableExpressions.append(contentsOf: favTotems.map { .totem($0) })
			}
		} else {
			availableExpressions.reserveCapacity(inventory.sprays.count + inventory.totems.count)
			availableExpressions.append(contentsOf: inventory.sprays.map { .spray($0) })
			availableExpressions.append(contentsOf: inventory.totems.map { .totem($0) })
		}
		
		if !availableExpressions.isEmpty {
			let total = availableExpressions.count
			if total <= 4 {
				let shuffled = availableExpressions.shuffled()
				for index in 0..<4 {
					next.expressions[index] = shuffled[index % total]
				}
			} else {
				var pickedIndices = Set<Int>()
				for index in 0..<4 {
					var candidate = Int.random(in: 0..<total)
					while !pickedIndices.insert(candidate).inserted {
						candidate = Int.random(in: 0..<total)
					}
					next.expressions[index] = availableExpressions[candidate]
				}
			}
		}
		
		return next
	}
}
