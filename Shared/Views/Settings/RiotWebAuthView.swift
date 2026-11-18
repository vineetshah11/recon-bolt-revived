import SwiftUI
import WebKit
import ValorantAPI

// MARK: - RiotWebAuthView
// Replaces the old username/password URLSession auth with a WKWebView-based flow.
// This bypasses Cloudflare's bot protection because:
//   - WKWebView is a real iOS web engine (not URLSession)
//   - iOS 16+ supports Private Access Tokens which Cloudflare accepts silently
//   - The user types credentials directly in the browser, no programmatic submission
//
// Flow:
//   1. Load auth.riotgames.com/authorize in WKWebView
//   2. User logs in manually
//   3. Riot redirects to playvalorant.com/#access_token=...
//   4. We intercept the redirect, extract tokens, close the sheet

struct RiotWebAuthView: View {
    @Environment(\.dismiss) private var dismiss
    var onSuccess: (WebAuthTokens) -> Void
    var onFailure: (Error) -> Void
    
    var body: some View {
        NavigationView {
            RiotWebAuthRepresentable(onSuccess: { tokens in
                onSuccess(tokens)
                dismiss()
            }, onFailure: { error in
                onFailure(error)
                dismiss()
            })
            .navigationTitle("Sign In to Riot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onFailure(RiotWebAuthError.userCancelled)
                        dismiss()
                    }
                }
            }
            .ignoresSafeArea(.all, edges: .bottom)
        }
    }
}

// MARK: - UIViewRepresentable wrapper for WKWebView

struct RiotWebAuthRepresentable: UIViewRepresentable {
    var onSuccess: (WebAuthTokens) -> Void
    var onFailure: (Error) -> Void
    
    // Riot OAuth2 authorize URL
    // Uses the same parameters as the original CookiesRequest but via browser
    private static let authURL: URL = {
        var components = URLComponents(string: "https://auth.riotgames.com/authorize")!
        components.queryItems = [
            .init(name: "redirect_uri",  value: "https://playvalorant.com/opt_in"),
            .init(name: "client_id",     value: "play-valorant-web-prod"),
            .init(name: "response_type", value: "token id_token"),
            .init(name: "scope",         value: "account openid"),
            .init(name: "nonce",         value: "1"),
        ]
        return components.url!
    }()
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess, onFailure: onFailure)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use the default persistent store so Riot session cookies survive app restarts.
        // Previously used .nonPersistent() which discarded cookies on every launch.
        config.websiteDataStore = .default()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: Self.authURL))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    // MARK: Coordinator (WKNavigationDelegate)
    
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSuccess: (WebAuthTokens) -> Void
        var onFailure: (Error) -> Void
        
        private let redirectPrefix = "https://playvalorant.com/opt_in"
        
        init(onSuccess: @escaping (WebAuthTokens) -> Void, onFailure: @escaping (Error) -> Void) {
            self.onSuccess = onSuccess
            self.onFailure = onFailure
        }
        
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard
                let url = navigationAction.request.url,
                url.absoluteString.hasPrefix(redirectPrefix)
            else {
                decisionHandler(.allow)
                return
            }
            
            // Cancel navigation — we extract the tokens from the URL
            decisionHandler(.cancel)
            
            // Tokens are in the URL fragment (e.g. #access_token=...&id_token=...&expires_in=...)
            guard let tokens = WebAuthTokens(from: url) else {
                onFailure(RiotWebAuthError.couldNotExtractTokens(url))
                return
            }
            
            onSuccess(tokens)
        }
        
        		func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
			report(error)
		}
		
		func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
			report(error)
		}
		
		private func report(_ error: Error) {
			// Ignore "cancelled" errors from our own decisionHandler(.cancel)
			let nsError = error as NSError
			if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
			onFailure(RiotWebAuthError.navigationFailed(error))
		}
    }
}

// MARK: - Token Model Extension

extension WebAuthTokens {
    init?(from url: URL) {
        // Riot puts tokens in the URL *fragment* (after #)
        guard let fragment = url.fragment else { return nil }
        
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            params[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        
        guard
            let access = params["access_token"],
            let id = params["id_token"],
            let expiresStr = params["expires_in"],
            let expires = Int(expiresStr)
        else { return nil }
        
        self.accessToken  = access
        self.idToken      = id
        self.expiresIn    = expires
    }
}

// MARK: - Errors

enum RiotWebAuthError: LocalizedError {
    case userCancelled
    case couldNotExtractTokens(URL)
    case navigationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Sign-in was cancelled."
        case .couldNotExtractTokens(let url):
            return "Could not extract auth tokens from redirect URL: \(url)"
        case .navigationFailed(let error):
            return "Web navigation failed: \(error.localizedDescription)"
        }
    }
}
