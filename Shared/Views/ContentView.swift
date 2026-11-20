import SwiftUI
import HandyOperators
import ValorantAPI
import WidgetKit

struct ContentView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject private var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	@ObservedObject var store: InAppStore
	
	@SceneStorage("tab")
	var tab = Tab.career
	
	@State var handleDeepLink: DeepLink.Handler?
	@State var isReauthenticating = false
	
	var body: some View {
		TabView(selection: $tab) {
			onlineView { BookmarkListView(userID: $0) }
				.withToolbar()
				.tabItem { Label(
					String(localized: "Matches", comment: "Top-Level Tab Title"),
					systemImage: "clock"
				) }
				.tag(Tab.career)
			
			onlineView { LiveView(userID: $0).id(accountManager.sessionGeneration) }
				.withToolbar()
				.tabItem { Label(
					String(localized: "Live", comment: "Top-Level Tab Title"),
					systemImage: "play"
				) }
				.tag(Tab.live)
			
			ReferenceView()
				.withToolbar()
				.tabItem { Label(
					String(localized: "Explore", comment: "Top-Level Tab Title"),
					systemImage: "square.grid.2x2"
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
		.environmentObject(assetManager)
		.environmentObject(assetManager)
	.environment(\.assets, assetManager.assets)
		.task(id: accountManager.requiresAction) {
			if accountManager.requiresAction {
				tab = .settings
				if accountManager.activeAccount != nil {
					isReauthenticating = true
				}
			}
		}
		.onChange(of: accountManager.requiresAction) { requiresAction in
			guard requiresAction, accountManager.activeAccount != nil else { return }
			// web sign-in only stores tokens, so the stored session can't refresh itself;
			// grab a fresh one from Riot's login page (usually silent, since its cookies persist)
			isReauthenticating = true
		}
		.task {
			// make sure the reference and settings tabs see a loading/error state even when the user
			// is not signed in; the app root already injects assetManager.assets, but this keeps the
			// ContentView tree self-contained if it is ever hosted somewhere without the App-level env.
			await assetManager.tryLoadAssets()
		}
		.sheet(caching: $accountManager.multifactorPrompt) {
			MultifactorPromptView(prompt: $0, didSessionExpire: true)
		} onDismiss: {
			$0.completion(.failure(AccountManager.MultifactorPromptError.cancelled))
		}
		.fullScreenCover(isPresented: $isReauthenticating) {
			SessionRefreshView(manager: accountManager)
		}
		.withValorantLoadFunction(manager: accountManager)
		.withLoadErrorAlerts()
		.onSceneActivation {
			Task { await assetManager.tryLoadAssets() }
			Task { await accountManager.refreshClientVersion() }
		}
		.readingDeepLinkHandler { handleDeepLink = $0 }
		.environment(\.deepLink, handle(_:))
		.onOpenURL(perform: handle(_:))
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

/// Full-screen Riot sign-in used when the stored session can't refresh on its own.
/// Unlike ``RiotWebAuthView`` it stays open until a working session exists, and shows why it didn't.
struct SessionRefreshView: View {
	@ObservedObject var manager: AccountManager
	
	@Environment(\.dismiss) private var dismiss
	
	@State private var attempt = 0
	@State private var isSigningIn = false
	@State private var errorMessage: String?
	
	var body: some View {
		NavigationView {
			ZStack(alignment: .bottom) {
				RiotWebAuthRepresentable(
					onSuccess: signIn,
					onFailure: { error in errorMessage = error.localizedDescription }
				)
				.id(attempt)
				
				if isSigningIn {
					ProgressView(String(localized: "Signing in…", comment: "Session refresh: progress"))
						.padding()
						.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				
				if let errorMessage {
					VStack(spacing: 8) {
						Text(errorMessage)
							.font(.footnote)
							.multilineTextAlignment(.center)
						Button(String(localized: "Try Again", comment: "Session refresh: button")) {
							self.errorMessage = nil
							attempt += 1
						}
						.buttonStyle(.borderedProminent)
					}
					.padding()
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.padding()
				}
			}
			.navigationTitle(Text("Sign In to Riot", comment: "Session refresh: title"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(String(localized: "Cancel", comment: "Session refresh: button")) {
						dismiss()
					}
				}
			}
		}
		.ignoresSafeArea(.all, edges: .bottom)
	}
	
	private func signIn(_ tokens: WebAuthTokens) {
		guard !isSigningIn else { return }
		isSigningIn = true
		errorMessage = nil
		
		Task {
			do {
				try await manager.addAccount(using: tokens)
				dismiss()
			} catch {
				errorMessage = error.localizedDescription
			}
			isSigningIn = false
		}
	}
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		ContentView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init())
		ContentView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init(), tab: .live)
		ContentView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init(), tab: .reference)
		ContentView(accountManager: .init(), assetManager: .forPreviews, settings: .init(), store: .init())
	}
}
#endif
