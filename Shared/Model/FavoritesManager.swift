import Foundation
import ValorantAPI

@MainActor
final class FavoritesManager: ObservableObject {
	@Published private(set) var favoritesByAccount: [User.ID: Favorites] = [:]
	@Published private(set) var inventoryByAccount: [User.ID: Inventory] = [:]
	@Published private(set) var inFlightItemIDs: Set<LowercaseUUID> = []
	@Published private(set) var isApplyingPreset = false
	
	private var itemIDsByAccount: [User.ID: Set<LowercaseUUID>] = [:]
	private var inventoryFetchTasks: [User.ID: Task<Void, Never>] = [:]
	
	private func setFavorites(_ favorites: Favorites?, for accountID: User.ID) {
		favoritesByAccount[accountID] = favorites
		itemIDsByAccount[accountID] = favorites?.itemIDs
	}
	
	func cacheInventory(_ inventory: Inventory, for accountID: User.ID) {
		inventoryByAccount[accountID] = inventory
	}
	
	func inventory(for accountID: User.ID?) -> Inventory? {
		guard let accountID else { return nil }
		return inventoryByAccount[accountID]
	}
	
	func refreshInventoryIfNeeded(using client: ValorantClient) async {
		let accountID = client.userID
		guard inventoryByAccount[accountID] == nil else { return }
		if let existing = inventoryFetchTasks[accountID] {
			await existing.value
			return
		}
		let task = Task { [weak self] in
			defer { self?.inventoryFetchTasks.removeValue(forKey: accountID) }
			if let loaded = try? await client.getInventory() {
				self?.inventoryByAccount[accountID] = loaded
			}
		}
		inventoryFetchTasks[accountID] = task
		await task.value
	}
	
	func favorites(for accountID: User.ID?) -> Favorites? {
		guard let accountID else { return nil }
		return favoritesByAccount[accountID]
	}
	
	func itemIDs(for accountID: User.ID?) -> Set<LowercaseUUID> {
		guard let accountID else { return [] }
		return itemIDsByAccount[accountID] ?? []
	}
	
	func isFavorited(_ itemID: LowercaseUUID, for accountID: User.ID?) -> Bool {
		guard let accountID else { return false }
		return itemIDsByAccount[accountID]?.contains(itemID) ?? false
	}
	
	func isChromaFavorited(_ chromaID: Weapon.Skin.Chroma.ID, for accountID: User.ID?) -> Bool {
		isFavorited(chromaID.rawID, for: accountID)
	}
	
	func isSkinFavorited(_ skin: WeaponSkin, for accountID: User.ID?) -> Bool {
		guard let accountID, let ids = itemIDsByAccount[accountID] else { return false }
		if skin.chromas.contains(where: { ids.contains($0.id.rawID) }) { return true }
		if ids.contains(skin.id.rawID) { return true }
		return skin.levels.contains { ids.contains($0.id.rawID) }
	}
	
	func isLoading(_ itemID: LowercaseUUID) -> Bool {
		inFlightItemIDs.contains(itemID)
	}
	
	func isLoading(skin: WeaponSkin) -> Bool {
		if inFlightItemIDs.contains(skin.id.rawID) { return true }
		if skin.chromas.contains(where: { inFlightItemIDs.contains($0.id.rawID) }) { return true }
		return skin.levels.contains { inFlightItemIDs.contains($0.id.rawID) }
	}
	
	func refresh(using client: ValorantClient) async {
		if let loaded = try? await client.getFavorites() {
			setFavorites(loaded, for: client.userID)
		}
	}
	
	func refreshIfNeeded(using client: ValorantClient) async {
		if favoritesByAccount[client.userID] == nil {
			await refresh(using: client)
		}
	}
	
	func toggleFavorite(itemID: LowercaseUUID, using client: ValorantClient) async throws {
		try await toggleFavorite(
			primaryID: itemID,
			matchIDs: [itemID],
			using: client
		)
	}
	
	func toggleSkinFavorite(_ skin: WeaponSkin, chroma: WeaponSkin.Chroma? = nil, using client: ValorantClient) async throws {
		// Riot's /favorites/v1 endpoint only accepts skin chroma IDs for weapon skins.
		let primaryID: LowercaseUUID
		let matchIDs: [LowercaseUUID]
		if let chroma {
			primaryID = chroma.id.rawID
			matchIDs = [primaryID]
		} else {
			primaryID = skin.chromas.first?.id.rawID ?? skin.levels.first?.id.rawID ?? skin.id.rawID
			var seen = Set<LowercaseUUID>()
			matchIDs = ([primaryID] + skin.chromas.map(\.id.rawID) + skin.levels.map(\.id.rawID) + [skin.id.rawID]).filter {
				seen.insert($0).inserted
			}
		}
		
		try await toggleFavorite(
			primaryID: primaryID,
			matchIDs: matchIDs,
			using: client
		)
	}
	
