import SwiftUI
import AVKit

// TODO: remove this when FB9309847 (using implicit CGFloat–Double conversion breaks preview bounds display) is addressed
typealias FloatLiteralType = CGFloat

@main
struct ReconBoltApp: App {
	@StateObject var accountManager = AccountManager()
	@StateObject var assetManager = AssetManager()
	@StateObject var bookmarkList = BookmarkList()
	@StateObject var imageManager = ImageManager()
	@StateObject var settings = AppSettings()
	@StateObject var store = InAppStore()
	@StateObject var configManager = GameConfigManager()
	@StateObject var loadoutPresetManager = LoadoutPresetManager()
	@StateObject var wishlistManager = WishlistManager()
	@StateObject var favoritesManager = FavoritesManager()
	@StateObject var shopHistoryStore = ShopHistoryStore()
	@StateObject var playerSettingsSnapshotStore = PlayerSettingsSnapshotStore()
	@StateObject var seasonGoalStore = SeasonGoalStore()
	@StateObject var progressTimelineStore = ProgressTimelineStore()
	@StateObject var socialManager = SocialManager()
	@StateObject var lineupsManager = LineupsManager()
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
					.environmentObject(bookmarkList)
					.environmentObject(imageManager)
					.environmentObject(settings)
					.environmentObject(configManager)
					.environmentObject(loadoutPresetManager)
					.environmentObject(wishlistManager)
					.environmentObject(favoritesManager)
					.environmentObject(shopHistoryStore)
					.environmentObject(UsernameHistoryStore.shared)
					.environmentObject(playerSettingsSnapshotStore)
					.environmentObject(seasonGoalStore)
					.environmentObject(progressTimelineStore)
					.environmentObject(socialManager)
					.environmentObject(lineupsManager)
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
					await socialManager.connectIfNeeded(using: accountManager.activeAccount?.client)
				}
				.task(id: assetManager.assets?.version) {
					guard let version = assetManager.assets?.version else { return }
					accountManager.clientVersion = version.riotClientVersion
					imageManager.setVersion(version)
				}
			}
		}
	}
	
	private func onLaunch() {
		ReviewManager.registerUsage(points: 2)
		AppSettings.applyGlobalTint(settings.effectiveAccentColor)
		
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

extension EnvironmentValues {
	var ownsProVersion: Bool {
		get { self[OwnsProVersionKey.self] }
		set { self[OwnsProVersionKey.self] = newValue }
	}
	
	private enum OwnsProVersionKey: EnvironmentKey {
		static let defaultValue = true
	}
}
