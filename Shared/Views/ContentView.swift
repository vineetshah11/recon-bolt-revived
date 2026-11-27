import SwiftUI
import Combine
import HandyOperators
import ValorantAPI
import WidgetKit

struct ContentView: View {
	@ObservedObject var accountManager: AccountManager
	let assetManager: AssetManager
	let settings: AppSettings
	let store: InAppStore
	
	@Environment(\.backupStores) private var backupStores
	
	@SceneStorage("tab")
	var tab = Tab.career
	
	@State private var deepLinkBox = DeepLinkHandlerBox()
	@State private var incomingBackupFile: IncomingBackupFile?
	
	private final class DeepLinkHandlerBox {
		var handler: DeepLink.Handler?
	}
	
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
			
			onlineView { LiveView(userID: $0, isTabActive: tab == .live) }
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
			await assetManager.tryLoadAssets()
		}
		.readingDeepLinkHandler { deepLinkBox.handler = $0 }
		.environment(\.deepLink, handle(_:))
		.onOpenURL(perform: handle(_:))
		.sheet(item: $incomingBackupFile) { file in
			if let backupStores {
				NavigationStack {
					BackupImportView(stores: backupStores, initialURL: file.url)
				}
			}
		}
		.onAppear {
			consumeNotificationRouteIfNeeded()
		}
		.onReceive(StoreNotificationManager.shared.$pendingRoute.removeDuplicates().compactMap { $0 }) { _ in
			consumeNotificationRouteIfNeeded()
		}
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
		case .store:
			tab = .live
		}
		
		handleWithDelay(.inApp(link))
	}
	
	private func consumeNotificationRouteIfNeeded() {
		guard let route = StoreNotificationManager.shared.consumePendingRoute() else { return }
		if let accountID = route.accountID,
		   accountManager.storedAccounts.contains(accountID) {
			try? accountManager.setActive(accountID)
		}
		handle(InAppLink.store(expandNightMarket: route.expandNightMarket))
	}
	
	private func handleWithDelay(_ link: DeepLink) {
		// delay to give newly-displayed tabs time to propagate their preferences
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
			deepLinkBox.handler?(link)
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
		.environmentObject(StoreNotificationManager.shared)
	}
}
#endif