	private func toggleFavorite(
		primaryID: LowercaseUUID,
		matchIDs: [LowercaseUUID],
		using client: ValorantClient
	) async throws {
		guard !inFlightItemIDs.contains(primaryID) else { return }
		inFlightItemIDs.insert(primaryID)
		defer { inFlightItemIDs.remove(primaryID) }
		
		let accountID = client.userID
		let previous = favoritesByAccount[accountID]
		let matchSet = Set(matchIDs)
		let matchKeySet = Set(matchIDs.map(\.description))
		
		var matchedEntries: [(key: String, entry: Favorites.FavoriteEntry)] = []
		if let current = previous {
			var seenKeys = Set<String>()
			for candidate in matchIDs {
				let key = candidate.description
				if let entry = current.favoritedContent[key], seenKeys.insert(key).inserted {
					matchedEntries.append((key, entry))
				}
				for pair in current.favoritedContent where pair.value.itemID == candidate && seenKeys.insert(pair.key).inserted {
					matchedEntries.append((pair.key, pair.value))
				}
			}
		}
		
		let matchedKeySet = Set(matchedEntries.map(\.key))
		let isRemoving = !matchedEntries.isEmpty
		
		// Optimistic UI update
		var optimistic = previous ?? Favorites(subject: accountID)
		if isRemoving {
			optimistic.favoritedContent = optimistic.favoritedContent.filter { key, entry in
				!matchedKeySet.contains(key) && !matchKeySet.contains(key) && !matchSet.contains(entry.itemID)
			}
		} else {
			optimistic.favoritedContent[primaryID.description] = Favorites.FavoriteEntry(
				id: primaryID,
				itemID: primaryID
			)
		}
		setFavorites(optimistic, for: accountID)
		
		do {
			let updated: Favorites
			if isRemoving {
				var latest: Favorites?
				for (_, matchedEntry) in matchedEntries {
					do {
						latest = try await client.removeFavorite(
							itemID: matchedEntry.itemID,
							favoriteID: matchedEntry.id
						)
					} catch where latest != nil && Self.isIgnorableFavoriteMutationError(error) {
						continue
					}
				}
				if let latest {
					updated = latest
				} else {
					updated = try await client.getFavorites()
				}
			} else {
				updated = try await client.addFavorite(primaryID)
			}
			setFavorites(updated, for: accountID)
		} catch {
			if isRemoving {
				var rolledBack = favoritesByAccount[accountID] ?? Favorites(subject: accountID)
				if let previous {
					for (key, entry) in previous.favoritedContent where matchedKeySet.contains(key) || matchKeySet.contains(key) || matchSet.contains(entry.itemID) {
						rolledBack.favoritedContent[key] = entry
					}
				}
				setFavorites(rolledBack, for: accountID)
			} else if var rolledBack = favoritesByAccount[accountID] {
				rolledBack.favoritedContent.removeValue(forKey: primaryID.description)
				if let previous {
					setFavorites(previous.favoritedContent.isEmpty && rolledBack.favoritedContent.isEmpty ? previous : rolledBack, for: accountID)
				} else {
					setFavorites(rolledBack.favoritedContent.isEmpty ? nil : rolledBack, for: accountID)
				}
			} else {
				setFavorites(previous, for: accountID)
			}
			throw error
		}
	}
	
	private static func isIgnorableFavoriteMutationError(_ error: Error) -> Bool {
		switch error {
		case APIError.resourceNotFound:
			return true
		case APIError.badResponseCode(let code, _, _):
			return code == 400 || code == 404
		default:
			return false
		}
	}
	
	func applyFavoritesPreset(
		itemIDs targetList: [LowercaseUUID],
		using client: ValorantClient,
		progress: ((Int, Int) -> Void)? = nil
	) async throws {
		guard !isApplyingPreset else { return }
		isApplyingPreset = true
		defer { isApplyingPreset = false }
		
		let current = try await client.getFavorites()
		var seen = Set<LowercaseUUID>()
		let dedupedTarget = targetList.filter { seen.insert($0).inserted }
		let targetSet = Set(dedupedTarget)
		
		let currentEntries = Array(current.favoritedContent.values)
		let currentIDs = Set(currentEntries.map(\.itemID))
		let toRemove = currentEntries.filter { !targetSet.contains($0.itemID) }
		let toAdd = dedupedTarget.filter { !currentIDs.contains($0) }
		let total = toRemove.count + toAdd.count
		
		setFavorites(current, for: client.userID)
		guard total > 0 else { return }
		
		var completed = 0
		var latestFavorites: Favorites?
		progress?(0, total)
		
		do {
			for entry in toRemove {
				try Task.checkCancellation()
				do {
					latestFavorites = try await client.removeFavorite(
						itemID: entry.itemID,
						favoriteID: entry.id
					)
				} catch where Self.isIgnorableFavoriteMutationError(error) {
					// Ignore stale/missing items on the server so remaining mutations complete.
				}
				completed += 1
				progress?(completed, total)
			}
			
			for id in toAdd {
				try Task.checkCancellation()
				do {
					latestFavorites = try await client.addFavorite(id)
				} catch where Self.isIgnorableFavoriteMutationError(error) {
					// Ignore unowned items if applying across accounts.
				}
				completed += 1
				progress?(completed, total)
			}
		} catch {
			if let latestFavorites {
				setFavorites(latestFavorites, for: client.userID)
			}
			throw error
		}
		
		if let latestFavorites {
			setFavorites(latestFavorites, for: client.userID)
		} else if let finalFavs = try? await client.getFavorites() {
			setFavorites(finalFavs, for: client.userID)
		}
	}
}
