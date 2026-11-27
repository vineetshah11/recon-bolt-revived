import BackgroundTasks
import Combine
import Foundation
import UIKit
import UserDefault
import UserNotifications
import ValorantAPI

struct NotificationRoute: Equatable {
	let id: UUID
	let accountID: User.ID?
	let expandNightMarket: Bool
}

struct TrackedBundle: Codable, Equatable, Identifiable {
	var id: String
	var name: String
	var expiryDate: Date
	var totalVP: Int
}

struct StoreNotificationState: Codable, Equatable {
	var lastKnownDailyRefreshDate: Date?
	var lastDailyRotationSeenOrNotified: String?
	var lastWishlistNotifiedSignatures: [String: String] = [:]
	var lastAccessoryNotifiedSignatures: [String: String] = [:]
	var lastNightMarketLiveWindowNotified: String?
	var notifiedLeavingBundleIDs: Set<String> = []
	var trackedBundles: [TrackedBundle] = []
	var trackedNightMarketExpiry: Date?
	var scheduledDailyFireDates: [String: Date] = [:]
	var lastBackgroundCheckAt: Date?
	var lastBackgroundCheckSource: String?
	var lastBackgroundCheckSummary: String?
	var lastBackgroundScheduleError: String?
	
	init() {}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		lastKnownDailyRefreshDate = try container.decodeIfPresent(Date.self, forKey: .lastKnownDailyRefreshDate)
		lastDailyRotationSeenOrNotified = try container.decodeIfPresent(String.self, forKey: .lastDailyRotationSeenOrNotified)
		lastWishlistNotifiedSignatures = try container.decodeIfPresent([String: String].self, forKey: .lastWishlistNotifiedSignatures) ?? [:]
		lastAccessoryNotifiedSignatures = try container.decodeIfPresent([String: String].self, forKey: .lastAccessoryNotifiedSignatures) ?? [:]
		lastNightMarketLiveWindowNotified = try container.decodeIfPresent(String.self, forKey: .lastNightMarketLiveWindowNotified)
		notifiedLeavingBundleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .notifiedLeavingBundleIDs) ?? []
		trackedBundles = try container.decodeIfPresent([TrackedBundle].self, forKey: .trackedBundles) ?? []
		trackedNightMarketExpiry = try container.decodeIfPresent(Date.self, forKey: .trackedNightMarketExpiry)
		scheduledDailyFireDates = try container.decodeIfPresent([String: Date].self, forKey: .scheduledDailyFireDates) ?? [:]
		lastBackgroundCheckAt = try container.decodeIfPresent(Date.self, forKey: .lastBackgroundCheckAt)
		lastBackgroundCheckSource = try container.decodeIfPresent(String.self, forKey: .lastBackgroundCheckSource)
		lastBackgroundCheckSummary = try container.decodeIfPresent(String.self, forKey: .lastBackgroundCheckSummary)
		lastBackgroundScheduleError = try container.decodeIfPresent(String.self, forKey: .lastBackgroundScheduleError)
	}
}

struct MatchedWishlistOffer: Equatable {
	var name: String
	var priceText: String?
	var accountName: String?
	var accountID: User.ID?
	var isAccessory: Bool
}

struct NotificationPreviewContent: Equatable {
	var title: String
	var subtitle: String?
	var body: String
	var routeExpandNightMarket: Bool
}

struct ScheduledNotificationSummary: Identifiable, Equatable {
	var id: String
	var title: String
	var subtitle: String?
	var body: String
	var nextTriggerDate: Date?
	var isTest: Bool
}

enum StoreCheckSource: String {
	case backgroundRefresh = "Background Refresh"
	case manualDiagnostic = "Manual Check"
}

struct StoreCheckReport: Equatable {
	var checkedAt: Date
	var source: StoreCheckSource
	var accountsAttempted: Int
	var accountsSucceeded: Int
	var rotationKey: String?
	var nextDailyRefresh: Date?
	var wishlistMatchNames: [String]
	var activeBundleNames: [String]
	var nightMarketActive: Bool
	var notificationsPosted: [String]
	var errors: [String]
}

enum TestNotificationKind: String, CaseIterable, Identifiable {
	case shopRefresh
	case wishlistSingle
	case wishlistMultiple
	case bundleLeavingSoon
	case nightMarketLive
	case nightMarketLeavingSoon
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .shopRefresh: return "Daily Shop Refresh"
		case .wishlistSingle: return "Wishlist Match (1 Item)"
		case .wishlistMultiple: return "Wishlist Match (Multiple)"
		case .bundleLeavingSoon: return "Bundle Leaving Soon"
		case .nightMarketLive: return "Night Market Live"
		case .nightMarketLeavingSoon: return "Night Market Ending Soon"
		}
	}
}

enum TestNotificationDelay: Int, CaseIterable, Identifiable {
	case now = 1
	case fiveSeconds = 5
	case thirtySeconds = 30
	
	var id: Int { rawValue }
	
	var label: String {
		switch self {
		case .now: return "Now"
		case .fiveSeconds: return "5s"
		case .thirtySeconds: return "30s"
		}
	}
}

enum StoreNotificationContentBuilder {
	private static let maxBodyLength = 140
	
	static func shopRefresh() -> NotificationPreviewContent {
		NotificationPreviewContent(
			title: "Daily Shop Refreshed",
			subtitle: nil,
			body: "Your new daily weapon skins are now available in the Valorant store.",
			routeExpandNightMarket: false
		)
	}
	
	static func wishlistMatch(
		items: [MatchedWishlistOffer],
		accountNames: [String]
	) -> NotificationPreviewContent {
		let count = items.count
		let title = count == 1
			? "Wishlist Match in Your Shop!"
			: "\(count) Wishlist Items in Your Shop!"
		
		let subtitle: String?
		if accountNames.isEmpty {
			subtitle = nil
		} else if accountNames.count == 1 {
			subtitle = accountNames[0]
		} else if accountNames.count == 2 {
			subtitle = "\(accountNames[0]) & \(accountNames[1])"
		} else {
			subtitle = "\(accountNames[0]) +\(accountNames.count - 1) accounts"
		}
		
		let body = formatWishlistBody(items: items)
		return NotificationPreviewContent(
			title: title,
			subtitle: subtitle,
			body: body,
			routeExpandNightMarket: false
		)
	}
	
	static func bundleLeavingSoon(
		name: String,
		totalVP: Int?,
		remainingHours: Int
	) -> NotificationPreviewContent {
		let phrase = remainingHoursPhrase(remainingHours)
		let body: String
		if let totalVP, totalVP > 0 {
			body = "\(name) (\(totalVP.formatted()) VP) leaves the store in \(phrase)."
		} else {
			body = "\(name) leaves the store in \(phrase)."
		}
		return NotificationPreviewContent(
			title: "Bundle Leaving Soon",
			subtitle: nil,
			body: truncateText(body, limit: maxBodyLength),
			routeExpandNightMarket: false
		)
	}
	
	static func nightMarketLive(
		offerCount: Int,
		maxDiscountPercent: Int,
		remainingDuration: TimeInterval,
		wishlistMatches: [(name: String, discount: Int)]
	) -> NotificationPreviewContent {
		let endsText = shortDurationText(remainingDuration)
		let body: String
		if let firstMatch = wishlistMatches.first {
			let firstText = "\(firstMatch.name) (-\(firstMatch.discount)%)"
			let matchSummary: String
			if wishlistMatches.count > 1 {
				matchSummary = "\(firstText) +\(wishlistMatches.count - 1) more"
			} else {
				matchSummary = firstText
			}
			let candidate = "\(offerCount) discounted skins (\(endsText)) — Wishlist: \(matchSummary)!"
			if candidate.count <= maxBodyLength {
				body = candidate
			} else {
				let prefix = "\(offerCount) discounted skins (\(endsText)) — Wishlist: "
				let available = max(12, maxBodyLength - prefix.count - 1)
				body = "\(prefix)\(truncateText(matchSummary, limit: available))!"
			}
		} else {
			let discountPart = maxDiscountPercent > 0 ? "up to \(maxDiscountPercent)% off, " : ""
			body = "Your Night Market is open with \(offerCount) discounted skins (\(discountPart)\(endsText))."
		}
		
		return NotificationPreviewContent(
			title: "Night Market is Live!",
			subtitle: nil,
			body: truncateText(body, limit: maxBodyLength),
			routeExpandNightMarket: true
		)
	}
	
