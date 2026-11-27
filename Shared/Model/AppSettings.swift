import SwiftUI
import ValorantAPI

final class AppSettings: ObservableObject {
	/// Vantage brand purple, `#842DC8` (sRGB 132, 45, 200).
	static let defaultAccentColor = Color(.sRGB, red: 132 / 255, green: 45 / 255, blue: 200 / 255)
	
	@Published var accentReloadToken = UUID()
	
	@AppStorage("AppSettings.theme")
	var theme = Theme.system
	
	@AppStorage("AppSettings.customAccentColor")
	var customAccentColorComponents = ""
	
	// Interface settings
	@AppStorage("LiveGameBox.shouldAutoShow")
	var autoOpenMatchDetails = false
	
	@AppStorage("vibrateOnMatchFound")
	var vibrateOnMatchFound = true

	@AppStorage("instalock.enabled")
	private var storedInstalockEnabled = false

	/// Locks in ``instalockAgent`` as soon as Agent Select starts. Off by default.
	var instalockEnabled: Bool {
		get { storedInstalockEnabled }
		set {
			objectWillChange.send()
			storedInstalockEnabled = newValue
		}
	}

	@AppStorage("instalock.agentID")
	private var storedInstalockAgentID = ""

	var instalockAgent: Agent.ID? {
		get {
			guard let uuid = LowercaseUUID(storedInstalockAgentID) else { return nil }
			return Agent.ID(rawID: uuid)
		}
		set {
			objectWillChange.send()
			storedInstalockAgentID = newValue.map { $0.rawID.description } ?? ""
		}
	}
	
	@AppStorage("MatchList.isCompact")
	var isCompactListStyle = false
	
	@AppStorage("MatchList.autoDownload")
	var autoDownloadMatches = true
	
	@AppStorage("UserLabel.canCopy")
	var copyPlayerNames = true
	
	@AppStorage("Social.directProfileNavigation")
	var openProfileDirectly = false
	
	@AppStorage("Social.sortOfflineByLastSeen")
	var sortOfflineByLastSeen = true
	
	@AppStorage("Social.friendsSortOrder")
	var friendsSortOrder: FriendsSortOrder = .defaultOrder
	
	// Sign-in settings
	@AppStorage("Login.clearCookiesOnLogin")
	var clearWebSignInDataOnOpen = true
	
	// Auto-delete / Match retention settings
	@AppStorage("MatchRetention.maxAgeDays")
	var matchRetentionDays: Int = 14
	
	@AppStorage("MatchRetention.keepsOwnMatches")
	var keepsOwnMatches = true
	
	@AppStorage("MatchRetention.keepsBookmarkedMatches")
	var keepsBookmarkedMatches = true
	
	@AppStorage("MatchRetention.keepsUnlinkedMatches")
	var keepsUnlinkedMatches = false
	
	// Notification settings
	@AppStorage(NotificationKeys.shopRefresh)
	var notifyShopRefresh = false
	
	@AppStorage(NotificationKeys.wishlistMatch)
	var notifyWishlistMatch = false
	
	@AppStorage(NotificationKeys.bundleLeavingSoon)
	var notifyBundleLeavingSoon = false
	
	@AppStorage(NotificationKeys.nightMarket)
	var notifyNightMarket = false
	
	@AppStorage(NotificationKeys.leadTimeHours)
	var notificationLeadTimeHours: Int = 24
	
	@AppStorage(NotificationKeys.allAccounts)
	var notifyAllAccounts = true
	
	enum NotificationKeys {
		static let shopRefresh = "Notifications.shopRefresh"
		static let wishlistMatch = "Notifications.wishlistMatch"
		static let bundleLeavingSoon = "Notifications.bundleLeavingSoon"
		static let nightMarket = "Notifications.nightMarket"
		static let leadTimeHours = "Notifications.leadTimeHours"
		static let allAccounts = "Notifications.allAccounts"
	}
	
	var anyStoreNotificationEnabled: Bool {
		notifyShopRefresh || notifyWishlistMatch || notifyBundleLeavingSoon || notifyNightMarket
	}
	
	var hasCustomAccentColor: Bool {
		!customAccentColorComponents.isEmpty
	}
	
