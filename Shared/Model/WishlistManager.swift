import Foundation
import Combine
import ValorantAPI

struct WishlistEntry: Identifiable, Codable, Equatable {
	var id: WeaponSkin.ID { skinID }
	var skinID: WeaponSkin.ID
	var addedAt = Date()
}

@MainActor
final class WishlistManager: ObservableObject {
	@Published var entries: [WishlistEntry] = []
	
	private let filename = "Wishlist.v1.json"
	
	init() {
		entries = LocalJSONStore.load([WishlistEntry].self, from: filename) ?? []
	}
	
	var skinIDs: Set<WeaponSkin.ID> {
		Set(entries.map(\.skinID))
	}
	
	func contains(_ skinID: WeaponSkin.ID) -> Bool {
		entries.contains { $0.skinID == skinID }
	}
	
	func toggle(_ skinID: WeaponSkin.ID) {
		if contains(skinID) {
			entries.removeAll { $0.skinID == skinID }
		} else {
			entries.insert(WishlistEntry(skinID: skinID), at: 0)
		}
		persist()
	}
	
	func remove(id: WeaponSkin.ID) {
		entries.removeAll { $0.skinID == id }
		persist()
	}
	
	func isOfferWishlisted(_ offer: StoreOffer, assets: AssetCollection?) -> Bool {
		guard let assets else { return false }
		for reward in offer.rewards {
			if let level = reward.skinLevel, let resolved = assets.resolveSkin(level) {
				if contains(resolved.skin.id) {
					return true
				}
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
