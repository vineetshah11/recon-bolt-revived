import Foundation
import ValorantAPI

enum FavoriteSyncError: Error, LocalizedError {
	case invalidURL
	case httpError(Int, String?)
	case unauthenticated
	
	var errorDescription: String? {
		switch self {
		case .invalidURL:
			return "Invalid Riot Favorites URL."
		case .httpError(let code, let message):
			if let message, !message.isEmpty {
				return "Could not update in-game favorites (\(code)): \(message)"
			}
			return "Could not update in-game favorites (HTTP \(code))."
		case .unauthenticated:
			return "Sign in to sync favorites with VALORANT."
		}
	}
}

private enum RiotFavoritesClient {
	private static let urlSession: URLSession = {
		let config = URLSessionConfiguration.ephemeral
		config.httpAdditionalHeaders = ["User-Agent": ""]
		config.timeoutIntervalForRequest = 20
		config.timeoutIntervalForResource = 30
		return URLSession(configuration: config)
	}()
	
	private struct PlatformPayload: Encodable {
		let platformType = "PC"
		let platformOS = "Windows"
		let platformOSVersion = "10.0.19042.1.256.64bit"
		let platformChipset = "Unknown"
	}
	
	private static let encodedPlatformInfo: String = {
		(try? JSONEncoder().encode(PlatformPayload()).base64EncodedString()) ?? ""
	}()
	
	private static let fallbackClientVersion = "release-13.10-shipping-18-5893614"
	
	private struct AddFavoriteBody: Encodable {
		let itemID: String
		
		private enum CodingKeys: String, CodingKey {
			case itemID = "ItemID"
		}
	}
	
	private struct RiotErrorBody: Decodable {
		let message: String?
		let errorCode: String?
	}
	
	static func addFavorite(itemID: LowercaseUUID, using client: ValorantClient) async throws -> Favorites {
		let body = try JSONEncoder().encode(AddFavoriteBody(itemID: itemID.description))
		return try await sendFavoriteMutation(
			method: "POST",
			path: "/favorites/v1/players/\(client.userID)/favorites",
			body: body,
			using: client
		)
	}
	
	static func removeFavorite(
		itemID: LowercaseUUID,
		favoriteID: LowercaseUUID? = nil,
		using client: ValorantClient
	) async throws -> Favorites {
		var candidates: [String] = [
			itemID.description.replacingOccurrences(of: "-", with: ""),
		]
		if let favoriteID {
			let favNoDash = favoriteID.description.replacingOccurrences(of: "-", with: "")
			if !candidates.contains(favNoDash) {
				candidates.append(favNoDash)
			}
			if !candidates.contains(favoriteID.description) {
				candidates.append(favoriteID.description)
			}
		}
		if !candidates.contains(itemID.description) {
			candidates.append(itemID.description)
		}
		
		var lastError: Error?
		for candidate in candidates {
			do {
				return try await sendFavoriteMutation(
					method: "DELETE",
					path: "/favorites/v1/players/\(client.userID)/favorites/\(candidate)",
					body: nil,
					using: client
				)
			} catch let FavoriteSyncError.httpError(code, _) where code == 404 {
				lastError = FavoriteSyncError.httpError(code, nil)
				continue
			} catch {
				throw error
			}
		}
		throw lastError ?? FavoriteSyncError.httpError(404, nil)
	}
	
	private static func sendFavoriteMutation(
		method: String,
		path: String,
		body: Data?,
		using client: ValorantClient
	) async throws -> Favorites {
		let baseURL = URL(string: "https://pd.\(client.location.shard).a.pvp.net")
		guard let url = baseURL?.appendingPathComponent(path) else {
			throw FavoriteSyncError.invalidURL
		}
		
		for attempt in 0..<2 {
			let accessToken = try await client.getAccessToken()
			let entitlements = await client.getEntitlementsToken()
			let version = (client.clientVersion?.isEmpty == false)
				? client.clientVersion!
				: fallbackClientVersion
			
			var request = URLRequest(url: url)
			request.httpMethod = method
			request.httpBody = body
			request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
			request.setValue(entitlements, forHTTPHeaderField: "X-Riot-Entitlements-JWT")
			request.setValue(version, forHTTPHeaderField: "X-Riot-ClientVersion")
			request.setValue(encodedPlatformInfo, forHTTPHeaderField: "X-Riot-ClientPlatform")
			request.setValue("application/json", forHTTPHeaderField: "Accept")
			if body != nil {
				request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			}
			
			let (data, response) = try await urlSession.data(for: request)
			let code = (response as? HTTPURLResponse)?.statusCode ?? 0
			
			if code == 401, attempt == 0 {
				// Trigger ValorantClient's internal token refresh via a lightweight read, then retry once.
				_ = try? await client.getFavorites()
				continue
			}
			
			guard (200..<300).contains(code) else {
				let decodedErr = try? JSONDecoder().decode(RiotErrorBody.self, from: data)
				throw FavoriteSyncError.httpError(code, decodedErr?.message ?? decodedErr?.errorCode)
			}
			
			if !data.isEmpty,
			   let updated = try? ValorantClient.responseDecoder.decode(Favorites.self, from: data) {
				return updated
			}
			return try await client.getFavorites()
		}
		
		throw FavoriteSyncError.httpError(401, nil)
	}
}

