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

@main
struct ReconBoltApp: App {
	@StateObject var accountManager = AccountManager()
	@StateObject var assetManager = AssetManager()
	@StateObject var settings = AppSettings()
	@StateObject var store = InAppStore()
	@StateObject var configManager = GameConfigManager()
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
					.environment(\.configs, configManager.configs())
					.environment(\.assets, assetManager.assets)
					.environment(\.location, accountManager.activeAccount?.location)
					.environment(\.ownsProVersion, store.ownsProVersion)
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
					accountManager: accountManager
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
					}
					return
				}
				if scenePhase == .background {
					socialManager.handleDidEnterBackground()
				} else if scenePhase == .active, previous != .active {
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
	
	private enum OwnsProVersionKey: EnvironmentKey {
		static let defaultValue = true
	}
}
