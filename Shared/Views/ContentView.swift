import SwiftUI
import HandyOperators
import ValorantAPI
import WidgetKit

struct ContentView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	@ObservedObject var store: InAppStore
	
	@EnvironmentObject private var bookmarkList: BookmarkList
	@EnvironmentObject private var loadoutPresetManager: LoadoutPresetManager
	@EnvironmentObject private var wishlistManager: WishlistManager
	@EnvironmentObject private var shopHistoryStore: ShopHistoryStore
	@EnvironmentObject private var usernameHistoryStore: UsernameHistoryStore
	@EnvironmentObject private var playerSettingsSnapshotStore: PlayerSettingsSnapshotStore
	@EnvironmentObject private var seasonGoalStore: SeasonGoalStore
	@EnvironmentObject private var progressTimelineStore: ProgressTimelineStore
	@EnvironmentObject private var socialManager: SocialManager
	@EnvironmentObject private var lineupsManager: LineupsManager
	
	@SceneStorage("tab")
	var tab = Tab.career
	
	@State var handleDeepLink: DeepLink.Handler?
	@State private var incomingBackupFile: IncomingBackupFile?
	
	private struct IncomingBackupFile: Identifiable {
		let id = UUID()
		let url: URL
	}
	
	var body: some View {
		TabView(selection: $tab) {
			onlineView { BookmarkListView(userID: $0) }
				.withToolbar()
				.tabItem { Label(
					String(localized: "Career", comment: "Top-Level Tab Title"),
					systemImage: "clock"
				) }
				.tag(Tab.career)
			
			onlineView { LiveView(userID: $0) }
				.withToolbar()
				.tabItem { Label(
					String(localized: "Live", comment: "Top-Level Tab Title"),
					systemImage: "play"
				) }
				.tag(Tab.live)
			
			ReferenceView()
				.withToolbar()
				.tabItem { Label(
					String(localized: "Hub", comment: "Top-Level Tab Title"),
					systemImage: "square.grid.2x2.fill"
				) }
				.tag(Tab.reference)
			
			SettingsView(accountManager: accountManager, assetManager: assetManager, settings: settings, store: store)
				.withToolbar()
				.tabItem { Label(
					String(localized: "Settings", comment: "Top-Level Tab Title"),
					systemImage: "gearshape"
				) }
				.tag(Tab.settings)
		}
		.tint(settings.effectiveAccentColor)
		.accentColor(settings.effectiveAccentColor)
		.modifier(LiquidGlassTabBarModifier())
		.task(id: accountManager.requiresAction) {
			if accountManager.requiresAction {
				tab = .settings
			}
		}
		.sheet(caching: $accountManager.multifactorPrompt) {
			MultifactorPromptView(prompt: $0, didSessionExpire: true)
		} onDismiss: {
			$0.completion(.failure(AccountManager.MultifactorPromptError.cancelled))
		}
		.withValorantLoadFunction(manager: accountManager)
		.withLoadErrorAlerts()
		.onSceneActivation {
			Task { await assetManager.tryLoadAssets() }
		}
		.readingDeepLinkHandler { handleDeepLink = $0 }
		.environment(\.deepLink, handle(_:))
		.onOpenURL(perform: handle(_:))
		.sheet(item: $incomingBackupFile) { file in
			NavigationStack {
				BackupImportView(stores: makeBackupStores(), initialURL: file.url)
			}
		}
	}
	
	private func makeBackupStores() -> BackupStores {
		BackupStores(
			accountManager: accountManager,
			bookmarkList: bookmarkList,
			settings: settings,
			loadoutPresetManager: loadoutPresetManager,
			wishlistManager: wishlistManager,
			shopHistoryStore: shopHistoryStore,
			usernameHistoryStore: usernameHistoryStore,
			playerSettingsSnapshotStore: playerSettingsSnapshotStore,
			seasonGoalStore: seasonGoalStore,
			progressTimelineStore: progressTimelineStore,
			socialManager: socialManager,
			lineupsManager: lineupsManager
		)
	}
	
	@ViewBuilder
	private func onlineView<Content: View>(
		@ViewBuilder content: @escaping (User.ID) -> Content
	) -> some View {
		UnwrappingView(
			value: accountManager.activeAccount,
			placeholder: "Not signed in!"
		) { account in
			content(account.id)
		}
	}
	
	func handle(_ url: URL) {
		print("handling", url)
		if url.isFileURL, url.pathExtension.lowercased() == "rbbackup" {
			incomingBackupFile = IncomingBackupFile(url: url)
			return
		}
		do {
			if let widgetLink = try WidgetLink(from: url) {
				handle(widgetLink)
			}
		} catch {
			print("could not decode opened url: \(url)")
		}
	}
	
	func handle(_ link: WidgetLink) {
		guard #available(iOS 16.0, *) else { return }
		print("handling", link)
		
		if let kind = link.timelinesToReload {
			WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
		}
		
		if let user = link.account {
			do {
				try accountManager.setActive(user)
			} catch {
				print("error setting account to \(user) for widget link")
			}
		}
		
		switch link.destination {
		case .career:
			tab = .career
		case .store, .missions:
			tab = .live
		case nil:
			break
		}
		
		handleWithDelay(.widget(link))
	}
	
	func handle(_ link: InAppLink) {
		switch link {
		case .storefront:
			tab = .settings
		}
		
		handleWithDelay(.inApp(link))
	}
	
	private func handleWithDelay(_ link: DeepLink) {
		// delay to give newly-displayed tabs time to propagate their preferences
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
			handleDeepLink?(link)
		}
	}
	
	enum Tab: String {
		case career
		case live
		case reference
		case settings
	}
}

private struct LiquidGlassTabBarModifier: ViewModifier {
	func body(content: Content) -> some View {
		if #available(iOS 26.0, *) {
			content
				.tabBarMinimizeBehavior(.never)
		} else {
			content
		}
	}
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			ContentView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init())
			ContentView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init(), tab: .live)
			ContentView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init(), tab: .reference)
			ContentView(accountManager: .init(), assetManager: .forPreviews, settings: .init(), store: .init())
		}
		.environmentObject(BookmarkList())
		.environmentObject(LoadoutPresetManager())
		.environmentObject(WishlistManager())
		.environmentObject(FavoritesManager())
		.environmentObject(ShopHistoryStore())
		.environmentObject(UsernameHistoryStore.shared)
		.environmentObject(PlayerSettingsSnapshotStore())
		.environmentObject(SeasonGoalStore())
		.environmentObject(ProgressTimelineStore())
		.environmentObject(SocialManager())
		.environmentObject(LineupsManager())
	}
}
#endif
