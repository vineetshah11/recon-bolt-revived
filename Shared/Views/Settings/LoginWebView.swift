import SwiftUI
import WebKit
import ValorantAPI

/// Holds the `WKWebView` instance in a `@StateObject` so switching to another app
/// (e.g. Mail / Authenticator for 2FA) never recreates or reloads the login page.
@MainActor
final class RiotLoginWebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
	let webView: WKWebView
	
	@Published var isLoading = true
	@Published var loadError: String?
	
	var onAuthRedirect: ((URL, [HTTPCookie]) -> Void)?
	private var hasLoadedInitialURL = false
	private var didCompleteAuth = false
	
	static let mobileSafariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
	
	override init() {
		let config = WKWebViewConfiguration()
		// persistent store: iOS may suspend/evict the web content process while you're in Mail
		// fetching the 2FA code; a non-persistent store loses the half-finished login when that happens.
		config.websiteDataStore = .default()
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.customUserAgent = Self.mobileSafariUserAgent
		self.webView = webView
		super.init()
		webView.navigationDelegate = self
		webView.uiDelegate = self
	}
	
	func loadIfNeeded() {
		guard !hasLoadedInitialURL else { return }
		hasLoadedInitialURL = true
		reload()
	}
	
	static func clearAllWebsiteData() async {
		await WKWebsiteDataStore.default().removeData(
			ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
			modifiedSince: .distantPast
		)
	}
	
	/// Called once when the user starts a new sign-in: drops previous Riot/third-party web data if enabled, then loads the login page.
	func startNewSession(clearWebData: Bool = true) {
		hasLoadedInitialURL = true
		didCompleteAuth = false
		isLoading = true
		guard clearWebData else {
			reload()
			return
		}
		Task { @MainActor [weak self] in
			await Self.clearAllWebsiteData()
			self?.reload()
		}
	}
	
	func reload() {
		didCompleteAuth = false
		loadError = nil
		isLoading = true
		webView.load(URLRequest(url: APISession.riotLoginURL))
	}
	
	private func handleRedirectIfTokenPresent(_ url: URL?) -> Bool {
		guard
			!didCompleteAuth,
			let url,
			url.host?.hasSuffix("playvalorant.com") == true,
			let fragment = url.fragment,
			fragment.contains("access_token=")
		else {
			return false
		}
		
		didCompleteAuth = true
		isLoading = true
		
		let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
		cookieStore.getAllCookies { [weak self] cookies in
			Task { @MainActor [weak self] in
				self?.onAuthRedirect?(url, cookies)
			}
		}
		return true
	}
	
	nonisolated func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		let url = navigationAction.request.url
		Task { @MainActor [weak self] in
			if self?.handleRedirectIfTokenPresent(url) == true {
				decisionHandler(.cancel)
			} else {
				decisionHandler(.allow)
			}
		}
	}
	
	nonisolated func webView(
		_ webView: WKWebView,
		didStartProvisionalNavigation navigation: WKNavigation!
	) {
		Task { @MainActor [weak self] in
			self?.isLoading = true
			self?.loadError = nil
		}
	}
	
	nonisolated func webView(
		_ webView: WKWebView,
		didFinish navigation: WKNavigation!
	) {
		Task { @MainActor [weak self] in
			self?.isLoading = false
		}
	}
	
	nonisolated func webView(
		_ webView: WKWebView,
		didFail navigation: WKNavigation!,
		withError error: Error
	) {
		Task { @MainActor [weak self] in
			guard let self, !self.didCompleteAuth else { return }
			let nsError = error as NSError
			if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
			self.isLoading = false
			self.loadError = error.localizedDescription
		}
	}
	
	nonisolated func webView(
		_ webView: WKWebView,
		didFailProvisionalNavigation navigation: WKNavigation!,
		withError error: Error
	) {
		Task { @MainActor [weak self] in
			guard let self, !self.didCompleteAuth else { return }
			let nsError = error as NSError
			if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
			self.isLoading = false
			self.loadError = error.localizedDescription
		}
	}
	
	nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		// iOS killed the web process in the background: restore the *current* page rather than restarting the login.
		Task { @MainActor in
			if webView.url != nil {
				webView.reload()
			} else {
				self.reload()
			}
		}
	}
	
	nonisolated func webView(
		_ webView: WKWebView,
		createWebViewWith configuration: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures: WKWindowFeatures
	) -> WKWebView? {
		MainActor.assumeIsolated {
			if navigationAction.targetFrame == nil {
				webView.load(navigationAction.request)
			}
			return nil
		}
	}
}

#if os(iOS)
struct RiotLoginWebView: UIViewRepresentable {
	@ObservedObject var model: RiotLoginWebViewModel
	
	func makeUIView(context: Context) -> WKWebView {
		model.loadIfNeeded()
		return model.webView
	}
	
	func updateUIView(_ uiView: WKWebView, context: Context) {
		// Intentionally do not reload here so backgrounding (e.g. checking 2FA email)
		// never resets the active login session.
	}
}
#elseif os(macOS)
struct RiotLoginWebView: NSViewRepresentable {
	@ObservedObject var model: RiotLoginWebViewModel
	
	func makeNSView(context: Context) -> WKWebView {
		model.loadIfNeeded()
		return model.webView
	}
	
	func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
