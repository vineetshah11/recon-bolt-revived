import SwiftUI
import ValorantAPI

struct LoginForm: View {
	@ObservedObject var accountManager: AccountManager
	var credentials = Credentials()
	@State var isSigningIn = false
	@StateObject private var webViewModel = RiotLoginWebViewModel()
	
	@Environment(\.loadWithErrorAlerts) private var load
	@Environment(\.dismiss) private var dismiss
	
	var body: some View {
		ZStack {
			RiotLoginWebView(model: webViewModel)
				.opacity(isSigningIn ? 0.25 : 1)
				.disabled(isSigningIn)
			
			if isSigningIn || webViewModel.isLoading {
				ProgressView {
					if isSigningIn {
						Text("signing in…", comment: "Login Form")
					}
				}
				.padding()
				.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
			}
		}
		.onAppear {
			webViewModel.onAuthRedirect = { url, cookies in
				Task {
					await completeSignIn(redirectURL: url, cookies: cookies)
				}
			}
			webViewModel.loadIfNeeded()
		}
		.interactiveDismissDisabled(isSigningIn)
		.navigationTitle(Text("Sign In with your Riot account", comment: "Login Form"))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .cancellationAction) {
				Button { dismiss() } label: {
					Text("Cancel")
				}
			}
			ToolbarItemGroup(placement: .primaryAction) {
				Button {
					webViewModel.reload()
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.disabled(isSigningIn)
			}
		}
		.withToolbar(allowLargeTitles: false)
	}
	
	func completeSignIn(redirectURL: URL, cookies: [HTTPCookie]) async {
		isSigningIn = true
		defer { isSigningIn = false }
		
		await load {
			try await accountManager.addAccount(redirectURL: redirectURL, cookies: cookies)
			dismiss()
		}
	}
}

#if DEBUG
struct LoginForm_Previews: PreviewProvider {
	static var previews: some View {
		LoginForm(accountManager: .mocked)
			.withToolbar()
	}
}
#endif
