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
	@Published var entries: [WishlistEntry] = []
	
	private let filename = "Wishlist.v1.json"
	
	init() {
		entries = LocalJSONStore.load([WishlistEntry].self, from: filename) ?? []
	}
	
	var skinIDs: Set<WeaponSkin.ID> {
		Set(entries.lazy.filter { $0.kind == .skin }.map(\.skinID))
	}
	
	func contains(_ skinID: WeaponSkin.ID) -> Bool {
		contains(kind: .skin, itemID: skinID.rawID)
	}
	
	func contains(kind: WishlistItemKind, itemID: LowercaseUUID) -> Bool {
		entries.contains { $0.kind == kind && $0.itemID == itemID }
	}
	
	func toggle(_ skinID: WeaponSkin.ID) {
		toggle(kind: .skin, itemID: skinID.rawID)
	}
	
	func toggle(kind: WishlistItemKind, itemID: LowercaseUUID) {
		if contains(kind: kind, itemID: itemID) {
			entries.removeAll { $0.kind == kind && $0.itemID == itemID }
		} else {
			entries.insert(WishlistEntry(kind: kind, itemID: itemID), at: 0)
		}
		persist()
	}
	
	func remove(id: WeaponSkin.ID) {
		remove(kind: .skin, itemID: id.rawID)
	}
	
	func remove(kind: WishlistItemKind, itemID: LowercaseUUID) {
		entries.removeAll { $0.kind == kind && $0.itemID == itemID }
		persist()
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
		LocalJSONStore.save(entries, to: filename)
	}
}
