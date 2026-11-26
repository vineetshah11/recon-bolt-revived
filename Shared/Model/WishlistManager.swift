import Foundation
import ValorantAPI

enum WishlistItemKind: String, Codable, CaseIterable, Hashable, Sendable {
	case skin
	case buddy
	case spray
	case card
	case title
	case flex
	
	var displayName: String {
		switch self {
		case .skin: return "Skins"
		case .buddy: return "Buddies"
		case .spray: return "Sprays"
		case .card: return "Cards"
		case .title: return "Titles"
		case .flex: return "Flex"
		}
	}
}

struct WishlistEntry: Identifiable, Codable, Equatable {
	var id: LowercaseUUID { itemID }
	var kind: WishlistItemKind
	var itemID: LowercaseUUID
	var addedAt = Date()
	
	var skinID: WeaponSkin.ID {
		WeaponSkin.ID(rawID: itemID)
	}
	
	init(kind: WishlistItemKind, itemID: LowercaseUUID, addedAt: Date = Date()) {
		self.kind = kind
		self.itemID = itemID
		self.addedAt = addedAt
	}
	
	init(skinID: WeaponSkin.ID, addedAt: Date = Date()) {
		self.kind = .skin
		self.itemID = skinID.rawID
		self.addedAt = addedAt
	}
	
	private enum CodingKeys: String, CodingKey {
		case kind
		case itemID
		case skinID
		case addedAt
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.kind = try container.decodeIfPresent(WishlistItemKind.self, forKey: .kind) ?? .skin
		if let itemID = try container.decodeIfPresent(LowercaseUUID.self, forKey: .itemID) {
			self.itemID = itemID
		} else {
			let legacySkinID = try container.decode(WeaponSkin.ID.self, forKey: .skinID)
			self.itemID = legacySkinID.rawID
		}
		self.addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
	}
	
	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(kind, forKey: .kind)
		try container.encode(itemID, forKey: .itemID)
		try container.encode(addedAt, forKey: .addedAt)
	}
}

@MainActor
final class WishlistManager: ObservableObject {
	private struct LookupKey: Hashable {
		var kind: WishlistItemKind
		var itemID: LowercaseUUID
	}
	
	@Published var entries: [WishlistEntry] = []
	
	private let filename = "Wishlist.v1.json"
	private var lookupIndex: Set<LookupKey> = []
	private var cachedSkinIDs: Set<WeaponSkin.ID> = []
	private var hasLoadedFromDisk = false
	private var initialLoadTask: Task<Void, Never>?
	private var pendingRemovedKeys: Set<LookupKey> = []
	private var pendingSaveTask: Task<Void, Never>?
	
