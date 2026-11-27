import SwiftUI
import AVKit

// TODO: remove this when FB9309847 (using implicit CGFloat–Double conversion breaks preview bounds display) is addressed
typealias FloatLiteralType = CGFloat

@MainActor
private final class AppServices {
	let bookmarkList = BookmarkList()
	let loadoutPresetManager = LoadoutPresetManager()
	let wishlistManager = WishlistManager()
	let favoritesManager = FavoritesManager()
	let shopHistoryStore = ShopHistoryStore()
	let playerSettingsSnapshotStore = PlayerSettingsSnapshotStore()
	let seasonGoalStore = SeasonGoalStore()
	let progressTimelineStore = ProgressTimelineStore()
	let socialManager = SocialManager()
	let lineupsManager = LineupsManager()
}

@MainActor
final class ReconBoltAppDelegate: NSObject, UIApplicationDelegate {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		if ProcessInfo.processInfo.environment["XCInjectBundleInto"] == nil {
			StoreNotificationManager.shared.registerBackgroundTasks()
		}
		return true
	}
}

@main
struct ReconBoltApp: App {
	@UIApplicationDelegateAdaptor(ReconBoltAppDelegate.self) private var appDelegate
	@StateObject var accountManager = AccountManager()
	@StateObject var assetManager = AssetManager()
	@StateObject var settings = AppSettings()
	@StateObject var store = InAppStore()
	@StateObject var configManager = GameConfigManager()
	private let notificationManager = StoreNotificationManager.shared
	private let services = AppServices()
	@State private var hasLaunched = false
	
	private var isTesting: Bool {
		ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil
	}
	
	var body: some Scene {
		WindowGroup {
			if !isTesting {
				Group {
					ContentView(
						accountManager: accountManager,
						assetManager: assetManager,
						settings: settings,
						store: store
					)
					.environmentObject(accountManager)
					.environmentObject(services.bookmarkList)
					.environmentObject(settings)
					.environmentObject(configManager)
					.environmentObject(services.loadoutPresetManager)
					.environmentObject(services.wishlistManager)
					.environmentObject(services.favoritesManager)
					.environmentObject(services.shopHistoryStore)
					.environmentObject(UsernameHistoryStore.shared)
					.environmentObject(services.playerSettingsSnapshotStore)
					.environmentObject(services.seasonGoalStore)
					.environmentObject(services.progressTimelineStore)
					.environmentObject(services.socialManager)
					.environmentObject(services.socialManager.onlineCountModel)
					.environmentObject(services.lineupsManager)
					.environmentObject(notificationManager)
					.environment(\.configs, configManager.configs())
					.environment(\.assets, assetManager.assets)
					.environment(\.location, accountManager.activeAccount?.location)
					.environment(\.ownsProVersion, store.ownsProVersion)
					.environment(\.backupStores, BackupStores(
						accountManager: accountManager,
						bookmarkList: services.bookmarkList,
						settings: settings,
						loadoutPresetManager: services.loadoutPresetManager,
						wishlistManager: services.wishlistManager,
						shopHistoryStore: services.shopHistoryStore,
						usernameHistoryStore: .shared,
						playerSettingsSnapshotStore: services.playerSettingsSnapshotStore,
						seasonGoalStore: services.seasonGoalStore,
						progressTimelineStore: services.progressTimelineStore,
						socialManager: services.socialManager,
						lineupsManager: services.lineupsManager
					))
					.environment(\.favoritesManagerRef, services.favoritesManager)
					.environment(\.progressTimelineStoreRef, services.progressTimelineStore)
					.environment(\.shopHistoryStoreRef, services.shopHistoryStore)
					.environment(\.wishlistManagerRef, services.wishlistManager)
					.preferredColorScheme(settings.theme.colorScheme)
					.tint(settings.effectiveAccentColor)
					.accentColor(settings.effectiveAccentColor)
					.id(settings.accentReloadToken)
				}
				.onAppear {
					guard !hasLaunched else { return }
					hasLaunched = true
					onLaunch()
				}
				.onChange(of: settings.customAccentColorComponents) { _ in
					AppSettings.applyGlobalTint(settings.effectiveAccentColor)
				}
				.task(id: accountManager.activeAccount?.id) {
					await services.socialManager.connectIfNeeded(using: accountManager.activeAccount?.client)
				}
				.modifier(SocialSceneLifecycleModifier(
					socialManager: services.socialManager,
					accountManager: accountManager,
					notificationManager: notificationManager
				))
				.task(id: assetManager.assets?.version) {
					guard let assets = assetManager.assets else { return }
					accountManager.clientVersion = assets.version.riotClientVersion
					ImageManager.shared.setVersion(assets.version)
					ImageManager.shared.prewarmHotAssets(from: assets)
				}
			}
		}
	}
	
