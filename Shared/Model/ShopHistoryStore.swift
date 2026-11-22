import Foundation
import Combine
import ValorantAPI

struct ShopHistoryDay: Identifiable, Codable, Equatable {
	var id: String // YYYY-MM-DD
	var accountID: User.ID
	var date: Date
	var offerSkinLevelIDs: [Weapon.Skin.Level.ID]
	var nightMarketLevelIDs: [Weapon.Skin.Level.ID]?
}

@MainActor
final class ShopHistoryStore: ObservableObject {
	@Published var days: [ShopHistoryDay] = []
	
	private let filename = "ShopHistory.v1.json"
	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	init() {
		days = LocalJSONStore.load([ShopHistoryDay].self, from: filename) ?? []
	}
	
	func days(for accountID: User.ID?) -> [ShopHistoryDay] {
		days
			.filter { accountID == nil || $0.accountID == accountID }
			.sorted { $0.date > $1.date }
	}
	
	func record(storefront: Storefront, for accountID: User.ID) {
		let offerLevels = storefront.dailySkinStore.offers.compactMap { $0.rewards.first?.skinLevel }
		guard !offerLevels.isEmpty else { return }
		
		let nmLevels = storefront.nightMarket?.offers.compactMap { $0.offer.rewards.first?.skinLevel }
		let dayKey = Self.dayFormatter.string(from: Date())
		
		if let existingIdx = days.firstIndex(where: { $0.accountID == accountID && $0.id == dayKey }) {
			if days[existingIdx].offerSkinLevelIDs == offerLevels && days[existingIdx].nightMarketLevelIDs == nmLevels {
				return
			}
			days[existingIdx].offerSkinLevelIDs = offerLevels
			days[existingIdx].nightMarketLevelIDs = nmLevels
			days[existingIdx].date = Date()
		} else {
			days.insert(
				ShopHistoryDay(
					id: dayKey,
					accountID: accountID,
					date: Date(),
					offerSkinLevelIDs: offerLevels,
					nightMarketLevelIDs: nmLevels
				),
				at: 0
			)
		}
		persist()
	}
	
	func appearanceCount(for skinID: Weapon.Skin.ID, accountID: User.ID?, assets: AssetCollection?) -> Int {
		guard let assets else { return 0 }
		return days(for: accountID).reduce(0) { total, day in
			let matched = day.offerSkinLevelIDs.contains { level in
				assets.resolveSkin(level)?.skin.id == skinID
			}
			return total + (matched ? 1 : 0)
		}
	}
	
	private func persist() {
		LocalJSONStore.save(days, to: filename)
	}
}