	private static let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB)
	
	private static func parseRGBComponents(_ raw: String) -> (Double, Double, Double)? {
		guard let firstComma = raw.firstIndex(of: ",") else { return nil }
		let afterFirst = raw.index(after: firstComma)
		guard let secondComma = raw[afterFirst...].firstIndex(of: ",") else { return nil }
		let afterSecond = raw.index(after: secondComma)
		guard !raw[afterSecond...].contains(","),
			  let r = Double(raw[..<firstComma]),
			  let g = Double(raw[afterFirst..<secondComma]),
			  let b = Double(raw[afterSecond...]) else {
			return nil
		}
		return (r, g, b)
	}
	
	var effectiveAccentColor: Color {
		guard let (r, g, b) = Self.parseRGBComponents(customAccentColorComponents) else {
			return Self.defaultAccentColor
		}
		return Self.strictSRGBColor(red: r, green: g, blue: b)
	}
	
	var accentColorBinding: Binding<Color> {
		Binding(
			get: {
				if self.hasCustomAccentColor {
					return self.effectiveAccentColor
				}
				let (r, g, b) = Self.clampedSRGBComponents(from: Self.defaultAccentColor)
				return Self.strictSRGBColor(red: r, green: g, blue: b)
			},
			set: { newValue in
				let (r, g, b) = Self.clampedSRGBComponents(from: newValue)
				let formatted = "\(r),\(g),\(b)"
				guard self.customAccentColorComponents != formatted else { return }
				self.customAccentColorComponents = formatted
			}
		)
	}
	
	private static func clampedSRGBComponents(from color: Color) -> (Double, Double, Double) {
		let cgColor = UIColor(color).cgColor
		if let srgbSpace = sRGBSpace,
		   let converted = cgColor.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
		   let components = converted.components,
		   components.count >= 3
		{
			return (
				min(max(Double(components[0]), Double(0)), Double(1)),
				min(max(Double(components[1]), Double(0)), Double(1)),
				min(max(Double(components[2]), Double(0)), Double(1))
			)
		}
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		if UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
			return (
				min(max(Double(red), Double(0)), Double(1)),
				min(max(Double(green), Double(0)), Double(1)),
				min(max(Double(blue), Double(0)), Double(1))
			)
		}
		return (Double(1), Double(0), Double(0.311))
	}
	
	private static func strictSRGBColor(red: Double, green: Double, blue: Double) -> Color {
		let r = min(max(red, Double(0)), Double(1))
		let g = min(max(green, Double(0)), Double(1))
		let b = min(max(blue, Double(0)), Double(1))
		if let space = sRGBSpace,
		   let cgColor = CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), 1])
		{
			return Color(cgColor: cgColor)
		}
		return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
	}
	
	var pickerSelectedUIColor: UIColor {
		let baseColor = hasCustomAccentColor ? effectiveAccentColor : Self.defaultAccentColor
		let (r, g, b) = Self.clampedSRGBComponents(from: baseColor)
		if let space = Self.sRGBSpace,
		   let cgColor = CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), 1])
		{
			return UIColor(cgColor: cgColor)
		}
		return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
	}
	
	var matchRetentionLabel: String {
		matchRetentionDays <= 0 ? "Off" : "\(matchRetentionDays) Days"
	}
	
	@MainActor
	static func applyGlobalTint(_ color: Color) {
		let uiColor = UIColor(color)
		UIView.appearance().tintColor = uiColor
		UITabBar.appearance().tintColor = uiColor
		UINavigationBar.appearance().tintColor = uiColor
		for scene in UIApplication.shared.connectedScenes {
			guard let windowScene = scene as? UIWindowScene else { continue }
			for window in windowScene.windows {
				window.tintColor = uiColor
				if let root = window.rootViewController {
					applyTintRecursively(uiColor, to: root)
				}
			}
		}
	}
	
	@MainActor
	private static func applyTintRecursively(_ uiColor: UIColor, to vc: UIViewController) {
		vc.viewIfLoaded?.tintColor = uiColor
		if let tabBarController = vc as? UITabBarController {
			tabBarController.tabBar.tintColor = uiColor
			tabBarController.tabBar.setNeedsLayout()
		}
		if let navController = vc as? UINavigationController {
			navController.navigationBar.tintColor = uiColor
			navController.navigationBar.setNeedsLayout()
		}
		for child in vc.children {
			applyTintRecursively(uiColor, to: child)
		}
		if let presented = vc.presentedViewController {
			applyTintRecursively(uiColor, to: presented)
		}
	}
	
	@MainActor
	func setCustomAccentColor(_ uiColor: UIColor) {
		let (r, g, b) = Self.clampedSRGBComponents(from: Color(uiColor))
		let formatted = "\(r),\(g),\(b)"
		guard customAccentColorComponents != formatted else { return }
		customAccentColorComponents = formatted
	}
	
	@MainActor
	func reloadAppForAccentChange() {
		Self.applyGlobalTint(effectiveAccentColor)
		accentReloadToken = UUID()
	}
	
	@MainActor
	func resetAccentColor() {
		if !customAccentColorComponents.isEmpty {
			customAccentColorComponents = ""
		}
		reloadAppForAccentChange()
	}
	
	@MainActor
	func resetAll() {
		if theme != .system { theme = .system }
		if customAccentColorComponents != "" { customAccentColorComponents = "" }
		if autoOpenMatchDetails != false { autoOpenMatchDetails = false }
		if vibrateOnMatchFound != true { vibrateOnMatchFound = true }
		if isCompactListStyle != false { isCompactListStyle = false }
		if autoDownloadMatches != true { autoDownloadMatches = true }
		if copyPlayerNames != true { copyPlayerNames = true }
		if openProfileDirectly != false { openProfileDirectly = false }
		if sortOfflineByLastSeen != true { sortOfflineByLastSeen = true }
		if friendsSortOrder != .defaultOrder { friendsSortOrder = .defaultOrder }
		if clearWebSignInDataOnOpen != true { clearWebSignInDataOnOpen = true }
		if matchRetentionDays != 14 { matchRetentionDays = 14 }
		if keepsOwnMatches != true { keepsOwnMatches = true }
		if keepsBookmarkedMatches != true { keepsBookmarkedMatches = true }
		if keepsUnlinkedMatches != false { keepsUnlinkedMatches = false }
		if notifyShopRefresh != false { notifyShopRefresh = false }
		if notifyWishlistMatch != false { notifyWishlistMatch = false }
		if notifyBundleLeavingSoon != false { notifyBundleLeavingSoon = false }
		if notifyNightMarket != false { notifyNightMarket = false }
		if notificationLeadTimeHours != 24 { notificationLeadTimeHours = 24 }
		if notifyAllAccounts != true { notifyAllAccounts = true }
		reloadAppForAccentChange()
	}
	
	struct BackupSnapshot: Codable, Equatable, Sendable {
		var theme: Theme
		var customAccentColorComponents: String
		var autoOpenMatchDetails: Bool
		var vibrateOnMatchFound: Bool
		var isCompactListStyle: Bool
		var autoDownloadMatches: Bool
		var copyPlayerNames: Bool
		var openProfileDirectly: Bool
		var sortOfflineByLastSeen: Bool
		var friendsSortOrder: FriendsSortOrder
		var clearWebSignInDataOnOpen: Bool
		var matchRetentionDays: Int
		var keepsOwnMatches: Bool
		var keepsBookmarkedMatches: Bool
		var keepsUnlinkedMatches: Bool
		var notifyShopRefresh: Bool
		var notifyWishlistMatch: Bool
		var notifyBundleLeavingSoon: Bool
		var notifyNightMarket: Bool
		var notificationLeadTimeHours: Int
		var notifyAllAccounts: Bool
		
		init(
			theme: Theme,
			customAccentColorComponents: String,
			autoOpenMatchDetails: Bool,
			vibrateOnMatchFound: Bool,
			isCompactListStyle: Bool,
			autoDownloadMatches: Bool,
			copyPlayerNames: Bool,
			openProfileDirectly: Bool,
			sortOfflineByLastSeen: Bool,
			friendsSortOrder: FriendsSortOrder,
			clearWebSignInDataOnOpen: Bool,
			matchRetentionDays: Int,
			keepsOwnMatches: Bool,
			keepsBookmarkedMatches: Bool,
			keepsUnlinkedMatches: Bool,
			notifyShopRefresh: Bool = false,
			notifyWishlistMatch: Bool = false,
			notifyBundleLeavingSoon: Bool = false,
			notifyNightMarket: Bool = false,
			notificationLeadTimeHours: Int = 24,
			notifyAllAccounts: Bool = true
		) {
			self.theme = theme
			self.customAccentColorComponents = customAccentColorComponents
			self.autoOpenMatchDetails = autoOpenMatchDetails
			self.vibrateOnMatchFound = vibrateOnMatchFound
			self.isCompactListStyle = isCompactListStyle
			self.autoDownloadMatches = autoDownloadMatches
			self.copyPlayerNames = copyPlayerNames
			self.openProfileDirectly = openProfileDirectly
			self.sortOfflineByLastSeen = sortOfflineByLastSeen
			self.friendsSortOrder = friendsSortOrder
			self.clearWebSignInDataOnOpen = clearWebSignInDataOnOpen
			self.matchRetentionDays = matchRetentionDays
			self.keepsOwnMatches = keepsOwnMatches
			self.keepsBookmarkedMatches = keepsBookmarkedMatches
			self.keepsUnlinkedMatches = keepsUnlinkedMatches
			self.notifyShopRefresh = notifyShopRefresh
			self.notifyWishlistMatch = notifyWishlistMatch
			self.notifyBundleLeavingSoon = notifyBundleLeavingSoon
			self.notifyNightMarket = notifyNightMarket
			self.notificationLeadTimeHours = notificationLeadTimeHours
			self.notifyAllAccounts = notifyAllAccounts
		}
		
		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			theme = try container.decode(Theme.self, forKey: .theme)
			customAccentColorComponents = try container.decode(String.self, forKey: .customAccentColorComponents)
			autoOpenMatchDetails = try container.decode(Bool.self, forKey: .autoOpenMatchDetails)
			vibrateOnMatchFound = try container.decode(Bool.self, forKey: .vibrateOnMatchFound)
			isCompactListStyle = try container.decode(Bool.self, forKey: .isCompactListStyle)
			autoDownloadMatches = try container.decode(Bool.self, forKey: .autoDownloadMatches)
			copyPlayerNames = try container.decode(Bool.self, forKey: .copyPlayerNames)
			openProfileDirectly = try container.decode(Bool.self, forKey: .openProfileDirectly)
			sortOfflineByLastSeen = try container.decode(Bool.self, forKey: .sortOfflineByLastSeen)
			friendsSortOrder = try container.decode(FriendsSortOrder.self, forKey: .friendsSortOrder)
			clearWebSignInDataOnOpen = try container.decode(Bool.self, forKey: .clearWebSignInDataOnOpen)
			matchRetentionDays = try container.decode(Int.self, forKey: .matchRetentionDays)
			keepsOwnMatches = try container.decode(Bool.self, forKey: .keepsOwnMatches)
			keepsBookmarkedMatches = try container.decode(Bool.self, forKey: .keepsBookmarkedMatches)
			keepsUnlinkedMatches = try container.decode(Bool.self, forKey: .keepsUnlinkedMatches)
			notifyShopRefresh = try container.decodeIfPresent(Bool.self, forKey: .notifyShopRefresh) ?? false
			notifyWishlistMatch = try container.decodeIfPresent(Bool.self, forKey: .notifyWishlistMatch) ?? false
			notifyBundleLeavingSoon = try container.decodeIfPresent(Bool.self, forKey: .notifyBundleLeavingSoon) ?? false
			notifyNightMarket = try container.decodeIfPresent(Bool.self, forKey: .notifyNightMarket) ?? false
			notificationLeadTimeHours = try container.decodeIfPresent(Int.self, forKey: .notificationLeadTimeHours) ?? 24
			notifyAllAccounts = try container.decodeIfPresent(Bool.self, forKey: .notifyAllAccounts) ?? true
		}
	}
	
	func exportSnapshot() -> BackupSnapshot {
		BackupSnapshot(
			theme: theme,
			customAccentColorComponents: customAccentColorComponents,
			autoOpenMatchDetails: autoOpenMatchDetails,
			vibrateOnMatchFound: vibrateOnMatchFound,
			isCompactListStyle: isCompactListStyle,
			autoDownloadMatches: autoDownloadMatches,
			copyPlayerNames: copyPlayerNames,
			openProfileDirectly: openProfileDirectly,
			sortOfflineByLastSeen: sortOfflineByLastSeen,
			friendsSortOrder: friendsSortOrder,
			clearWebSignInDataOnOpen: clearWebSignInDataOnOpen,
			matchRetentionDays: matchRetentionDays,
			keepsOwnMatches: keepsOwnMatches,
			keepsBookmarkedMatches: keepsBookmarkedMatches,
			keepsUnlinkedMatches: keepsUnlinkedMatches,
			notifyShopRefresh: notifyShopRefresh,
			notifyWishlistMatch: notifyWishlistMatch,
			notifyBundleLeavingSoon: notifyBundleLeavingSoon,
			notifyNightMarket: notifyNightMarket,
			notificationLeadTimeHours: notificationLeadTimeHours,
			notifyAllAccounts: notifyAllAccounts
		)
	}
	
	@MainActor
	func applySnapshot(_ snapshot: BackupSnapshot) {
		let accentChanged = customAccentColorComponents != snapshot.customAccentColorComponents
		if theme != snapshot.theme { theme = snapshot.theme }
		if customAccentColorComponents != snapshot.customAccentColorComponents {
			customAccentColorComponents = snapshot.customAccentColorComponents
		}
		if autoOpenMatchDetails != snapshot.autoOpenMatchDetails { autoOpenMatchDetails = snapshot.autoOpenMatchDetails }
		if vibrateOnMatchFound != snapshot.vibrateOnMatchFound { vibrateOnMatchFound = snapshot.vibrateOnMatchFound }
		if isCompactListStyle != snapshot.isCompactListStyle { isCompactListStyle = snapshot.isCompactListStyle }
		if autoDownloadMatches != snapshot.autoDownloadMatches { autoDownloadMatches = snapshot.autoDownloadMatches }
		if copyPlayerNames != snapshot.copyPlayerNames { copyPlayerNames = snapshot.copyPlayerNames }
		if openProfileDirectly != snapshot.openProfileDirectly { openProfileDirectly = snapshot.openProfileDirectly }
		if sortOfflineByLastSeen != snapshot.sortOfflineByLastSeen { sortOfflineByLastSeen = snapshot.sortOfflineByLastSeen }
		if friendsSortOrder != snapshot.friendsSortOrder { friendsSortOrder = snapshot.friendsSortOrder }
		if clearWebSignInDataOnOpen != snapshot.clearWebSignInDataOnOpen { clearWebSignInDataOnOpen = snapshot.clearWebSignInDataOnOpen }
		if matchRetentionDays != snapshot.matchRetentionDays { matchRetentionDays = snapshot.matchRetentionDays }
		if keepsOwnMatches != snapshot.keepsOwnMatches { keepsOwnMatches = snapshot.keepsOwnMatches }
		if keepsBookmarkedMatches != snapshot.keepsBookmarkedMatches { keepsBookmarkedMatches = snapshot.keepsBookmarkedMatches }
		if keepsUnlinkedMatches != snapshot.keepsUnlinkedMatches { keepsUnlinkedMatches = snapshot.keepsUnlinkedMatches }
		if notifyShopRefresh != snapshot.notifyShopRefresh { notifyShopRefresh = snapshot.notifyShopRefresh }
		if notifyWishlistMatch != snapshot.notifyWishlistMatch { notifyWishlistMatch = snapshot.notifyWishlistMatch }
		if notifyBundleLeavingSoon != snapshot.notifyBundleLeavingSoon { notifyBundleLeavingSoon = snapshot.notifyBundleLeavingSoon }
		if notifyNightMarket != snapshot.notifyNightMarket { notifyNightMarket = snapshot.notifyNightMarket }
		if notificationLeadTimeHours != snapshot.notificationLeadTimeHours { notificationLeadTimeHours = snapshot.notificationLeadTimeHours }
		if notifyAllAccounts != snapshot.notifyAllAccounts { notifyAllAccounts = snapshot.notifyAllAccounts }
		if accentChanged {
			reloadAppForAccentChange()
		}
	}
	
	enum FriendsSortOrder: String, Hashable, Codable, CaseIterable {
		case defaultOrder
		case alphabeticalAsc
		case alphabeticalDesc
		case lastSeen
		case rank
		case level
		
		var title: String {
			switch self {
			case .defaultOrder: return "Default"
			case .alphabeticalAsc: return "Name (A–Z)"
			case .alphabeticalDesc: return "Name (Z–A)"
			case .lastSeen: return "Last Seen"
			case .rank: return "Rank (Highest)"
			case .level: return "Account Level"
			}
		}
		
		var shortTitle: String {
			switch self {
			case .defaultOrder: return "Default"
			case .alphabeticalAsc: return "A–Z"
			case .alphabeticalDesc: return "Z–A"
			case .lastSeen: return "Last Seen"
			case .rank: return "Rank"
			case .level: return "Level"
			}
		}
		
		var icon: String {
			switch self {
			case .defaultOrder: return "line.3.horizontal.decrease"
			case .alphabeticalAsc: return "textformat.abc"
			case .alphabeticalDesc: return "textformat.abc"
			case .lastSeen: return "clock.arrow.circlepath"
			case .rank: return "trophy"
			case .level: return "star.circle"
			}
		}
	}
	
	enum Theme: String, Hashable, Codable, CaseIterable {
		case system
		case light
		case dark
	}
}

extension AppSettings.Theme {
	var colorScheme: ColorScheme? {
		switch self {
		case .system:
			return nil
		case .light:
			return .light
		case .dark:
			return .dark
		}
	}
}
