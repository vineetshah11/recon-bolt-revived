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
	private struct AccountDayKey: Hashable {
		var accountID: User.ID
		var id: String
	}
	
	private struct StatsScopeKey: Hashable {
		var accountID: User.ID?
		var version: AssetVersion
	}
	
	private struct AccessoryKey: Hashable {
		var kind: WishlistItemKind
		var itemID: LowercaseUUID
	}
	
	private struct CachedAccountStats {
		var skinStats: [WeaponSkin.ID: WishlistAppearanceStats]
		var accessoryStats: [AccessoryKey: WishlistAppearanceStats]
	}
	
	@Published var days: [ShopHistoryDay] = [] {
		didSet {
			statsCache.removeAll(keepingCapacity: true)
		}
	}
	@Published private(set) var lastDailyCheckAt: Date?
	@Published private(set) var lastDailyCheckAccountCount: Int
	
	private let filename = "ShopHistory.v1.json"
	private static let lastCheckAtKey = "ShopHistory.lastCheckAt"
	private static let lastCheckCountKey = "ShopHistory.lastCheckAccountCount"
	
	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)!
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	private static let expiryMatchTolerance: TimeInterval = 7_200 // 2h leeway for clock drift
	private static let offerDuplicateWindow: TimeInterval = 26 * 3_600
	
	private var hasLoadedFromDisk = false
	private var initialLoadTask: Task<Void, Never>?
	private var pendingSaveTask: Task<Void, Never>?
	private var statsCache: [StatsScopeKey: CachedAccountStats] = [:]
	
	init() {
		lastDailyCheckAt = UserDefaults.standard.object(forKey: Self.lastCheckAtKey) as? Date
		lastDailyCheckAccountCount = UserDefaults.standard.integer(forKey: Self.lastCheckCountKey)
		initialLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let loaded = await LocalJSONStore.loadAsync([ShopHistoryDay].self, from: self.filename) ?? []
			let deduplicated = await Task.detached(priority: .userInitiated) {
				Self.deduplicateRotations(loaded)
			}.value
			self.mergeDiskDays(deduplicated, originalCount: loaded.count, didChangeOnLoad: deduplicated != loaded)
		}
	}
	
	func waitUntilLoaded() async {
		if let initialLoadTask, !hasLoadedFromDisk {
			await initialLoadTask.value
		}
	}
	
	private func mergeDiskDays(_ diskDays: [ShopHistoryDay], originalCount: Int, didChangeOnLoad: Bool) {
		hasLoadedFromDisk = true
		if days.isEmpty {
			days = diskDays
			if didChangeOnLoad {
				persist()
			}
			return
		}
		let merged = Self.deduplicateRotations(diskDays + days)
		days = merged
		if didChangeOnLoad || merged.count != originalCount {
			persist()
		}
	}
	
	func days(for accountID: User.ID?) -> [ShopHistoryDay] {
		guard let accountID else { return days }
		return days.filter { $0.accountID == accountID }
	}
	
	func dayCount(for accountID: User.ID?) -> Int {
		guard let accountID else { return days.count }
		var count = 0
		for day in days where day.accountID == accountID {
			count += 1
		}
		return count
	}
	
	func firstRecordedDate(for accountID: User.ID?) -> Date? {
		if let accountID {
			return days.last { $0.accountID == accountID }?.date
		}
		return days.last?.date
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
		let dayKey = Self.rotationKey(now: now, remainingDuration: remaining)
		
		var daysModified = false
		if let existingIdx = days.firstIndex(where: {
			$0.accountID == accountID
			&& Self.isSameRotation(
				$0,
				now: now,
				remaining: remaining,
				offerLevels: offerLevels,
				targetKey: dayKey
			)
		}) {
			let existing = days[existingIdx]
			let contentUnchanged = existing.id == dayKey
				&& existing.offerSkinLevelIDs == offerLevels
				&& (nmLevels == nil || existing.nightMarketLevelIDs == nmLevels)
				&& (accessories == nil || existing.accessoryOffers == accessories)
				&& existing.dailyRemainingDuration != nil
			if !contentUnchanged {
				var updated = existing
				updated.id = dayKey
				updated.dailyRemainingDuration = remaining
				updated.date = max(existing.date, now)
				updated.offerSkinLevelIDs = offerLevels
				updated.nightMarketLevelIDs = nmLevels ?? existing.nightMarketLevelIDs
				updated.accessoryOffers = accessories ?? existing.accessoryOffers
				days[existingIdx] = updated
				days.sort { $0.date > $1.date }
				daysModified = true
			}
		} else {
			let newEntry = ShopHistoryDay(
				id: dayKey,
				accountID: accountID,
				date: now,
				offerSkinLevelIDs: offerLevels,
				nightMarketLevelIDs: nmLevels,
				accessoryOffers: accessories,
				dailyRemainingDuration: remaining
			)
			if let insertIdx = days.firstIndex(where: { $0.date <= now }) {
				days.insert(newEntry, at: insertIdx)
			} else {
				days.append(newEntry)
			}
			daysModified = true
		}
		
		let shouldUpdateCheckMetadata = daysModified
			|| lastDailyCheckAt == nil
			|| now.timeIntervalSince(lastDailyCheckAt!) >= 60
		if shouldUpdateCheckMetadata {
			lastDailyCheckAt = now
			if lastDailyCheckAccountCount == 0 {
				lastDailyCheckAccountCount = 1
			}
			UserDefaults.standard.set(now, forKey: Self.lastCheckAtKey)
			UserDefaults.standard.set(lastDailyCheckAccountCount, forKey: Self.lastCheckCountKey)
		}
		if daysModified {
			persist()
		}
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
		let stats = cachedAccountStats(for: accountID, assets: assets)
		if entry.kind == .skin {
			return stats.skinStats[entry.skinID] ?? WishlistAppearanceStats(count: 0, lastSeenDate: nil)
		}
		let key = AccessoryKey(kind: entry.kind, itemID: entry.itemID)
		return stats.accessoryStats[key] ?? WishlistAppearanceStats(count: 0, lastSeenDate: nil)
	}
	
	private func cachedAccountStats(for accountID: User.ID?, assets: AssetCollection) -> CachedAccountStats {
		let scopeKey = StatsScopeKey(accountID: accountID, version: assets.version)
		if let cached = statsCache[scopeKey] {
			return cached
		}
		
		var skinStats: [WeaponSkin.ID: WishlistAppearanceStats] = [:]
		var accessoryStats: [AccessoryKey: WishlistAppearanceStats] = [:]
		let accountDays = days(for: accountID)
		
		for day in accountDays {
			var seenSkinsInDay: Set<WeaponSkin.ID> = []
			for levelID in day.offerSkinLevelIDs {
				guard let resolved = assets.resolveSkin(levelID),
					  seenSkinsInDay.insert(resolved.skin.id).inserted else { continue }
				var stat = skinStats[resolved.skin.id] ?? WishlistAppearanceStats(count: 0, lastSeenDate: day.date)
				stat.count += 1
				if stat.lastSeenDate == nil || day.date > stat.lastSeenDate! {
					stat.lastSeenDate = day.date
				}
				skinStats[resolved.skin.id] = stat
			}
			if let nm = day.nightMarketLevelIDs {
				for levelID in nm {
					guard let resolved = assets.resolveSkin(levelID),
						  seenSkinsInDay.insert(resolved.skin.id).inserted else { continue }
					var stat = skinStats[resolved.skin.id] ?? WishlistAppearanceStats(count: 0, lastSeenDate: day.date)
					stat.count += 1
					if stat.lastSeenDate == nil || day.date > stat.lastSeenDate! {
						stat.lastSeenDate = day.date
					}
					skinStats[resolved.skin.id] = stat
				}
			}
			if let accessories = day.accessoryOffers {
				var seenAccessoriesInDay: Set<AccessoryKey> = []
				for offer in accessories {
					let kind: WishlistItemKind?
					let resolvedID: LowercaseUUID
					switch offer.itemTypeID {
					case .buddies:
						kind = .buddy
						resolvedID = assets.resolveBuddy(.init(rawID: offer.itemID))?.id.rawID ?? offer.itemID
					case .sprays:
						kind = .spray
						resolvedID = offer.itemID
					case .cards:
						kind = .card
						resolvedID = offer.itemID
					case .titles:
						kind = .title
						resolvedID = offer.itemID
					case .totems:
						kind = .flex
						resolvedID = offer.itemID
					default:
						kind = nil
						resolvedID = offer.itemID
					}
					guard let kind else { continue }
					let key = AccessoryKey(kind: kind, itemID: resolvedID)
					guard seenAccessoriesInDay.insert(key).inserted else { continue }
					var stat = accessoryStats[key] ?? WishlistAppearanceStats(count: 0, lastSeenDate: day.date)
					stat.count += 1
					if stat.lastSeenDate == nil || day.date > stat.lastSeenDate! {
						stat.lastSeenDate = day.date
					}
					accessoryStats[key] = stat
				}
			}
		}
		
		let built = CachedAccountStats(skinStats: skinStats, accessoryStats: accessoryStats)
		statsCache[scopeKey] = built
		return built
	}
	
	func skinFrequencies(for accountID: User.ID?, assets: AssetCollection?) -> [SkinFrequencyStat] {
		guard let assets else { return [] }
		let accountDays = days(for: accountID)
		// accountDays is maintained in descending date order; appending yields dates already descending.
		var bySkin: [WeaponSkin.ID: (resolved: ResolvedLevel, count: Int, newest: Date, oldest: Date)] = [:]
		
		for day in accountDays {
			var seenInDay: Set<WeaponSkin.ID> = []
			for levelID in day.offerSkinLevelIDs {
				guard let resolved = assets.resolveSkin(levelID),
					  seenInDay.insert(resolved.skin.id).inserted else { continue }
				if var entry = bySkin[resolved.skin.id] {
					entry.count += 1
					if day.date > entry.newest { entry.newest = day.date }
					if day.date < entry.oldest { entry.oldest = day.date }
					bySkin[resolved.skin.id] = entry
				} else {
					bySkin[resolved.skin.id] = (resolved, 1, day.date, day.date)
				}
			}
		}
		
		return bySkin.values.map { item in
			let avgInterval: Int? = {
				guard item.count >= 2 else { return nil }
				let spanDays = item.newest.timeIntervalSince(item.oldest) / Double(86_400)
				return max(1, Int(round(spanDays / Double(item.count - 1))))
			}()
			return SkinFrequencyStat(
				skin: item.resolved.skin,
				weapon: item.resolved.weapon,
				levelID: item.resolved.level.id,
				count: item.count,
				lastSeenDate: item.newest,
				averageIntervalDays: avgInterval
			)
		}
		.sorted { lhs, rhs in
			if lhs.count != rhs.count { return lhs.count > rhs.count }
			return lhs.lastSeenDate > rhs.lastSeenDate
		}
	}
	
	func exportDays(for playerIDs: Set<User.ID>?) -> [ShopHistoryDay] {
		guard let playerIDs else { return days }
		return days.filter { playerIDs.contains($0.accountID) }
	}
	
	@discardableResult
	func importDays(_ incoming: [ShopHistoryDay], replaceAll: Bool) async -> Int {
		await waitUntilLoaded()
		pendingSaveTask?.cancel()
		var working = replaceAll ? [] : days
		var indexByKey: [AccountDayKey: Int] = [:]
		indexByKey.reserveCapacity(working.count + incoming.count)
		for (idx, day) in working.enumerated() {
			indexByKey[AccountDayKey(accountID: day.accountID, id: day.id)] = idx
		}
		var changedCount = 0
		
		for day in incoming {
			let key = AccountDayKey(accountID: day.accountID, id: day.id)
			if let idx = indexByKey[key] {
				if day.date > working[idx].date {
					working[idx] = day
					changedCount += 1
				}
			} else {
				indexByKey[key] = working.count
				working.append(day)
				changedCount += 1
			}
		}
		
		let deduplicated = Self.deduplicateRotations(working)
		days = deduplicated
		await LocalJSONStore.saveAndWait(days, to: filename)
		return replaceAll ? deduplicated.count : changedCount
	}
	
	nonisolated static func rotationKey(now: Date, remainingDuration: TimeInterval?) -> String {
		if let remaining = remainingDuration, remaining > 0, remaining <= 172_800 {
			let expiry = now.addingTimeInterval(remaining)
			// Anchoring 12h before expiry maps every timestamp inside a 24h UTC shop window to the same yyyy-MM-dd key.
			let midpoint = expiry.addingTimeInterval(-43_200)
			return dayFormatter.string(from: midpoint)
		}
		return dayFormatter.string(from: now)
	}
	
	private nonisolated static func isSameRotation(
		_ existing: ShopHistoryDay,
		now: Date,
		remaining: TimeInterval?,
		offerLevels: [Weapon.Skin.Level.ID],
		targetKey: String,
		existingNormalizedKey: String? = nil
	) -> Bool {
		if existing.id == targetKey {
			return true
		}
		let normalizedExisting = existingNormalizedKey ?? existing.dailyRemainingDuration.map {
			rotationKey(now: existing.date, remainingDuration: $0)
		} ?? existing.id
		if normalizedExisting == targetKey {
			return true
		}
		if let existingRemaining = existing.dailyRemainingDuration, existingRemaining > 0,
		   let remaining, remaining > 0 {
			let existingExpiry = existing.date.addingTimeInterval(existingRemaining)
			let newExpiry = now.addingTimeInterval(remaining)
			if abs(existingExpiry.timeIntervalSince(newExpiry)) <= expiryMatchTolerance {
				return true
			}
		}
		if !offerLevels.isEmpty,
		   existing.offerSkinLevelIDs.count == offerLevels.count,
		   abs(now.timeIntervalSince(existing.date)) <= offerDuplicateWindow,
		   Set(existing.offerSkinLevelIDs) == Set(offerLevels) {
			return true
		}
		return false
	}
	
	private nonisolated static func deduplicateRotations(_ input: [ShopHistoryDay]) -> [ShopHistoryDay] {
		var result: [ShopHistoryDay] = []
		result.reserveCapacity(input.count)
		var indexByKey: [AccountDayKey: Int] = [:]
		var recentIndicesByAccount: [User.ID: [Int]] = [:]
		
		let chronological = input.sorted { $0.date < $1.date }
		
		for var entry in chronological {
			let normalizedKey: String
			if let remaining = entry.dailyRemainingDuration, remaining > 0 {
				normalizedKey = rotationKey(now: entry.date, remainingDuration: remaining)
				entry.id = normalizedKey
			} else {
				normalizedKey = entry.id
			}
			
			let exactKey = AccountDayKey(accountID: entry.accountID, id: normalizedKey)
			var matchedIndex = indexByKey[exactKey]
			
			if matchedIndex == nil, let candidates = recentIndicesByAccount[entry.accountID] {
				for idx in candidates.reversed() {
					let existing = result[idx]
					if isSameRotation(
						existing,
						now: entry.date,
						remaining: entry.dailyRemainingDuration,
						offerLevels: entry.offerSkinLevelIDs,
						targetKey: normalizedKey,
						existingNormalizedKey: existing.id
					) {
						matchedIndex = idx
						break
					}
				}
			}
			
			if let matchIdx = matchedIndex {
				let older = result[matchIdx]
				var merged = entry.date >= older.date ? entry : older
				merged.id = normalizedKey.count == 10 ? normalizedKey : merged.id
				merged.nightMarketLevelIDs = entry.nightMarketLevelIDs ?? older.nightMarketLevelIDs
				merged.accessoryOffers = entry.accessoryOffers ?? older.accessoryOffers
				if merged.dailyRemainingDuration == nil {
					merged.dailyRemainingDuration = older.dailyRemainingDuration
				}
				result[matchIdx] = merged
				indexByKey[AccountDayKey(accountID: merged.accountID, id: merged.id)] = matchIdx
			} else {
				let newIndex = result.count
				result.append(entry)
				indexByKey[exactKey] = newIndex
				var recent = recentIndicesByAccount[entry.accountID] ?? []
				recent.append(newIndex)
				if recent.count > 3 {
					recent.removeFirst(recent.count - 3)
				}
				recentIndicesByAccount[entry.accountID] = recent
			}
		}
		
		return result.sorted { $0.date > $1.date }
	}
	
	private func persist() {
		if hasLoadedFromDisk {
			LocalJSONStore.save(days, to: filename)
		} else {
			pendingSaveTask?.cancel()
			pendingSaveTask = Task { @MainActor [weak self] in
				await self?.waitUntilLoaded()
				guard let self, !Task.isCancelled else { return }
				LocalJSONStore.save(self.days, to: self.filename)
			}
		}
	}
}

extension ShopHistoryDay {
	private static let localDayParser: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.timeZone = .autoupdatingCurrent
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	/// Calendar-friendly date matching the UTC rotation ID (`yyyy-MM-dd`), avoiding local post-midnight shifts.
	var rotationDisplayDate: Date {
		if id.count == 10, let localDate = Self.localDayParser.date(from: id) {
			return localDate
		}
		return date
	}
}