	static func nightMarketLeavingSoon(remainingHours: Int) -> NotificationPreviewContent {
		let phrase = remainingHoursPhrase(remainingHours)
		return NotificationPreviewContent(
			title: "Night Market Ending Soon",
			subtitle: nil,
			body: "Your Night Market closes in \(phrase) — check your discounted offers before they're gone.",
			routeExpandNightMarket: true
		)
	}
	
	private static func formatWishlistBody(items: [MatchedWishlistOffer]) -> String {
		guard let first = items.first else {
			return "Check today's shop for your wishlisted items."
		}
		
		func fullLabel(_ item: MatchedWishlistOffer) -> String {
			if let price = item.priceText, !price.isEmpty {
				return "\(item.name) (\(price))"
			}
			return item.name
		}
		
		if items.count == 1 {
			let candidate = "\(fullLabel(first)) is in today's shop!"
			if candidate.count <= maxBodyLength {
				return candidate
			}
			let suffix: String
			if let price = first.priceText, !price.isEmpty {
				suffix = " (\(price)) is in today's shop!"
			} else {
				suffix = " is in today's shop!"
			}
			let maxNameLen = max(12, maxBodyLength - suffix.count)
			return "\(truncateText(first.name, limit: maxNameLen))\(suffix)"
		}
		
		if items.count == 2 {
			let second = items[1]
			let detailed = "\(fullLabel(first)) and \(fullLabel(second)) are in today's shop!"
			if detailed.count <= maxBodyLength {
				return detailed
			}
			let namesOnly = "\(first.name) and \(second.name) are in today's shop!"
			if namesOnly.count <= maxBodyLength {
				return namesOnly
			}
			let fallbackSuffix = " and 1 more in today's shop!"
			let maxFirstLen = max(12, maxBodyLength - fallbackSuffix.count)
			return "\(truncateText(fullLabel(first), limit: maxFirstLen))\(fallbackSuffix)"
		}
		
		let second = items[1]
		let remainingAfterTwo = items.count - 2
		let detailed = "\(fullLabel(first)), \(fullLabel(second)), and \(remainingAfterTwo) more in today's shop!"
		if detailed.count <= maxBodyLength {
			return detailed
		}
		let namesOnly = "\(first.name), \(second.name), and \(remainingAfterTwo) more in today's shop!"
		if namesOnly.count <= maxBodyLength {
			return namesOnly
		}
		let remainingAfterOne = items.count - 1
		let singleSuffix = ", and \(remainingAfterOne) more in today's shop!"
		let maxFirstLen = max(12, maxBodyLength - singleSuffix.count)
		return "\(truncateText(first.name, limit: maxFirstLen))\(singleSuffix)"
	}
	
	private static func remainingHoursPhrase(_ hours: Int) -> String {
		if hours >= 48 && hours % 24 == 0 {
			return "\(hours / 24) days"
		}
		if hours == 1 {
			return "1 hour"
		}
		return "\(hours) hours"
	}
	
	private static func shortDurationText(_ seconds: TimeInterval) -> String {
		let totalHours = max(1, Int(seconds / TimeInterval(3_600)))
		if totalHours >= 48 {
			return "ends in \(totalHours / 24)d"
		}
		return "ends in \(totalHours)h"
	}
	
	private static func truncateText(_ text: String, limit: Int) -> String {
		guard text.count > limit else { return text }
		guard limit > 1 else { return String(text.prefix(max(0, limit))) }
		let cutIndex = text.index(text.startIndex, offsetBy: limit - 1)
		let prefixSlice = text[..<cutIndex]
		if let lastSpace = prefixSlice.lastIndex(of: " "),
		   text.distance(from: text.startIndex, to: lastSpace) > limit / 2 {
			return String(prefixSlice[..<lastSpace]) + "…"
		}
		return String(prefixSlice) + "…"
	}
}

