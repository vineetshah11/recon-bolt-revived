import Foundation
import ValorantAPI

struct RecordedAccessoryOffer: Codable, Equatable, Hashable {
	var itemTypeID: ItemType.ID
	var itemID: LowercaseUUID
}

struct ShopHistoryDay: Identifiable, Codable, Equatable {
	var id: String // YYYY-MM-DD
	var accountID: User.ID
	var date: Date
	var offerSkinLevelIDs: [Weapon.Skin.Level.ID]
	var nightMarketLevelIDs: [Weapon.Skin.Level.ID]?
	var accessoryOffers: [RecordedAccessoryOffer]? = nil
	var dailyRemainingDuration: TimeInterval? = nil
}

struct WishlistAppearanceStats {
	var count: Int
	var lastSeenDate: Date?
}

struct SkinFrequencyStat: Identifiable {
	var id: WeaponSkin.ID { skin.id }
	var skin: WeaponSkin
	var weapon: WeaponInfo
	var levelID: WeaponSkin.Level.ID
	var count: Int
	var lastSeenDate: Date
	var averageIntervalDays: Int?
}

@MainActor
final class ShopHistoryStore: ObservableObject {
	@Published var days: [ShopHistoryDay] = []
	@Published private(set) var lastDailyCheckAt: Date?
	@Published private(set) var lastDailyCheckAccountCount: Int
	
	private let filename = "ShopHistory.v1.json"
	private static let lastCheckAtKey = "ShopHistory.lastCheckAt"
	private static let lastCheckCountKey = "ShopHistory.lastCheckAccountCount"
	
	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	init() {
		days = LocalJSONStore.load([ShopHistoryDay].self, from: filename) ?? []
		lastDailyCheckAt = UserDefaults.standard.object(forKey: Self.lastCheckAtKey) as? Date
		lastDailyCheckAccountCount = UserDefaults.standard.integer(forKey: Self.lastCheckCountKey)
	}
	
	func days(for accountID: User.ID?) -> [ShopHistoryDay] {
		days
			.filter { accountID == nil || $0.accountID == accountID }
			.sorted { $0.date > $1.date }
	}
	
	func firstRecordedDate(for accountID: User.ID?) -> Date? {
		days(for: accountID).last?.date
	}
	
	func recordDailyCheck(accountCount: Int) {
		let now = Date()
		lastDailyCheckAt = now
		lastDailyCheckAccountCount = max(1, accountCount)
		UserDefaults.standard.set(now, forKey: Self.lastCheckAtKey)
		UserDefaults.standard.set(lastDailyCheckAccountCount, forKey: Self.lastCheckCountKey)
	}
	
	func record(storefront: Storefront, for accountID: User.ID) {
		let offerLevels = storefront.dailySkinStore.offers.compactMap { $0.rewards.first?.skinLevel }
		guard !offerLevels.isEmpty else { return }
		
		let nmLevels = storefront.nightMarket?.offers.compactMap { $0.offer.rewards.first?.skinLevel }
		let accessories = storefront.accessoryStore.offers?.compactMap { offer -> RecordedAccessoryOffer? in
			guard let reward = offer.offer.rewards.first else { return nil }
			return RecordedAccessoryOffer(itemTypeID: reward.itemTypeID, itemID: reward.itemID)
		}
		let remaining = storefront.dailySkinStore.remainingDuration
		let now = Date()
		let dayKey = Self.dayFormatter.string(from: now)
		
		if let existingIdx = days.firstIndex(where: { $0.accountID == accountID && $0.id == dayKey }) {
			let unchanged = days[existingIdx].offerSkinLevelIDs == offerLevels
				&& days[existingIdx].nightMarketLevelIDs == nmLevels
				&& days[existingIdx].accessoryOffers == accessories
			days[existingIdx].dailyRemainingDuration = remaining
			days[existingIdx].date = now
			if !unchanged {
				days[existingIdx].offerSkinLevelIDs = offerLevels
				days[existingIdx].nightMarketLevelIDs = nmLevels
				days[existingIdx].accessoryOffers = accessories
			}
		} else {
			days.insert(
				ShopHistoryDay(
					id: dayKey,
					accountID: accountID,
					date: now,
					offerSkinLevelIDs: offerLevels,
					nightMarketLevelIDs: nmLevels,
					accessoryOffers: accessories,
					dailyRemainingDuration: remaining
				),
				at: 0
			)
		}
		
		lastDailyCheckAt = now
		if lastDailyCheckAccountCount == 0 {
			lastDailyCheckAccountCount = 1
		}
		UserDefaults.standard.set(now, forKey: Self.lastCheckAtKey)
		UserDefaults.standard.set(lastDailyCheckAccountCount, forKey: Self.lastCheckCountKey)
		persist()
	}
	