	private func onLaunch() {
		PerfMonitor.log("PERF", "ReconBoltApp.onLaunch")
		ReviewManager.registerUsage(points: 2)
		AppSettings.applyGlobalTint(settings.effectiveAccentColor)
		
		notificationManager.configure(
			accountManager: accountManager,
			assetManager: assetManager,
			settings: settings,
			wishlistManager: services.wishlistManager,
			shopHistoryStore: services.shopHistoryStore
		)
		Task {
			await notificationManager.handleAppLaunch()
		}
		
		let bookmarkList = services.bookmarkList
		Task {
			_ = await MatchRetentionManager.pruneIfEnabled(
				settings: settings,
				accountManager: accountManager,
				bookmarkList: bookmarkList
			)
		}
		
		// make videos play audio even in silent mode
		do {
			try AVAudioSession.sharedInstance().setCategory(.playback)
		} catch {
			print("could not set audio session category: \(error)")
		}
	}
}

private struct SocialSceneLifecycleModifier: ViewModifier {
	let socialManager: SocialManager
	let accountManager: AccountManager
	let notificationManager: StoreNotificationManager
	
	@Environment(\.scenePhase) private var scenePhase
	@State private var lastPhase: ScenePhase?
	
	func body(content: Content) -> some View {
		content
			.task(id: scenePhase) {
				let previous = lastPhase
				lastPhase = scenePhase
				if previous == nil {
					if scenePhase == .background {
						socialManager.handleDidEnterBackground()
						notificationManager.handleDidEnterBackground()
					}
					return
				}
				if scenePhase == .background {
					socialManager.handleDidEnterBackground()
					notificationManager.handleDidEnterBackground()
				} else if scenePhase == .active, previous != .active {
					await notificationManager.refreshStatus()
					await socialManager.handleSceneActivation(using: accountManager.activeAccount?.client)
				}
			}
	}
}

extension EnvironmentValues {
	var ownsProVersion: Bool {
		get { self[OwnsProVersionKey.self] }
		set { self[OwnsProVersionKey.self] = newValue }
	}
	
	var backupStores: BackupStores? {
		get { self[BackupStoresKey.self] }
		set { self[BackupStoresKey.self] = newValue }
	}
	
	var favoritesManagerRef: FavoritesManager? {
		get { self[FavoritesManagerRefKey.self] }
		set { self[FavoritesManagerRefKey.self] = newValue }
	}
	
	var progressTimelineStoreRef: ProgressTimelineStore? {
		get { self[ProgressTimelineStoreRefKey.self] }
		set { self[ProgressTimelineStoreRefKey.self] = newValue }
	}
	
	var shopHistoryStoreRef: ShopHistoryStore? {
		get { self[ShopHistoryStoreRefKey.self] }
		set { self[ShopHistoryStoreRefKey.self] = newValue }
	}
	
	var wishlistManagerRef: WishlistManager? {
		get { self[WishlistManagerRefKey.self] }
		set { self[WishlistManagerRefKey.self] = newValue }
	}
	
	private enum OwnsProVersionKey: EnvironmentKey {
		static let defaultValue = true
	}
	
	private enum BackupStoresKey: EnvironmentKey {
		static let defaultValue: BackupStores? = nil
	}
	
	private enum FavoritesManagerRefKey: EnvironmentKey {
		static let defaultValue: FavoritesManager? = nil
	}
	
	private enum ProgressTimelineStoreRefKey: EnvironmentKey {
		static let defaultValue: ProgressTimelineStore? = nil
	}
	
	private enum ShopHistoryStoreRefKey: EnvironmentKey {
		static let defaultValue: ShopHistoryStore? = nil
	}
	
	private enum WishlistManagerRefKey: EnvironmentKey {
		static let defaultValue: WishlistManager? = nil
	}
}