@MainActor
final class StoreNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
	static let shared = StoreNotificationManager()
	static let bgRefreshTaskIdentifier = "com.dtl21.Recon-Bolt.shopRefresh"
	
	private enum Prefix {
		static let dailyShop = "reconbolt.shop.daily."
		static let wishlist = "reconbolt.shop.wishlist."
		static let bundleLeaving = "reconbolt.bundle.leaving."
		static let nightMarketLive = "reconbolt.nightmarket.live."
		static let nightMarketLeaving = "reconbolt.nightmarket.leaving."
		static let debug = "reconbolt.debug."
	}
	
	private enum UserInfoKey {
		static let route = "route"
		static let accountID = "accountID"
		static let expandNightMarket = "expandNightMarket"
		static let isTest = "isTest"
	}
	
	private struct PreferencesSnapshot {
		var notifyShopRefresh: Bool
		var notifyWishlistMatch: Bool
		var notifyBundleLeavingSoon: Bool
		var notifyNightMarket: Bool
		var leadTimeHours: Int
		var notifyAllAccounts: Bool
		
		var anyEnabled: Bool {
			notifyShopRefresh || notifyWishlistMatch || notifyBundleLeavingSoon || notifyNightMarket
		}
	}
	
	private struct ColdAccountStorage {
		@UserDefault("AccountManager.activeAccount", defaults: .shared)
		var activeAccount: User.ID?
		@UserDefault("AccountManager.storedAccounts", defaults: .shared)
		var storedAccounts: [User.ID] = []
		@UserDefault("AccountManager.clientVersion", defaults: .shared)
		var clientVersion: String?
	}
	
	enum NotificationTestError: LocalizedError {
		case permissionDenied
		
		var errorDescription: String? {
			switch self {
			case .permissionDenied:
				return "Notification permission is blocked for Recon Bolt Revived. Enable it in iOS Settings > Notifications."
			}
		}
	}
	
	@Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
	@Published private(set) var backgroundRefreshStatus: UIBackgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
	@Published private(set) var pendingRequests: [ScheduledNotificationSummary] = []
	@Published private(set) var state: StoreNotificationState = .init()
	@Published private(set) var pendingRoute: NotificationRoute?
	@Published private(set) var isCheckingStore = false
	@Published private(set) var lastManualReport: StoreCheckReport?
	
	private let center = UNUserNotificationCenter.current()
	private let stateFilename = "StoreNotifications.v1.json"
	private var didRegisterBackgroundTasks = false
	private var hasLoadedState = false
	private var hasSyncedSchedulesThisSession = false
	private var hasPopulatedPendingRequests = false
	private var isSyncingSchedules = false
	private var needsScheduleResync = false
	private var lastSubmittedBGDate: Date?
	private var loadStateTask: Task<Void, Never>?
	
	private weak var accountManager: AccountManager?
	private weak var assetManager: AssetManager?
	private weak var settings: AppSettings?
	private weak var wishlistManager: WishlistManager?
	private weak var shopHistoryStore: ShopHistoryStore?
	
	private nonisolated static let utcDayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)!
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	private override init() {
		super.init()
		center.delegate = self
	}
	
	func configure(
		accountManager: AccountManager,
		assetManager: AssetManager,
		settings: AppSettings,
		wishlistManager: WishlistManager,
		shopHistoryStore: ShopHistoryStore
	) {
		self.accountManager = accountManager
		self.assetManager = assetManager
		self.settings = settings
		self.wishlistManager = wishlistManager
		self.shopHistoryStore = shopHistoryStore
	}
	
	func registerBackgroundTasks() {
		center.delegate = self
		guard !didRegisterBackgroundTasks else { return }
		didRegisterBackgroundTasks = true
		
		BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgRefreshTaskIdentifier, using: nil) { task in
			guard let refreshTask = task as? BGAppRefreshTask else {
				task.setTaskCompleted(success: false)
				return
			}
			Task { @MainActor in
				StoreNotificationManager.shared.handleBackgroundRefreshTask(refreshTask)
			}
		}
	}
	
	func handleAppLaunch() async {
		await ensureStateLoaded()
		await refreshStatus()
		await syncSchedules()
	}
	
	func handleDidEnterBackground() {
		final class BackgroundTaskToken: @unchecked Sendable {
			private let lock = NSLock()
			private var identifier: UIBackgroundTaskIdentifier = .invalid
			
			func set(_ id: UIBackgroundTaskIdentifier) {
				lock.lock()
				identifier = id
				lock.unlock()
			}
			
			@MainActor
			func endIfNeeded() {
				lock.lock()
				let id = identifier
				identifier = .invalid
				lock.unlock()
				guard id != .invalid else { return }
				UIApplication.shared.endBackgroundTask(id)
			}
		}
		
		let token = BackgroundTaskToken()
		let taskID = UIApplication.shared.beginBackgroundTask(withName: "SyncStoreNotifications") {
			token.endIfNeeded()
		}
		token.set(taskID)
		
		Task { @MainActor in
			await ensureStateLoaded()
			await syncSchedules()
			token.endIfNeeded()
		}
	}
	
	func refreshStatus() async {
		let notificationSettings = await center.notificationSettings()
		if authorizationStatus != notificationSettings.authorizationStatus {
			authorizationStatus = notificationSettings.authorizationStatus
		}
		let bgStatus = UIApplication.shared.backgroundRefreshStatus
		if backgroundRefreshStatus != bgStatus {
			backgroundRefreshStatus = bgStatus
		}
		
		let requests = await center.pendingNotificationRequests()
		let mapped = Self.summarizeRequests(requests)
		if pendingRequests != mapped {
			pendingRequests = mapped
		}
		hasPopulatedPendingRequests = true
	}
	
	@discardableResult
	func requestAuthorizationIfNeeded() async -> Bool {
		let current = await center.notificationSettings().authorizationStatus
		authorizationStatus = current
		switch current {
		case .authorized, .provisional, .ephemeral:
			return true
		case .denied:
			return false
		case .notDetermined:
			let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
			await refreshStatus()
			return granted
		@unknown default:
			return false
		}
	}
	
	func consumePendingRoute() -> NotificationRoute? {
		defer { pendingRoute = nil }
		return pendingRoute
	}
	
	func processObservedStorefront(
		_ storefront: Storefront,
		for accountID: User.ID,
		fetchDate: Date,
		assets: AssetCollection?,
		wishlistEntries: [WishlistEntry],
		isBackground: Bool
	) async {
		await ensureStateLoaded()
		
		var nextState = state
		
		let remainingDaily = storefront.dailySkinStore.remainingDuration
		if remainingDaily > 0 && remainingDaily <= TimeInterval(172_800) {
			let newRefreshDate = Self.quantizedToMinute(fetchDate.addingTimeInterval(remainingDaily))
			if let existing = nextState.lastKnownDailyRefreshDate,
			   abs(existing.timeIntervalSince(newRefreshDate)) <= 120 {
				// Keep existing timestamp to avoid sub-minute jitter across refreshes.
			} else {
				nextState.lastKnownDailyRefreshDate = newRefreshDate
			}
		}
		
		let rotationKey = ShopHistoryStore.rotationKey(now: fetchDate, remainingDuration: remainingDaily)
		
		let bundles: [TrackedBundle] = storefront.featuredBundle.bundles.compactMap { bundle in
			guard bundle.remainingDuration > 0 else { return nil }
			let name = assets?.bundles[bundle.assetID]?.displayName ?? "Featured Bundle"
			let totalVP = bundle.items.lazy.map(\.discountedPrice).reduce(0, +)
			return TrackedBundle(
				id: bundle.id.description,
				name: name,
				expiryDate: Self.quantizedToMinute(fetchDate.addingTimeInterval(bundle.remainingDuration)),
				totalVP: totalVP
			)
		}
		nextState.trackedBundles = bundles
		
		let activeBundleIDs = Set(bundles.map(\.id))
		nextState.notifiedLeavingBundleIDs = nextState.notifiedLeavingBundleIDs.intersection(activeBundleIDs)
		
		if let nm = storefront.nightMarket, nm.remainingDuration > 0 {
			nextState.trackedNightMarketExpiry = Self.quantizedToMinute(fetchDate.addingTimeInterval(nm.remainingDuration))
		} else {
			nextState.trackedNightMarketExpiry = nil
		}
		
		if !isBackground {
			let dailyID = Prefix.dailyShop + rotationKey
			if nextState.lastDailyRotationSeenOrNotified != rotationKey {
				center.removePendingNotificationRequests(withIdentifiers: [dailyID])
			}
			nextState.lastDailyRotationSeenOrNotified = rotationKey
			if let nm = storefront.nightMarket, nm.remainingDuration > 0 {
				let nmExpiry = fetchDate.addingTimeInterval(nm.remainingDuration)
				nextState.lastNightMarketLiveWindowNotified = Self.nightMarketWindowKey(for: nmExpiry)
			}
		}
		
		let stateChanged = nextState != state
		if stateChanged {
			state = nextState
			persistState()
		}
		if stateChanged || !hasSyncedSchedulesThisSession {
			await syncSchedules()
		}
	}
	
	func syncSchedules() async {
		if isSyncingSchedules {
			needsScheduleResync = true
			return
		}
		isSyncingSchedules = true
		defer { isSyncingSchedules = false }
		
		repeat {
			needsScheduleResync = false
			await performSyncSchedules()
		} while needsScheduleResync
	}
	
	private func performSyncSchedules() async {
		await ensureStateLoaded()
		
		let prefs = readPreferences()
		let settingsStatus = await center.notificationSettings().authorizationStatus
		if authorizationStatus != settingsStatus {
			authorizationStatus = settingsStatus
		}
		let bgStatus = UIApplication.shared.backgroundRefreshStatus
		if backgroundRefreshStatus != bgStatus {
			backgroundRefreshStatus = bgStatus
		}
		
		let existingRequests = await center.pendingNotificationRequests()
		let managedRequests = existingRequests.filter { Self.isManagedIdentifier($0.identifier) }
		let existingByID = Dictionary(managedRequests.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		
		let isAuthorized: Bool
		switch settingsStatus {
		case .authorized, .provisional, .ephemeral:
			isAuthorized = true
		default:
			isAuthorized = false
		}
		
		guard isAuthorized, prefs.anyEnabled else {
			let managedIDs = managedRequests.map(\.identifier)
			if !managedIDs.isEmpty {
				center.removePendingNotificationRequests(withIdentifiers: managedIDs)
			}
			if !hasSyncedSchedulesThisSession || lastSubmittedBGDate != nil {
				BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgRefreshTaskIdentifier)
				lastSubmittedBGDate = nil
			}
			if !managedIDs.isEmpty || !hasPopulatedPendingRequests {
				await refreshStatus()
			}
			hasSyncedSchedulesThisSession = true
			return
		}
		
		var nextState = state
		let now = Date()
		let baseNextRefresh = nextDailyRefreshDate(after: now)
		var desiredRequests: [(id: String, request: UNNotificationRequest, fireDate: Date)] = []
		
		if prefs.notifyShopRefresh {
			let graceDelay: TimeInterval = prefs.notifyWishlistMatch ? TimeInterval(180) : TimeInterval(5)
			let preview = StoreNotificationContentBuilder.shopRefresh()
			var utcCalendar = Calendar(identifier: .gregorian)
			utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
			
			for dayOffset in 0..<14 {
				let refreshDate = baseNextRefresh.addingTimeInterval(TimeInterval(dayOffset) * TimeInterval(86_400))
				let dayKey = ShopHistoryStore.rotationKey(
					now: refreshDate.addingTimeInterval(TimeInterval(60)),
					remainingDuration: TimeInterval(86_340)
				)
				if dayKey == nextState.lastDailyRotationSeenOrNotified {
					continue
				}
				let fireDate = refreshDate.addingTimeInterval(graceDelay)
				guard fireDate > now else { continue }
				
				let components = utcCalendar.dateComponents(
					[.timeZone, .year, .month, .day, .hour, .minute, .second],
					from: fireDate
				)
				let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
				let content = makeNotificationContent(from: preview, accountID: nil, isTest: false)
				let identifier = Prefix.dailyShop + dayKey
				let request = UNNotificationRequest(
					identifier: identifier,
					content: content,
					trigger: trigger
				)
				desiredRequests.append((id: identifier, request: request, fireDate: fireDate))
				nextState.scheduledDailyFireDates[dayKey] = fireDate
			}
			Self.pruneSignatureCaches(in: &nextState)
		}
		
		let leadSeconds = TimeInterval(max(1, prefs.leadTimeHours)) * TimeInterval(3_600)
		
		if prefs.notifyBundleLeavingSoon {
			for bundle in nextState.trackedBundles where bundle.expiryDate > now {
				if nextState.notifiedLeavingBundleIDs.contains(bundle.id) {
					continue
				}
				let fireDate = bundle.expiryDate.addingTimeInterval(-leadSeconds)
				guard fireDate > now else { continue }
				
				let preview = StoreNotificationContentBuilder.bundleLeavingSoon(
					name: bundle.name,
					totalVP: bundle.totalVP,
					remainingHours: prefs.leadTimeHours
				)
				let identifier = Prefix.bundleLeaving + bundle.id
				let request = UNNotificationRequest(
					identifier: identifier,
					content: makeNotificationContent(from: preview, accountID: nil, isTest: false),
					trigger: calendarTrigger(for: fireDate)
				)
				desiredRequests.append((id: identifier, request: request, fireDate: fireDate))
			}
		}
		
		if prefs.notifyNightMarket, let nmExpiry = nextState.trackedNightMarketExpiry, nmExpiry > now {
			let fireDate = nmExpiry.addingTimeInterval(-leadSeconds)
			if fireDate > now {
				let windowKey = Self.nightMarketWindowKey(for: nmExpiry)
				let preview = StoreNotificationContentBuilder.nightMarketLeavingSoon(remainingHours: prefs.leadTimeHours)
				let identifier = Prefix.nightMarketLeaving + windowKey
				let request = UNNotificationRequest(
					identifier: identifier,
					content: makeNotificationContent(from: preview, accountID: nil, isTest: false),
					trigger: calendarTrigger(for: fireDate)
				)
				desiredRequests.append((id: identifier, request: request, fireDate: fireDate))
			}
		}
		
		let desiredIDs = Set(desiredRequests.map(\.id))
		var idsToRemove = existingByID.keys.filter { !desiredIDs.contains($0) }
		var requestsToAdd: [UNNotificationRequest] = []
		
		for desired in desiredRequests {
			if let existing = existingByID[desired.id],
			   Self.requestMatches(existing, desiredRequest: desired.request, desiredFireDate: desired.fireDate) {
				continue
			}
			if existingByID[desired.id] != nil {
				idsToRemove.append(desired.id)
			}
			requestsToAdd.append(desired.request)
		}
		
		if !idsToRemove.isEmpty {
			center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
		}
		for request in requestsToAdd {
			try? await center.add(request)
		}
		
		if prefs.notifyWishlistMatch || prefs.notifyNightMarket || prefs.notifyBundleLeavingSoon {
			let currentUTCRotationKey = ShopHistoryStore.rotationKey(
				now: now,
				remainingDuration: baseNextRefresh.timeIntervalSince(now)
			)
			let earliestDate: Date
			if nextState.lastDailyRotationSeenOrNotified != currentUTCRotationKey {
				earliestDate = now.addingTimeInterval(TimeInterval(15 * 60))
			} else {
				earliestDate = baseNextRefresh.addingTimeInterval(TimeInterval(20))
			}
			scheduleBackgroundRefresh(earliestBeginDate: earliestDate, into: &nextState)
		} else if !hasSyncedSchedulesThisSession || lastSubmittedBGDate != nil {
			BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgRefreshTaskIdentifier)
			lastSubmittedBGDate = nil
		}
		
		if nextState != state {
			state = nextState
			persistState()
		}
		
		if !idsToRemove.isEmpty || !requestsToAdd.isEmpty || !hasPopulatedPendingRequests {
			await refreshStatus()
		}
		hasSyncedSchedulesThisSession = true
	}
	
	func performStoreCheck(
		source: StoreCheckSource,
		forceNotifyForDiagnostics: Bool = false
	) async -> StoreCheckReport {
		await ensureStateLoaded()
		
		let now = Date()
		let prefs = readPreferences()
		let assets = await resolveAssetsForCheck()
		let wishlistEntries = await resolveWishlistEntriesForCheck()
		let (targetAccountIDs, clientVersion) = resolveTargetAccounts(prefs: prefs)
		
		var activeSessionCancellables: [AnyCancellable] = []
		var accountsSucceeded = 0
		var errors: [String] = []
		var allMatches: [MatchedWishlistOffer] = []
		var seenAccessoryKeys: Set<String> = []
		var matchAccountNames: [String] = []
		var latestRotationKey: String?
		var latestDailyRefresh: Date?
		var latestBundles: [TrackedBundle] = []
		var latestNightMarket: (market: Storefront.NightMarket, expiry: Date, windowKey: String, accountID: User.ID)?
		var nmWishlistMatchesBySkin: [String: (name: String, discount: Int)] = [:]
		var nmRouteAccountID: User.ID?
		var firstMatchedAccountID: User.ID?
		var updatedWishlistSignatures: [String: String] = [:]
		var updatedAccessorySignatures: [String: String] = [:]
		var notificationsPosted: [String] = []
		
		for accountID in targetAccountIDs {
			guard let client = makeClientForCheck(
				accountID: accountID,
				clientVersion: clientVersion,
				cancellables: &activeSessionCancellables
			) else {
				errors.append("Missing stored session for \(accountID.description.prefix(8))…")
				continue
			}
			
			do {
				let storefront = try await client.getStorefront()
				accountsSucceeded += 1
				
				shopHistoryStore?.record(storefront: storefront, for: accountID)
				
				let remainingDaily = storefront.dailySkinStore.remainingDuration
				if remainingDaily > 0 && remainingDaily <= TimeInterval(172_800) {
					let refreshAt = now.addingTimeInterval(remainingDaily)
					if latestDailyRefresh == nil || refreshAt > latestDailyRefresh! {
						latestDailyRefresh = refreshAt
					}
				}
				
				let rotationKey = ShopHistoryStore.rotationKey(now: now, remainingDuration: remainingDaily)
				latestRotationKey = rotationKey
				
				if latestBundles.isEmpty {
					latestBundles = storefront.featuredBundle.bundles.compactMap { bundle in
						guard bundle.remainingDuration > 0 else { return nil }
						let name = assets?.bundles[bundle.assetID]?.displayName ?? "Featured Bundle"
						let totalVP = bundle.items.lazy.map(\.discountedPrice).reduce(0, +)
						return TrackedBundle(
							id: bundle.id.description,
							name: name,
							expiryDate: now.addingTimeInterval(bundle.remainingDuration),
							totalVP: totalVP
						)
					}
				}
				
				if let nm = storefront.nightMarket, nm.remainingDuration > 0 {
					if latestNightMarket == nil {
						let expiry = now.addingTimeInterval(nm.remainingDuration)
						latestNightMarket = (nm, expiry, Self.nightMarketWindowKey(for: expiry), accountID)
					}
					let nmMatches = Self.matchingNightMarketOffers(
						in: nm,
						wishlistEntries: wishlistEntries,
						assets: assets
					)
					if !nmMatches.isEmpty, nmRouteAccountID == nil {
						nmRouteAccountID = accountID
					}
					for match in nmMatches {
						if let existing = nmWishlistMatchesBySkin[match.name] {
							if match.discount > existing.discount {
								nmWishlistMatchesBySkin[match.name] = match
							}
						} else {
							nmWishlistMatchesBySkin[match.name] = match
						}
					}
				}
				
				let accountName = await resolveAccountDisplayName(for: accountID)
				
				let dailyMatches = Self.matchingDailyOffers(
					in: storefront,
					wishlistEntries: wishlistEntries,
					assets: assets,
					accountID: accountID,
					accountName: targetAccountIDs.count > 1 ? accountName : nil
				)
				
				let dailySigKey = "\(accountID.description)|\(rotationKey)"
				let dailySig = dailyMatches.map(\.name).sorted().joined(separator: "|")
				let alreadyNotifiedDailySig = state.lastWishlistNotifiedSignatures[dailySigKey]
				let shouldIncludeDaily = forceNotifyForDiagnostics || alreadyNotifiedDailySig != dailySig
				if !dailyMatches.isEmpty && shouldIncludeDaily {
					updatedWishlistSignatures[dailySigKey] = dailySig
					allMatches.append(contentsOf: dailyMatches)
					if firstMatchedAccountID == nil {
						firstMatchedAccountID = accountID
					}
					if targetAccountIDs.count > 1, !matchAccountNames.contains(accountName) {
						matchAccountNames.append(accountName)
					}
				}
				
				let accessoryMatches = Self.matchingAccessoryOffers(
					in: storefront,
					wishlistEntries: wishlistEntries,
					assets: assets,
					accountID: accountID,
					accountName: targetAccountIDs.count > 1 ? accountName : nil
				)
				if !accessoryMatches.isEmpty, storefront.accessoryStore.remainingDuration > 0 {
					let accExpiry = now.addingTimeInterval(storefront.accessoryStore.remainingDuration)
					let accKey = "\(accountID.description)|\(Self.nightMarketWindowKey(for: accExpiry))"
					let accSig = accessoryMatches.map(\.name).sorted().joined(separator: "|")
					let prevAccSig = state.lastAccessoryNotifiedSignatures[accKey]
					if forceNotifyForDiagnostics || prevAccSig != accSig {
						updatedAccessorySignatures[accKey] = accSig
						for match in accessoryMatches where seenAccessoryKeys.insert(match.name).inserted {
							allMatches.append(match)
						}
						if firstMatchedAccountID == nil {
							firstMatchedAccountID = accountID
						}
						if targetAccountIDs.count > 1, !matchAccountNames.contains(accountName) {
							matchAccountNames.append(accountName)
						}
					}
				}
			} catch {
				errors.append(error.localizedDescription)
			}
		}
		
		_ = activeSessionCancellables
		
		if let latestDailyRefresh {
			state.lastKnownDailyRefreshDate = latestDailyRefresh
		}
		if !latestBundles.isEmpty {
			state.trackedBundles = latestBundles
			let activeBundleIDs = Set(latestBundles.map(\.id))
			state.notifiedLeavingBundleIDs = state.notifiedLeavingBundleIDs.intersection(activeBundleIDs)
		}
		if let latestNightMarket {
			state.trackedNightMarketExpiry = latestNightMarket.expiry
		} else if accountsSucceeded > 0 {
			state.trackedNightMarketExpiry = nil
		}
		
		let authStatus = await center.notificationSettings().authorizationStatus
		authorizationStatus = authStatus
		let isAuthorized: Bool
		switch authStatus {
		case .authorized, .provisional, .ephemeral:
			isAuthorized = true
		default:
			isAuthorized = false
		}
		
		let canPostAlerts = isAuthorized && (source == .backgroundRefresh || forceNotifyForDiagnostics)
		let dedupedMatches = Self.deduplicateMatchedOffers(allMatches)
		
		let pendingIDs = Set((await center.pendingNotificationRequests()).map(\.identifier))
		let deliveredIDs = Set((await center.deliveredNotifications()).map(\.request.identifier))
		var immediateRequests: [UNNotificationRequest] = []
		var deliveredIDsToRemove: [String] = []
		
		if canPostAlerts, let rotationKey = latestRotationKey {
			let dailyID = Prefix.dailyShop + rotationKey
			if (prefs.notifyWishlistMatch || forceNotifyForDiagnostics), !dedupedMatches.isEmpty {
				deliveredIDsToRemove.append(dailyID)
				
				let preview = StoreNotificationContentBuilder.wishlistMatch(
					items: dedupedMatches,
					accountNames: matchAccountNames
				)
				let requestID = forceNotifyForDiagnostics
					? "\(Prefix.debug)wishlist.\(UUID().uuidString.prefix(8))"
					: "\(Prefix.wishlist)\(rotationKey)"
				let content = makeNotificationContent(
					from: preview,
					accountID: firstMatchedAccountID,
					isTest: forceNotifyForDiagnostics
				)
				immediateRequests.append(UNNotificationRequest(identifier: requestID, content: content, trigger: nil))
				notificationsPosted.append(preview.title)
				
				if !forceNotifyForDiagnostics {
					state.lastDailyRotationSeenOrNotified = rotationKey
					for (k, v) in updatedWishlistSignatures {
						state.lastWishlistNotifiedSignatures[k] = v
					}
					for (k, v) in updatedAccessorySignatures {
						state.lastAccessoryNotifiedSignatures[k] = v
					}
				}
			} else if prefs.notifyShopRefresh,
					  source == .backgroundRefresh,
					  state.lastDailyRotationSeenOrNotified != rotationKey {
				let scheduledAlreadyFired = state.scheduledDailyFireDates[rotationKey].map { $0 <= now } ?? false
				let shouldDeliverGeneric = pendingIDs.contains(dailyID)
					|| (!deliveredIDs.contains(dailyID) && !scheduledAlreadyFired)
				if shouldDeliverGeneric {
					let preview = StoreNotificationContentBuilder.shopRefresh()
					let content = makeNotificationContent(from: preview, accountID: nil, isTest: false)
					immediateRequests.append(UNNotificationRequest(identifier: dailyID, content: content, trigger: nil))
					notificationsPosted.append(preview.title)
				}
				state.lastDailyRotationSeenOrNotified = rotationKey
			}
		}
		
		if canPostAlerts,
		   let nmInfo = latestNightMarket,
		   (prefs.notifyNightMarket || forceNotifyForDiagnostics),
		   (forceNotifyForDiagnostics || state.lastNightMarketLiveWindowNotified != nmInfo.windowKey) {
			let nmWishlistMatches = Array(nmWishlistMatchesBySkin.values).sorted { $0.discount > $1.discount }
			let maxDiscount = nmInfo.market.offers.map(\.discountPercent).max() ?? 0
			let preview = StoreNotificationContentBuilder.nightMarketLive(
				offerCount: nmInfo.market.offers.count,
				maxDiscountPercent: maxDiscount,
				remainingDuration: nmInfo.market.remainingDuration,
				wishlistMatches: nmWishlistMatches
			)
			let requestID = forceNotifyForDiagnostics
				? "\(Prefix.debug)nightmarket.\(UUID().uuidString.prefix(8))"
				: "\(Prefix.nightMarketLive)\(nmInfo.windowKey)"
			let content = makeNotificationContent(
				from: preview,
				accountID: nmRouteAccountID ?? nmInfo.accountID,
				isTest: forceNotifyForDiagnostics
			)
			immediateRequests.append(UNNotificationRequest(identifier: requestID, content: content, trigger: nil))
			notificationsPosted.append(preview.title)
			if !forceNotifyForDiagnostics {
				state.lastNightMarketLiveWindowNotified = nmInfo.windowKey
			}
		}
		
		if canPostAlerts, prefs.notifyBundleLeavingSoon, source == .backgroundRefresh {
			let leadSeconds = TimeInterval(max(1, prefs.leadTimeHours)) * TimeInterval(3_600)
			for bundle in latestBundles {
				let remaining = bundle.expiryDate.timeIntervalSince(now)
				guard remaining >= TimeInterval(3_600),
					  remaining <= leadSeconds,
					  !state.notifiedLeavingBundleIDs.contains(bundle.id) else {
					continue
				}
				let remainingHours = max(1, Int((remaining / TimeInterval(3_600)).rounded()))
				let preview = StoreNotificationContentBuilder.bundleLeavingSoon(
					name: bundle.name,
					totalVP: bundle.totalVP,
					remainingHours: remainingHours
				)
				let content = makeNotificationContent(from: preview, accountID: nil, isTest: false)
				let reqID = Prefix.bundleLeaving + bundle.id
				immediateRequests.append(UNNotificationRequest(identifier: reqID, content: content, trigger: nil))
				notificationsPosted.append(preview.title)
				state.notifiedLeavingBundleIDs.insert(bundle.id)
			}
		}
		
		pruneSignatureCaches()
		
		if accountsSucceeded > 0, shopHistoryStore != nil {
			shopHistoryStore?.recordDailyCheck(accountCount: accountsSucceeded)
		}
		
		let summaryParts = [
			"\(accountsSucceeded)/\(targetAccountIDs.count) accounts",
			dedupedMatches.isEmpty ? "no wishlist hits" : "\(dedupedMatches.count) wishlist match(es)",
			notificationsPosted.isEmpty ? "0 alerts sent" : "sent: \(notificationsPosted.joined(separator: ", "))",
		]
		state.lastBackgroundCheckAt = now
		state.lastBackgroundCheckSource = source.rawValue
		state.lastBackgroundCheckSummary = summaryParts.joined(separator: " · ")
		persistState()
		
		await syncSchedules()
		
		if !deliveredIDsToRemove.isEmpty {
			center.removeDeliveredNotifications(withIdentifiers: deliveredIDsToRemove)
		}
		for request in immediateRequests {
			try? await center.add(request)
		}
		await refreshStatus()
		
		let report = StoreCheckReport(
			checkedAt: now,
			source: source,
			accountsAttempted: targetAccountIDs.count,
			accountsSucceeded: accountsSucceeded,
			rotationKey: latestRotationKey,
			nextDailyRefresh: latestDailyRefresh,
			wishlistMatchNames: dedupedMatches.map(\.name),
			activeBundleNames: latestBundles.map(\.name),
			nightMarketActive: latestNightMarket != nil,
			notificationsPosted: notificationsPosted,
			errors: errors
		)
		if source == .manualDiagnostic {
			lastManualReport = report
		}
		return report
	}
	
	func previewContent(for kind: TestNotificationKind) -> NotificationPreviewContent {
		let prefs = readPreferences()
		let realSkins = realWishlistSampleNames()
		let primarySkin = realSkins.first ?? "Reaver Vandal"
		let secondarySkin = realSkins.dropFirst().first ?? "Kuronami Vandal"
		let tertiarySkin = realSkins.dropFirst(2).first ?? "Prime Phantom"
		let fourthSkin = realSkins.dropFirst(3).first ?? "RGX 11z Pro Butterfly Knife"
		let bundleSample = state.trackedBundles.first
		
		switch kind {
		case .shopRefresh:
			return StoreNotificationContentBuilder.shopRefresh()
		case .wishlistSingle:
			return StoreNotificationContentBuilder.wishlistMatch(
				items: [MatchedWishlistOffer(name: primarySkin, priceText: "1,775 VP", accountName: nil, accountID: nil, isAccessory: false)],
				accountNames: []
			)
		case .wishlistMultiple:
			return StoreNotificationContentBuilder.wishlistMatch(
				items: [
					MatchedWishlistOffer(name: primarySkin, priceText: "1,775 VP", accountName: nil, accountID: nil, isAccessory: false),
					MatchedWishlistOffer(name: secondarySkin, priceText: "2,375 VP", accountName: nil, accountID: nil, isAccessory: false),
					MatchedWishlistOffer(name: tertiarySkin, priceText: "1,775 VP", accountName: nil, accountID: nil, isAccessory: false),
					MatchedWishlistOffer(name: fourthSkin, priceText: "4,350 VP", accountName: nil, accountID: nil, isAccessory: false),
				],
				accountNames: accountManager?.storedAccounts.count ?? 0 > 1 ? ["Main", "Alt"] : []
			)
		case .bundleLeavingSoon:
			return StoreNotificationContentBuilder.bundleLeavingSoon(
				name: bundleSample?.name ?? "Kuronami",
				totalVP: bundleSample?.totalVP ?? 9_500,
				remainingHours: prefs.leadTimeHours
			)
		case .nightMarketLive:
			return StoreNotificationContentBuilder.nightMarketLive(
				offerCount: 6,
				maxDiscountPercent: 45,
				remainingDuration: TimeInterval(14 * 86_400),
				wishlistMatches: [(name: primarySkin, discount: 37)]
			)
		case .nightMarketLeavingSoon:
			return StoreNotificationContentBuilder.nightMarketLeavingSoon(remainingHours: prefs.leadTimeHours)
		}
	}
	
	func scheduleTestNotification(
		kind: TestNotificationKind,
		delay: TestNotificationDelay
	) async throws -> Date {
		let granted = await requestAuthorizationIfNeeded()
		guard granted else {
			throw NotificationTestError.permissionDenied
		}
		
		let preview = previewContent(for: kind)
		let content = makeNotificationContent(
			from: preview,
			accountID: accountManager?.activeAccount?.id,
			isTest: true
		)
		let seconds = TimeInterval(delay.rawValue)
		let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
		let identifier = "\(Prefix.debug)\(kind.rawValue).\(UUID().uuidString.prefix(8))"
		let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
		try await center.add(request)
		
		await refreshStatus()
		return Date().addingTimeInterval(seconds)
	}
	
	func cancelTestNotifications() async {
		let pending = await center.pendingNotificationRequests()
		let debugIDs = pending.map(\.identifier).filter { $0.hasPrefix(Prefix.debug) }
		if !debugIDs.isEmpty {
			center.removePendingNotificationRequests(withIdentifiers: debugIDs)
		}
		await refreshStatus()
	}
	
	func runDiagnosticStoreCheck(postAlertsIfFound: Bool) async -> StoreCheckReport? {
		guard !isCheckingStore else { return nil }
		isCheckingStore = true
		defer { isCheckingStore = false }
		return await performStoreCheck(
			source: .manualDiagnostic,
			forceNotifyForDiagnostics: postAlertsIfFound
		)
	}
	
	// MARK: - UNUserNotificationCenterDelegate
	
	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([.banner, .list, .sound])
	}
	
	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let userInfo = response.notification.request.content.userInfo
		let route = userInfo[UserInfoKey.route] as? String
		let accountIDString = userInfo[UserInfoKey.accountID] as? String
		let expandNightMarket = (userInfo[UserInfoKey.expandNightMarket] as? Bool) ?? false
		
		Task { @MainActor in
			if route == "store" {
				let accountID = accountIDString.flatMap { User.ID($0) }
				self.pendingRoute = NotificationRoute(
					id: UUID(),
					accountID: accountID,
					expandNightMarket: expandNightMarket
				)
			}
			completionHandler()
		}
	}
	
	// MARK: - Background Refresh Task
	
	private func handleBackgroundRefreshTask(_ task: BGAppRefreshTask) {
		var didComplete = false
		let lock = NSLock()
		func finish(success: Bool) {
			lock.lock()
			let alreadyDone = didComplete
			didComplete = true
			lock.unlock()
			guard !alreadyDone else { return }
			task.setTaskCompleted(success: success)
		}
		
		let workTask = Task { @MainActor in
			let report = await self.performStoreCheck(
				source: .backgroundRefresh,
				forceNotifyForDiagnostics: false
			)
			let succeeded = report.accountsSucceeded > 0 || report.accountsAttempted == 0
			finish(success: succeeded)
		}
		
		task.expirationHandler = {
			workTask.cancel()
			Task { @MainActor in
				await StoreNotificationManager.shared.syncSchedules()
				finish(success: false)
			}
		}
	}
	
	private func scheduleBackgroundRefresh(earliestBeginDate: Date, into nextState: inout StoreNotificationState) {
		if let lastSubmittedBGDate,
		   abs(lastSubmittedBGDate.timeIntervalSince(earliestBeginDate)) <= 120,
		   nextState.lastBackgroundScheduleError == nil {
			return
		}
		let request = BGAppRefreshTaskRequest(identifier: Self.bgRefreshTaskIdentifier)
		request.earliestBeginDate = earliestBeginDate
		do {
			try BGTaskScheduler.shared.submit(request)
			lastSubmittedBGDate = earliestBeginDate
			nextState.lastBackgroundScheduleError = nil
		} catch {
			nextState.lastBackgroundScheduleError = error.localizedDescription
		}
	}
	
	// MARK: - Helpers
	
	private static func isManagedIdentifier(_ identifier: String) -> Bool {
		identifier.hasPrefix(Prefix.dailyShop)
			|| identifier.hasPrefix(Prefix.bundleLeaving)
			|| identifier.hasPrefix(Prefix.nightMarketLeaving)
	}
	
	private static func quantizedToMinute(_ date: Date) -> Date {
		Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
	}
	
	private static func nextTriggerDate(for request: UNNotificationRequest) -> Date? {
		if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger {
			return calendarTrigger.nextTriggerDate()
		} else if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
			return intervalTrigger.nextTriggerDate()
		}
		return nil
	}
	
	private static func summarizeRequests(_ requests: [UNNotificationRequest]) -> [ScheduledNotificationSummary] {
		requests.map { request in
			let isTest = (request.content.userInfo[UserInfoKey.isTest] as? Bool) == true
				|| request.identifier.hasPrefix(Prefix.debug)
			return ScheduledNotificationSummary(
				id: request.identifier,
				title: request.content.title,
				subtitle: request.content.subtitle.isEmpty ? nil : request.content.subtitle,
				body: request.content.body,
				nextTriggerDate: nextTriggerDate(for: request),
				isTest: isTest
			)
		}
		.sorted { lhs, rhs in
			switch (lhs.nextTriggerDate, rhs.nextTriggerDate) {
			case let (l?, r?): return l < r
			case (_?, nil): return true
			case (nil, _?): return false
			case (nil, nil): return lhs.id < rhs.id
			}
		}
	}
	
	private static func requestMatches(
		_ existing: UNNotificationRequest,
		desiredRequest: UNNotificationRequest,
		desiredFireDate: Date
	) -> Bool {
		guard existing.content.title == desiredRequest.content.title,
			  existing.content.subtitle == desiredRequest.content.subtitle,
			  existing.content.body == desiredRequest.content.body,
			  let existingDate = nextTriggerDate(for: existing) else {
			return false
		}
		return abs(existingDate.timeIntervalSince(desiredFireDate)) <= 90
	}
	
	private func ensureStateLoaded() async {
		if hasLoadedState { return }
		if let loadStateTask {
			await loadStateTask.value
			return
		}
		let task = Task { @MainActor [weak self] in
			guard let self else { return }
			if let loaded = await LocalJSONStore.loadAsync(StoreNotificationState.self, from: self.stateFilename) {
				self.state = loaded
			}
			self.hasLoadedState = true
		}
		loadStateTask = task
		await task.value
		loadStateTask = nil
	}
	
	private func persistState() {
		LocalJSONStore.save(state, to: stateFilename)
	}
	
	private func pruneSignatureCaches() {
		Self.pruneSignatureCaches(in: &state)
	}
	
	private static func pruneSignatureCaches(in state: inout StoreNotificationState) {
		if state.lastWishlistNotifiedSignatures.count > 14 {
			let sortedKeys = state.lastWishlistNotifiedSignatures.keys.sorted()
			for key in sortedKeys.dropLast(14) {
				state.lastWishlistNotifiedSignatures.removeValue(forKey: key)
			}
		}
		if state.lastAccessoryNotifiedSignatures.count > 14 {
			let sortedKeys = state.lastAccessoryNotifiedSignatures.keys.sorted()
			for key in sortedKeys.dropLast(14) {
				state.lastAccessoryNotifiedSignatures.removeValue(forKey: key)
			}
		}
		if state.scheduledDailyFireDates.count > 20 {
			let sortedKeys = state.scheduledDailyFireDates.keys.sorted()
			for key in sortedKeys.dropLast(20) {
				state.scheduledDailyFireDates.removeValue(forKey: key)
			}
		}
	}
	
	private func readPreferences() -> PreferencesSnapshot {
		if let settings {
			return PreferencesSnapshot(
				notifyShopRefresh: settings.notifyShopRefresh,
				notifyWishlistMatch: settings.notifyWishlistMatch,
				notifyBundleLeavingSoon: settings.notifyBundleLeavingSoon,
				notifyNightMarket: settings.notifyNightMarket,
				leadTimeHours: settings.notificationLeadTimeHours,
				notifyAllAccounts: settings.notifyAllAccounts
			)
		}
		let defaults = UserDefaults.standard
		let leadHours = defaults.object(forKey: AppSettings.NotificationKeys.leadTimeHours) as? Int ?? 24
		let allAccounts = defaults.object(forKey: AppSettings.NotificationKeys.allAccounts) as? Bool ?? true
		return PreferencesSnapshot(
			notifyShopRefresh: defaults.bool(forKey: AppSettings.NotificationKeys.shopRefresh),
			notifyWishlistMatch: defaults.bool(forKey: AppSettings.NotificationKeys.wishlistMatch),
			notifyBundleLeavingSoon: defaults.bool(forKey: AppSettings.NotificationKeys.bundleLeavingSoon),
			notifyNightMarket: defaults.bool(forKey: AppSettings.NotificationKeys.nightMarket),
			leadTimeHours: leadHours,
			notifyAllAccounts: allAccounts
		)
	}
	
	private func makeNotificationContent(
		from preview: NotificationPreviewContent,
		accountID: User.ID?,
		isTest: Bool
	) -> UNMutableNotificationContent {
		let content = UNMutableNotificationContent()
		content.title = preview.title
		if let subtitle = preview.subtitle, !subtitle.isEmpty {
			content.subtitle = subtitle
		}
		content.body = preview.body
		content.sound = .default
		var userInfo: [AnyHashable: Any] = [
			UserInfoKey.route: "store",
			UserInfoKey.expandNightMarket: preview.routeExpandNightMarket,
		]
		if let accountID {
			userInfo[UserInfoKey.accountID] = accountID.description
		}
		if isTest {
			userInfo[UserInfoKey.isTest] = true
		}
		content.userInfo = userInfo
		return content
	}
	
	private func calendarTrigger(for date: Date) -> UNCalendarNotificationTrigger {
		let calendar = Calendar.current
		let components = calendar.dateComponents(
			[.timeZone, .year, .month, .day, .hour, .minute, .second],
			from: date
		)
		return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
	}
	
	private func nextDailyRefreshDate(after now: Date) -> Date {
		if var known = state.lastKnownDailyRefreshDate {
			while known <= now {
				known = known.addingTimeInterval(TimeInterval(86_400))
			}
			return known
		}
		var utcCalendar = Calendar(identifier: .gregorian)
		utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
		let startOfToday = utcCalendar.startOfDay(for: now)
		return utcCalendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(TimeInterval(86_400))
	}
	
	private nonisolated static func nightMarketWindowKey(for expiryDate: Date) -> String {
		let bucketSeconds = TimeInterval(21_600) // 6h rounding avoids midnight clock-skew splits
		let rounded = Date(timeIntervalSince1970: (expiryDate.timeIntervalSince1970 / bucketSeconds).rounded() * bucketSeconds)
		return utcDayFormatter.string(from: rounded)
	}
	
	private func resolveAssetsForCheck() async -> AssetCollection? {
		if let live = assetManager?.assets {
			return live
		}
		return await Task.detached(priority: .userInitiated) {
			AssetManager.loadCachedAssetsFromDisk()
		}.value
	}
	
	private func resolveWishlistEntriesForCheck() async -> [WishlistEntry] {
		if let wishlistManager {
			await wishlistManager.waitUntilLoaded()
			return wishlistManager.entries
		}
		return await LocalJSONStore.loadAsync([WishlistEntry].self, from: "Wishlist.v1.json") ?? []
	}
	
	private func resolveTargetAccounts(prefs: PreferencesSnapshot) -> (accounts: [User.ID], clientVersion: String?) {
		if let accountManager {
			let ids: [User.ID]
			if prefs.notifyAllAccounts {
				ids = accountManager.storedAccounts
			} else if let active = accountManager.activeAccount?.id {
				ids = [active]
			} else if let first = accountManager.storedAccounts.first {
				ids = [first]
			} else {
				ids = []
			}
			return (ids, accountManager.clientVersion)
		}
		
		let storage = ColdAccountStorage()
		let ids: [User.ID]
		if prefs.notifyAllAccounts {
			ids = storage.storedAccounts
		} else if let active = storage.activeAccount {
			ids = [active]
		} else if let first = storage.storedAccounts.first {
			ids = [first]
		} else {
			ids = []
		}
		return (ids, storage.clientVersion)
	}
	
	private func makeClientForCheck(
		accountID: User.ID,
		clientVersion: String?,
		cancellables: inout [AnyCancellable]
	) -> ValorantClient? {
		if let active = accountManager?.activeAccount, active.id == accountID {
			return active.client
		}
		guard let data = try? OSKeychain.instance.loadData(forKey: accountID.rawID.description),
			  let session = try? JSONDecoder().decode(APISession.self, from: data) else {
			return nil
		}
		var client = ValorantClient(session: session)
		if let clientVersion {
			client.clientVersion = clientVersion
		}
		let sub = client.onSessionUpdate { updatedSession in
			guard let encoded = try? JSONEncoder().encode(updatedSession) else { return }
			try? OSKeychain.instance.store(encoded, forKey: accountID.rawID.description)
		}
		cancellables.append(sub)
		return client
	}
	
	private func resolveAccountDisplayName(for accountID: User.ID) async -> String {
		if let user = await LocalDataProvider.shared.userManager.cachedObject(for: accountID),
		   !user.gameName.isEmpty {
			return user.gameName
		}
		return String(accountID.description.prefix(8))
	}
	
	private func realWishlistSampleNames() -> [String] {
		guard let assets = assetManager?.assets,
			  let entries = wishlistManager?.entries,
			  !entries.isEmpty else {
			return []
		}
		var names: [String] = []
		for entry in entries {
			switch entry.kind {
			case .skin:
				if let skin = assets.weapons.values.lazy.flatMap(\.skins).first(where: { $0.id == entry.skinID }) {
					names.append(skin.displayName)
				}
			case .buddy:
				if let buddy = assets.buddies[Weapon.Buddy.ID(rawID: entry.itemID)] {
					names.append(buddy.displayName)
				}
			case .spray:
				if let spray = assets.sprays[Spray.ID(rawID: entry.itemID)] {
					names.append(spray.displayName)
				}
			case .card:
				if let card = assets.playerCards[PlayerCard.ID(rawID: entry.itemID)] {
					names.append(card.displayName)
				}
			case .title:
				if let title = assets.playerTitles[PlayerTitle.ID(rawID: entry.itemID)] {
					names.append(title.titleText ?? title.displayName ?? "Title")
				}
			case .flex:
				if let flex = assets.flex[Totem.ID(rawID: entry.itemID)] {
					names.append(flex.displayName)
				}
			}
			if names.count >= 4 { break }
		}
		return names
	}
	
	private static func matchingDailyOffers(
		in storefront: Storefront,
		wishlistEntries: [WishlistEntry],
		assets: AssetCollection?,
		accountID: User.ID,
		accountName: String?
	) -> [MatchedWishlistOffer] {
		guard let assets else { return [] }
		let wishlistedSkins = Set(wishlistEntries.filter { $0.kind == .skin }.map(\.skinID))
		guard !wishlistedSkins.isEmpty else { return [] }
		
		var results: [MatchedWishlistOffer] = []
		for offer in storefront.dailySkinStore.offers {
			for reward in offer.rewards {
				if let level = reward.skinLevel,
				   let resolved = assets.resolveSkin(level),
				   wishlistedSkins.contains(resolved.skin.id) {
					let priceText = offer.cost[.valorantPoints].map { "\($0.formatted()) VP" }
					results.append(MatchedWishlistOffer(
						name: resolved.skin.displayName,
						priceText: priceText,
						accountName: accountName,
						accountID: accountID,
						isAccessory: false
					))
					break
				}
			}
		}
		return results
	}
	
	private static func matchingAccessoryOffers(
		in storefront: Storefront,
		wishlistEntries: [WishlistEntry],
		assets: AssetCollection?,
		accountID: User.ID,
		accountName: String?
	) -> [MatchedWishlistOffer] {
		guard let assets, let offers = storefront.accessoryStore.offers else { return [] }
		let wishlistedKeys = Set(wishlistEntries.map { "\($0.kind.rawValue)|\($0.itemID)" })
		guard !wishlistedKeys.isEmpty else { return [] }
		
		var results: [MatchedWishlistOffer] = []
		for accOffer in offers {
			let offer = accOffer.offer
			for reward in offer.rewards {
				let matchedName: String?
				if let buddy = reward.buddy,
				   let info = assets.resolveBuddy(buddy),
				   wishlistedKeys.contains("\(WishlistItemKind.buddy.rawValue)|\(info.id.rawID)") {
					matchedName = info.displayName
				} else if let spray = reward.spray,
						  wishlistedKeys.contains("\(WishlistItemKind.spray.rawValue)|\(spray.rawID)") {
					matchedName = assets.sprays[spray]?.displayName ?? "Wishlisted Spray"
				} else if let card = reward.card,
						  wishlistedKeys.contains("\(WishlistItemKind.card.rawValue)|\(card.rawID)") {
					matchedName = assets.playerCards[card]?.displayName ?? "Wishlisted Card"
				} else if let title = reward.title,
						  wishlistedKeys.contains("\(WishlistItemKind.title.rawValue)|\(title.rawID)") {
					matchedName = assets.playerTitles[title]?.titleText ?? assets.playerTitles[title]?.displayName ?? "Wishlisted Title"
				} else if let totem = reward.totem,
						  wishlistedKeys.contains("\(WishlistItemKind.flex.rawValue)|\(totem.rawID)") {
					matchedName = assets.flex[totem]?.displayName ?? "Wishlisted Flex"
				} else {
					matchedName = nil
				}
				
				if let matchedName {
					let priceText = offer.cost[.kingdomCredits].map { "\($0.formatted()) KC" }
					results.append(MatchedWishlistOffer(
						name: matchedName,
						priceText: priceText,
						accountName: accountName,
						accountID: accountID,
						isAccessory: true
					))
					break
				}
			}
		}
		return results
	}
	
	private static func matchingNightMarketOffers(
		in nightMarket: Storefront.NightMarket,
		wishlistEntries: [WishlistEntry],
		assets: AssetCollection?
	) -> [(name: String, discount: Int)] {
		guard let assets else { return [] }
		let wishlistedSkins = Set(wishlistEntries.filter { $0.kind == .skin }.map(\.skinID))
		guard !wishlistedSkins.isEmpty else { return [] }
		
		var matches: [(name: String, discount: Int)] = []
		for offer in nightMarket.offers {
			for reward in offer.offer.rewards {
				if let level = reward.skinLevel,
				   let resolved = assets.resolveSkin(level),
				   wishlistedSkins.contains(resolved.skin.id) {
					matches.append((name: resolved.skin.displayName, discount: offer.discountPercent))
					break
				}
			}
		}
		return matches
	}
	
	private static func deduplicateMatchedOffers(_ items: [MatchedWishlistOffer]) -> [MatchedWishlistOffer] {
		var seen: Set<String> = []
		var result: [MatchedWishlistOffer] = []
		for item in items {
			if seen.insert(item.name).inserted {
				result.append(item)
			}
		}
		return result
	}
}