@MainActor
final class FavoritesManager: ObservableObject {
	@Published private(set) var favoritesByAccount: [User.ID: Favorites] = [:]
	@Published private(set) var inFlightItemIDs: Set<LowercaseUUID> = []
	@Published private(set) var isApplyingPreset = false
	
	func favorites(for accountID: User.ID?) -> Favorites? {
		guard let accountID else { return nil }
		return favoritesByAccount[accountID]
	}
	
	func itemIDs(for accountID: User.ID?) -> Set<LowercaseUUID> {
		favorites(for: accountID)?.itemIDs ?? []
	}
	
	func isFavorited(_ itemID: LowercaseUUID, for accountID: User.ID?) -> Bool {
		favorites(for: accountID)?.contains(itemID) ?? false
	}
	
	func isSkinFavorited(_ skin: WeaponSkin, for accountID: User.ID?) -> Bool {
		guard let favs = favorites(for: accountID) else { return false }
		if favs.contains(skin.id.rawID) { return true }
		return skin.levels.contains { favs.contains($0.id.rawID) }
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
			favoritesByAccount[client.userID] = loaded
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
			if let matchedKey {
				optimistic.favoritedContent.removeValue(forKey: matchedKey)
			}
			for candidate in candidateIDs {
				optimistic.favoritedContent = optimistic.favoritedContent.filter {
					$0.value.itemID != candidate && $0.key != candidate.description
				}
			}
		} else {
			optimistic.favoritedContent[primaryID.description] = Favorites.FavoriteEntry(
				id: primaryID,
				itemID: primaryID
			)
		}
		favoritesByAccount[accountID] = optimistic
		
		do {
			let updated: Favorites
			if isRemoving, let matchedEntry {
				updated = try await RiotFavoritesClient.removeFavorite(
					itemID: matchedEntry.itemID,
					favoriteID: matchedEntry.id,
					using: client
				)
			} else {
				updated = try await addWithFallbacks(
					primaryID: primaryID,
					fallbackIDs: fallbackIDs,
					using: client
				)
			}
			favoritesByAccount[accountID] = updated
		} catch {
			favoritesByAccount[accountID] = previous
			throw error
		}
	}
	
	private func addWithFallbacks(
		primaryID: LowercaseUUID,
		fallbackIDs: [LowercaseUUID],
		using client: ValorantClient
	) async throws -> Favorites {
		do {
			return try await RiotFavoritesClient.addFavorite(itemID: primaryID, using: client)
		} catch let FavoriteSyncError.httpError(code, _) where (code == 400 || code == 404) && !fallbackIDs.isEmpty {
			var lastError: Error?
			for fallback in fallbackIDs where fallback != primaryID {
				do {
					return try await RiotFavoritesClient.addFavorite(itemID: fallback, using: client)
				} catch {
					lastError = error
				}
			}
			throw lastError ?? FavoriteSyncError.httpError(code, nil)
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
		
		favoritesByAccount[client.userID] = current
		guard total > 0 else { return }
		
		var completed = 0
		progress?(0, total)
		
		for entry in toRemove {
			do {
				let updated = try await RiotFavoritesClient.removeFavorite(
					itemID: entry.itemID,
					favoriteID: entry.id,
					using: client
				)
				favoritesByAccount[client.userID] = updated
			} catch let FavoriteSyncError.httpError(code, _) where code == 400 || code == 404 {
				// Ignore stale/missing items on the server so remaining mutations complete.
			}
			completed += 1
			progress?(completed, total)
		}
		
		for id in toAdd {
			do {
				let updated = try await RiotFavoritesClient.addFavorite(itemID: id, using: client)
				favoritesByAccount[client.userID] = updated
			} catch let FavoriteSyncError.httpError(code, _) where code == 400 || code == 404 {
				// Ignore unowned items if applying across accounts.
			}
			completed += 1
			progress?(completed, total)
		}
		
		if let finalFavs = try? await client.getFavorites() {
			favoritesByAccount[client.userID] = finalFavs
		}
	}
}