	func appearanceCount(for skinID: Weapon.Skin.ID, accountID: User.ID?, assets: AssetCollection?) -> Int {
		appearanceStats(for: WishlistEntry(skinID: skinID), accountID: accountID, assets: assets).count
	}
	
	func appearanceStats(
		for entry: WishlistEntry,
		accountID: User.ID?,
		assets: AssetCollection?
	) -> WishlistAppearanceStats {
		guard let assets else { return WishlistAppearanceStats(count: 0, lastSeenDate: nil) }
		let matchingDays = days(for: accountID).filter { day in
			dayMatches(day, entry: entry, assets: assets)
		}
		return WishlistAppearanceStats(
			count: matchingDays.count,
			lastSeenDate: matchingDays.first?.date
		)
	}
	
	private func dayMatches(_ day: ShopHistoryDay, entry: WishlistEntry, assets: AssetCollection) -> Bool {
		switch entry.kind {
		case .skin:
			let targetSkinID = entry.skinID
			if day.offerSkinLevelIDs.contains(where: { assets.resolveSkin($0)?.skin.id == targetSkinID }) {
				return true
			}
			if let nm = day.nightMarketLevelIDs,
			   nm.contains(where: { assets.resolveSkin($0)?.skin.id == targetSkinID }) {
				return true
			}
			return false
		case .buddy:
			return day.accessoryOffers?.contains { offer in
				guard offer.itemTypeID == .buddies else { return false }
				if offer.itemID == entry.itemID { return true }
				return assets.resolveBuddy(.init(rawID: offer.itemID))?.id.rawID == entry.itemID
			} ?? false
		case .spray:
			return day.accessoryOffers?.contains {
				$0.itemTypeID == .sprays && $0.itemID == entry.itemID
			} ?? false
		case .card:
			return day.accessoryOffers?.contains {
				$0.itemTypeID == .cards && $0.itemID == entry.itemID
			} ?? false
		case .title:
			return day.accessoryOffers?.contains {
				$0.itemTypeID == .titles && $0.itemID == entry.itemID
			} ?? false
		case .flex:
			return day.accessoryOffers?.contains {
				$0.itemTypeID == .totems && $0.itemID == entry.itemID
			} ?? false
		}
	}
	
	func skinFrequencies(for accountID: User.ID?, assets: AssetCollection?) -> [SkinFrequencyStat] {
		guard let assets else { return [] }
		let accountDays = days(for: accountID)
		var bySkin: [WeaponSkin.ID: (resolved: ResolvedLevel, dates: [Date])] = [:]
		
		for day in accountDays {
			var seenInDay: Set<WeaponSkin.ID> = []
			for levelID in day.offerSkinLevelIDs {
				guard let resolved = assets.resolveSkin(levelID),
					  seenInDay.insert(resolved.skin.id).inserted else { continue }
				if var entry = bySkin[resolved.skin.id] {
					entry.dates.append(day.date)
					bySkin[resolved.skin.id] = entry
				} else {
					bySkin[resolved.skin.id] = (resolved, [day.date])
				}
			}
		}
		
		return bySkin.values.map { item in
			let sortedDates = item.dates.sorted(by: >)
			let avgInterval: Int? = {
				guard sortedDates.count >= 2,
					  let newest = sortedDates.first,
					  let oldest = sortedDates.last else { return nil }
				let spanDays = newest.timeIntervalSince(oldest) / Double(86_400)
				return max(1, Int(round(spanDays / Double(sortedDates.count - 1))))
			}()
			return SkinFrequencyStat(
				skin: item.resolved.skin,
				weapon: item.resolved.weapon,
				levelID: item.resolved.level.id,
				count: sortedDates.count,
				lastSeenDate: sortedDates.first ?? Date(),
				averageIntervalDays: avgInterval
			)
		}
		.sorted { lhs, rhs in
			if lhs.count != rhs.count { return lhs.count > rhs.count }
			return lhs.lastSeenDate > rhs.lastSeenDate
		}
	}
	
	private func persist() {
		LocalJSONStore.save(days, to: filename)
	}
}
