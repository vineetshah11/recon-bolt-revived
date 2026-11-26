import Foundation
import ValorantAPI

@MainActor
final class FavoritesManager: ObservableObject {
	@Published private(set) var favoritesByAccount: [User.ID: Favorites] = [:]
	@Published private(set) var inFlightItemIDs: Set<LowercaseUUID> = []
	@Published private(set) var isApplyingPreset = false
	
	private var itemIDsByAccount: [User.ID: Set<LowercaseUUID>] = [:]
	
	private func setFavorites(_ favorites: Favorites?, for accountID: User.ID) {
		favoritesByAccount[accountID] = favorites
		itemIDsByAccount[accountID] = favorites?.itemIDs
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
	
	func isSkinFavorited(_ skin: WeaponSkin, for accountID: User.ID?) -> Bool {
		guard let accountID, let ids = itemIDsByAccount[accountID] else { return false }
		if ids.contains(skin.id.rawID) { return true }
		return skin.levels.contains { ids.contains($0.id.rawID) }
	}
	
	func isLoading(_ itemID: LowercaseUUID) -> Bool {
		inFlightItemIDs.contains(itemID)
	}
	
	func isLoading(skin: WeaponSkin) -> Bool {
		if inFlightItemIDs.contains(skin.id.rawID) { return true }
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
			fallbackIDs: [],
			using: client
		)
	}
	
	func toggleSkinFavorite(_ skin: WeaponSkin, using client: ValorantClient) async throws {
		let levelIDs = skin.levels.map(\.id.rawID)
		try await toggleFavorite(
			primaryID: skin.id.rawID,
			fallbackIDs: levelIDs,
			using: client
		)
	}
	
	private func toggleFavorite(
		primaryID: LowercaseUUID,
		fallbackIDs: [LowercaseUUID],
		using client: ValorantClient
	) async throws {
		guard !inFlightItemIDs.contains(primaryID) else { return }
		inFlightItemIDs.insert(primaryID)
		defer { inFlightItemIDs.remove(primaryID) }
		
		let accountID = client.userID
		let previous = favoritesByAccount[accountID]
		let candidateIDs = [primaryID] + fallbackIDs
		let candidateSet = Set(candidateIDs)
		let candidateKeySet = Set(candidateIDs.map(\.description))
		
		var matchedEntry: Favorites.FavoriteEntry?
		var matchedKey: String?
		if let current = previous {
			for candidate in candidateIDs {
				if let entry = current.favoritedContent[candidate.description] {
					matchedEntry = entry
					matchedKey = candidate.description
					break
				}
				if let pair = current.favoritedContent.first(where: { $0.value.itemID == candidate }) {
					matchedEntry = pair.value
					matchedKey = pair.key
					break
				}
			}
		}
		
		let isRemoving = matchedEntry != nil
		
		// Optimistic UI update
		var optimistic = previous ?? Favorites(subject: accountID)
		if isRemoving {
			optimistic.favoritedContent = optimistic.favoritedContent.filter { key, entry in
				key != matchedKey && !candidateKeySet.contains(key) && !candidateSet.contains(entry.itemID)
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
			if isRemoving, let matchedEntry {
				updated = try await client.removeFavorite(
					itemID: matchedEntry.itemID,
					favoriteID: matchedEntry.id
				)
			} else {
				updated = try await addWithFallbacks(
					primaryID: primaryID,
					fallbackIDs: fallbackIDs,
					using: client
				)
			}
			setFavorites(updated, for: accountID)
		} catch {
			if isRemoving {
				var rolledBack = favoritesByAccount[accountID] ?? Favorites(subject: accountID)
				if let previous {
					for (key, entry) in previous.favoritedContent where key == matchedKey || candidateKeySet.contains(key) || candidateSet.contains(entry.itemID) {
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
	
	private func addWithFallbacks(
		primaryID: LowercaseUUID,
		fallbackIDs: [LowercaseUUID],
		using client: ValorantClient
	) async throws -> Favorites {
		do {
			return try await client.addFavorite(primaryID)
		} catch where Self.isIgnorableFavoriteMutationError(error) && !fallbackIDs.isEmpty {
			var lastError: Error = error
			for fallback in fallbackIDs where fallback != primaryID {
				do {
					return try await client.addFavorite(fallback)
				} catch {
					lastError = error
				}
			}
			throw lastError
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
