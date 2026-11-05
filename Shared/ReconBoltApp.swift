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
	
	private var isTesting: Bool {
		ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil
	}
	
	var body: some Scene {
		WindowGroup {
			if !isTesting {
				ContentView(
					accountManager: accountManager,
					assetManager: assetManager,
					settings: settings,
					store: store
				)
				.onAppear { onLaunch() }
				.environmentObject(bookmarkList)
				.environmentObject(imageManager)
				.environmentObject(settings)
				.environmentObject(configManager)
				.environment(\.configs, configManager.configs())
				.environment(\.assets, assetManager.assets)
				.environment(\.location, accountManager.activeAccount?.location)
				.environment(\.ownsProVersion, store.ownsProVersion)
				.preferredColorScheme(settings.theme.colorScheme)
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
		
		// make videos play audio even in silent mode
		do {
			try AVAudioSession.sharedInstance().setCategory(.playback)
		} catch {
			print("could not set audio session category: \(error)")
		}
		
		// Fetch the Riot client version early so API calls work
		// even before the full asset download completes.
		Task { await fetchClientVersionEarly() }
	}
	
	/// Fetches the current Riot client version from valorant-api.com
	/// and stores it in accountManager immediately on launch.
	/// This runs in parallel with (and before) full asset loading,
	/// preventing "Bad headers / INVALID_HEADERS" errors on first API call.
	private func fetchClientVersionEarly() async {
		// Fallback version in case the network call fails.
		// Keep this roughly current; it's only used if valorant-api.com is unreachable.
		let fallbackVersion = "release-13.09-shipping-18-5804228"
		
		do {
			guard let url = URL(string: "https://valorant-api.com/v1/version") else { return }
			let (data, _) = try await URLSession.shared.data(from: url)
			
			struct VersionResponse: Decodable {
				struct Data: Decodable { let riotClientVersion: String }
				let data: Data
			}
			let decoded = try JSONDecoder().decode(VersionResponse.self, from: data)
			let version = decoded.data.riotClientVersion
			print("[ReconBolt] Fetched client version early: \(version)")
			accountManager.clientVersion = version
		} catch {
			print("[ReconBolt] Early version fetch failed (\(error)), using fallback: \(fallbackVersion)")
			// Only set fallback if we don't already have a version from cached assets
			if accountManager.clientVersion == nil {
				accountManager.clientVersion = fallbackVersion
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
		static let defaultValue = false
	}
}