	init() {
		initialLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let loaded = await LocalJSONStore.loadAsync([WishlistEntry].self, from: self.filename) ?? []
			self.mergeDiskEntries(loaded)
		}
	}
	
	func waitUntilLoaded() async {
		if let initialLoadTask, !hasLoadedFromDisk {
			await initialLoadTask.value
		}
	}
	
	private func mergeDiskEntries(_ diskEntries: [WishlistEntry]) {
		hasLoadedFromDisk = true
		guard !diskEntries.isEmpty else {
			pendingRemovedKeys.removeAll()
			return
		}
		if entries.isEmpty && pendingRemovedKeys.isEmpty {
			applyEntries(diskEntries)
			return
		}
		var working = entries
		var existingKeys = Set(working.map { LookupKey(kind: $0.kind, itemID: $0.itemID) })
		for diskEntry in diskEntries {
			let key = LookupKey(kind: diskEntry.kind, itemID: diskEntry.itemID)
			guard !pendingRemovedKeys.contains(key), existingKeys.insert(key).inserted else { continue }
			working.append(diskEntry)
		}
		working.sort { $0.addedAt > $1.addedAt }
		pendingRemovedKeys.removeAll()
		applyEntries(working)
	}
	
	private func applyEntries(_ newEntries: [WishlistEntry]) {
		entries = newEntries
		var keys: Set<LookupKey> = []
		var skins: Set<WeaponSkin.ID> = []
		keys.reserveCapacity(newEntries.count)
		for entry in newEntries {
			keys.insert(LookupKey(kind: entry.kind, itemID: entry.itemID))
			if entry.kind == .skin {
				skins.insert(entry.skinID)
			}
		}
		lookupIndex = keys
		cachedSkinIDs = skins
	}
	
	var skinIDs: Set<WeaponSkin.ID> {
		cachedSkinIDs
	}
	
	func contains(_ skinID: WeaponSkin.ID) -> Bool {
		contains(kind: .skin, itemID: skinID.rawID)
	}
	
	func contains(kind: WishlistItemKind, itemID: LowercaseUUID) -> Bool {
		lookupIndex.contains(LookupKey(kind: kind, itemID: itemID))
	}
	
	func toggle(_ skinID: WeaponSkin.ID) {
		toggle(kind: .skin, itemID: skinID.rawID)
	}
	
	func toggle(kind: WishlistItemKind, itemID: LowercaseUUID) {
		let key = LookupKey(kind: kind, itemID: itemID)
		var working = entries
		if lookupIndex.contains(key) {
			working.removeAll { $0.kind == kind && $0.itemID == itemID }
			if !hasLoadedFromDisk {
				pendingRemovedKeys.insert(key)
			}
		} else {
			pendingRemovedKeys.remove(key)
			working.insert(WishlistEntry(kind: kind, itemID: itemID), at: 0)
		}
		applyEntries(working)
		persist()
	}
	
	func remove(id: WeaponSkin.ID) {
		remove(kind: .skin, itemID: id.rawID)
	}
	
	func remove(kind: WishlistItemKind, itemID: LowercaseUUID) {
		let key = LookupKey(kind: kind, itemID: itemID)
		if !hasLoadedFromDisk {
			pendingRemovedKeys.insert(key)
		}
		guard lookupIndex.contains(key) else { return }
		var working = entries
		working.removeAll { $0.kind == kind && $0.itemID == itemID }
		applyEntries(working)
		persist()
	}
	
	@discardableResult
	func importEntries(_ incoming: [WishlistEntry], replaceAll: Bool) async -> Int {
		await waitUntilLoaded()
		pendingSaveTask?.cancel()
		var workingByKey: [LookupKey: WishlistEntry] = [:]
		if !replaceAll {
			workingByKey.reserveCapacity(entries.count + incoming.count)
			for entry in entries {
				workingByKey[LookupKey(kind: entry.kind, itemID: entry.itemID)] = entry
			}
		}
		var changedCount = 0
		
		for entry in incoming {
			let key = LookupKey(kind: entry.kind, itemID: entry.itemID)
			if let existing = workingByKey[key] {
				if entry.addedAt < existing.addedAt {
					var updated = existing
					updated.addedAt = entry.addedAt
					workingByKey[key] = updated
					changedCount += 1
				}
			} else {
				workingByKey[key] = entry
				changedCount += 1
			}
		}
		
		let working = workingByKey.values.sorted { $0.addedAt > $1.addedAt }
		applyEntries(working)
		await LocalJSONStore.saveAndWait(entries, to: filename)
		return replaceAll ? working.count : changedCount
	}
	
	func isOfferWishlisted(_ offer: StoreOffer, assets: AssetCollection?) -> Bool {
		guard let assets else { return false }
		for reward in offer.rewards {
			if let level = reward.skinLevel, let resolved = assets.resolveSkin(level), contains(resolved.skin.id) {
				return true
			}
			if let buddy = reward.buddy, let info = assets.resolveBuddy(buddy),
			   contains(kind: .buddy, itemID: info.id.rawID) {
				return true
			}
			if let spray = reward.spray, contains(kind: .spray, itemID: spray.rawID) {
				return true
			}
			if let card = reward.card, contains(kind: .card, itemID: card.rawID) {
				return true
			}
			if let title = reward.title, contains(kind: .title, itemID: title.rawID) {
				return true
			}
			if let totem = reward.totem, contains(kind: .flex, itemID: totem.rawID) {
				return true
			}
		}
		return false
	}
	
	func matchingDailyOffers(in storefront: Storefront, assets: AssetCollection?) -> [ResolvedLevel] {
		guard let assets else { return [] }
		return storefront.dailySkinStore.offers.compactMap { offer in
			for reward in offer.rewards {
				if let level = reward.skinLevel, let resolved = assets.resolveSkin(level), contains(resolved.skin.id) {
					return resolved
				}
			}
			return nil
		}
	}
	
	private func persist() {
		if hasLoadedFromDisk {
			LocalJSONStore.save(entries, to: filename)
		} else {
			pendingSaveTask?.cancel()
			pendingSaveTask = Task { @MainActor [weak self] in
				await self?.waitUntilLoaded()
				guard let self, !Task.isCancelled else { return }
				LocalJSONStore.save(self.entries, to: self.filename)
			}
		}
	}
}
