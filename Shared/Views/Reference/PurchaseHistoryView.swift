import SwiftUI
import WebKit
import ValorantAPI

/// Riot moved purchase history to support.riotgames.com, which authenticates via XSSO and then calls the Skye API
/// with an `X-Riot-Support-Token`. That token only exists inside a browser session, so we run the official page in a
/// (normally hidden) web view, wait for the token, and call the same endpoint the page uses.
@MainActor
final class RiotSupportPurchaseLoader: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
	enum State: Equatable {
		case idle
		case loading
		case needsSignIn
		case loaded
		case failed(String)
	}
	
	@Published var state: State = .idle
	@Published var history: PurchaseHistory?
	
	let webView: WKWebView
	private var pollTask: Task<Void, Never>?
	private var isFetching = false
	
	private static let historyEndpoint = "https://skye-production.sgp.riotgames.com/api/v1/sspd/valorant_purchase_history"
	
	override init() {
		let config = WKWebViewConfiguration()
		config.websiteDataStore = .default() // keeps the XSSO session so later loads are silent
		webView = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 700), configuration: config)
		webView.customUserAgent = RiotLoginWebViewModel.mobileSafariUserAgent
		super.init()
		webView.navigationDelegate = self
		webView.uiDelegate = self
	}
	
	private var supportPageURL: URL {
		let lang = (Locale.preferredLanguages.first ?? "en-US").lowercased()
		let supported = ["en-us", "fr-fr", "de-de", "es-es", "es-mx", "it-it", "pt-br", "pl-pl", "tr-tr", "ru-ru", "ja-jp", "ko-kr"]
		let code = supported.first { lang.hasPrefix($0) } ?? supported.first { lang.hasPrefix($0.prefix(2)) } ?? "en-us"
		return URL(string: "https://support.riotgames.com/\(code)/valorant/billing/checking-your-purchase-history")!
	}
	
	func start(cookies: [HTTPCookie]) async {
		guard !isFetching else { return }
		state = .loading
		let store = webView.configuration.websiteDataStore.httpCookieStore
		for cookie in cookies where cookie.domain.contains("riotgames.com") {
			await store.setCookie(cookie)
		}
		webView.load(URLRequest(url: supportPageURL))
		startPolling()
	}
	
	func reloadPage() {
		webView.load(URLRequest(url: supportPageURL))
		startPolling()
	}
	
	func stop() {
		pollTask?.cancel()
		pollTask = nil
	}
	
	private func startPolling() {
		pollTask?.cancel()
		pollTask = Task { [weak self] in
			let start = Date()
			while !Task.isCancelled {
				try? await Task.sleep(nanoseconds: 800_000_000)
				guard let self, !Task.isCancelled else { return }
				if let token = await self.supportToken() {
					await self.fetchHistory(token: token)
					return
				}
				// no silent session after a few seconds: let the user sign in on Riot's page
				if self.state == .loading, Date().timeIntervalSince(start) > 7 {
					self.state = .needsSignIn
				}
			}
		}
	}
	
	private func supportToken() async -> String? {
		let js = "(() => { const t = sessionStorage.getItem('__support-token'); if (!t) return null; try { const p = JSON.parse(t); return typeof p === 'string' ? p : t } catch (e) { return t } })()"
		guard let token = try? await webView.evaluateJavaScript(js) as? String, !token.isEmpty else { return nil }
		return token
	}
	
	private func fetchHistory(token: String) async {
		isFetching = true
		defer { isFetching = false }
		state = .loading
		let js = """
		const r = await fetch(url, { method: 'GET', credentials: 'omit', headers: { 'X-Riot-Support-Token': token } });
		const body = await r.text();
		return JSON.stringify({ status: r.status, body: body });
		"""
		do {
			let raw = try await webView.callAsyncJavaScript(js, arguments: ["url": Self.historyEndpoint, "token": token], contentWorld: .page)
			guard
				let wrapper = (raw as? String)?.data(using: .utf8),
				let json = try JSONSerialization.jsonObject(with: wrapper) as? [String: Any],
				let status = json["status"] as? Int,
				let body = json["body"] as? String
			else { throw URLError(.cannotParseResponse) }
			guard (200..<300).contains(status) else {
				state = .failed("Riot Support returned HTTP \(status).\n\(body.prefix(200))")
				return
			}
			history = try PurchaseHistory.decode(from: Data(body.utf8))
			state = .loaded
		} catch {
			state = .failed(error.localizedDescription)
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

private struct RiotSupportWebView: UIViewRepresentable {
	@ObservedObject var loader: RiotSupportPurchaseLoader
	
	func makeUIView(context: Context) -> WKWebView { loader.webView }
	func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct PurchaseHistoryView: View {
	enum Tab: String, CaseIterable, Identifiable {
		case payments = "Payments"
		case transactions = "Transactions"
		
		var id: String { rawValue }
	}
	
	@EnvironmentObject private var accountManager: AccountManager
	@Environment(\.assets) private var assets
	
	@State private var tab: Tab = .payments
	@State private var search = ""
	@StateObject private var loader = RiotSupportPurchaseLoader()
	
	private var history: PurchaseHistory? { loader.history }
	private var isLoading: Bool { loader.state == .loading || loader.state == .idle }
	private var errorMessage: String? {
		if case .failed(let message) = loader.state { return message }
		return nil
	}
	
	private var isShowingSignIn: Binding<Bool> {
		Binding(
			get: { loader.state == .needsSignIn },
			set: { if !$0 && loader.state == .needsSignIn { loader.state = .failed("Sign in to Riot Support to view your purchase history.") } }
		)
	}
	
	var body: some View {
		List {
			Section {
				Picker("Section", selection: $tab) {
					ForEach(Tab.allCases) { item in
						Text(item.rawValue).tag(item)
					}
				}
				.pickerStyle(.segmented)
				.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
			}
			
			if isLoading && history == nil {
				Section {
					HStack {
						Spacer()
						ProgressView("Loading from Riot Support...")
						Spacer()
					}
					.padding(.vertical, 16)
				}
			} else if let errorMessage {
				Section {
					VStack(alignment: .leading, spacing: 8) {
						Text("Could Not Load Purchase History")
							.font(.headline)
							.foregroundStyle(.red)
						Text(errorMessage)
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Button("Retry") {
							Task { await loadHistory() }
						}
					}
					.padding(.vertical, 6)
				}
			} else if let history {
				if tab == .payments {
					paymentsSections(history.account.billing.paymentHistory)
				} else {
					walletSections(history.ares.walletTransactions)
				}
			}
		}
		.searchable(text: $search, prompt: Text("Filter history"))
		.navigationTitle("Purchase History")
		.background {
			if loader.state != .needsSignIn {
				// the web view must be in the hierarchy to run; keep it invisible while it works silently
				RiotSupportWebView(loader: loader)
					.frame(width: 1, height: 1)
					.opacity(0.01)
					.allowsHitTesting(false)
			}
		}
		.sheet(isPresented: isShowingSignIn) {
			NavigationView {
				VStack(spacing: 0) {
					Text("Riot Support needs you to sign in once. Tap **Sign In** on the page below; you'll stay signed in afterwards.")
						.font(.footnote)
						.foregroundStyle(.secondary)
						.padding(12)
					RiotSupportWebView(loader: loader)
				}
				.navigationTitle("Riot Support")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Cancel") { isShowingSignIn.wrappedValue = false }
					}
					ToolbarItem(placement: .primaryAction) {
						Button { loader.reloadPage() } label: { Image(systemName: "arrow.clockwise") }
					}
				}
			}
		}
		.refreshable {
			await loadHistory()
		}
		.task {
			if history == nil {
				await loadHistory()
			}
		}
		.onDisappear { loader.stop() }
	}
	
	@ViewBuilder
	private func paymentsSections(_ entries: [PurchaseHistory.PaymentHistoryEntry]) -> some View {
		let filtered = entries
			.sorted { $0.dateCreated > $1.dateCreated }
			.filter {
				search.isEmpty
					|| $0.currency.localizedCaseInsensitiveContains(search)
					|| $0.paymentMethodID.localizedCaseInsensitiveContains(search)
					|| "\($0.amount)".localizedCaseInsensitiveContains(search)
			}
		
		let groupedByCurrency = Dictionary(grouping: filtered, by: \.currency)
		if !groupedByCurrency.isEmpty {
			Section("Total Spent") {
				ForEach(groupedByCurrency.keys.sorted(), id: \.self) { currency in
					let sum = groupedByCurrency[currency, default: []].reduce(Decimal(0)) { $0 + $1.amount }
					HStack {
						Text(currency)
							.font(.headline)
						Spacer()
						Text(formattedAmount(sum, currency: currency))
							.font(.headline.monospacedDigit())
							.foregroundStyle(Color.accentColor)
					}
				}
			}
		}
		
		Section("Real-Money Payments (\(filtered.count))") {
			if filtered.isEmpty {
				Text("No recorded real-money payments.")
					.foregroundStyle(.secondary)
			} else {
				ForEach(filtered) { entry in
					HStack {
						VStack(alignment: .leading, spacing: 3) {
							Text(entry.paymentMethodID.isEmpty ? entry.storefrontAccountCode : entry.paymentMethodID)
								.font(.body.weight(.medium))
							Text(entry.dateCreated.formatted(date: .abbreviated, time: .shortened))
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Text(formattedAmount(entry.amount, currency: entry.currency))
							.font(.subheadline.bold().monospacedDigit())
					}
					.padding(.vertical, 2)
				}
			}
		}
	}
	
	@ViewBuilder
	private func walletSections(_ transactions: [PurchaseHistory.WalletTransaction]) -> some View {
		let sorted = transactions.sorted { $0.createdTime > $1.createdTime }
		let filtered = search.isEmpty ? sorted : sorted.filter {
			$0.createdTime.formatted(date: .abbreviated, time: .omitted)
				.localizedCaseInsensitiveContains(search)
				|| $0.deltas.contains { delta in
					"\(delta.amount ?? 0)".localizedCaseInsensitiveContains(search)
						|| currencyName(delta.type)?.localizedCaseInsensitiveContains(search) == true
				}
		}
		let totals = WalletTotals(transactions: filtered)
		let currencyIDs = totals.currencyIDs
		
		if !currencyIDs.isEmpty {
			Section {
				HStack(alignment: .top, spacing: 28) {
					totalsColumn("Spent", sign: "-", amounts: totals.spent, currencyIDs: currencyIDs)
					totalsColumn("Earned", sign: "+", amounts: totals.earned, currencyIDs: currencyIDs)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 10)
			}
		}
		
		Section("Transactions (\(filtered.count))") {
			if filtered.isEmpty {
				Text("No wallet delta entries recorded.")
					.foregroundStyle(.secondary)
			} else {
				ForEach(filtered) { tx in
					HStack(alignment: .firstTextBaseline) {
						Text(tx.createdTime.formatted(date: .abbreviated, time: .omitted))
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Spacer()
						VStack(alignment: .trailing, spacing: 4) {
							ForEach(Array(tx.deltas.enumerated()), id: \.offset) { _, delta in
								HStack(spacing: 5) {
									if let amt = delta.amount {
										Text(amt > 0 ? "+\(amt)" : "\(amt)")
											.font(.subheadline.bold().monospacedDigit())
											.foregroundStyle(amt > 0 ? Color.green : Color.red)
									}
									currencyIcon(delta.type)
								}
							}
						}
					}
					.padding(.vertical, 2)
				}
			}
		}
	}
	
	@ViewBuilder
	private func totalsColumn(
		_ title: String,
		sign: String,
		amounts: [Currency.ID: Int],
		currencyIDs: [Currency.ID]
	) -> some View {
		VStack(spacing: 6) {
			ForEach(currencyIDs, id: \.self) { id in
				HStack(spacing: 5) {
					if let amount = amounts[id], amount != 0 {
						Text(sign + "\(amount)")
							.font(.headline.monospacedDigit())
							.foregroundStyle(sign == "+" ? Color.green : Color.red)
					} else {
						Text("—")
							.font(.headline)
							.foregroundStyle(.tertiary)
					}
					currencyIcon(id, size: 18)
				}
			}
			Text(title)
				.font(.caption2.weight(.medium))
				.foregroundStyle(.secondary)
				.textCase(.uppercase)
		}
		.frame(maxWidth: .infinity)
	}
	
	/// the currency icons are white glyphs, so they only show up when drawn as templates
	@ViewBuilder
	private func currencyIcon(_ id: Currency.ID, size: CGFloat = 16) -> some View {
		if let icon = assets?.currencies[id]?.displayIcon {
			icon.view(renderingMode: .template)
				.foregroundStyle(.secondary)
				.frame(width: size, height: size)
		} else {
			Color.clear
				.frame(width: size, height: size)
		}
	}
	
	private func currencyName(_ id: Currency.ID) -> String? {
		assets?.currencies[id]?.displayNamePlural
	}
	
	private struct WalletTotals {
		var spent: [Currency.ID: Int] = [:]
		var earned: [Currency.ID: Int] = [:]
		
		init(transactions: [PurchaseHistory.WalletTransaction]) {
			for transaction in transactions {
				for delta in transaction.deltas {
					guard let amount = delta.amount, amount != 0 else { continue }
					if amount > 0 {
						earned[delta.type, default: 0] += amount
					} else {
						spent[delta.type, default: 0] -= amount
					}
				}
			}
		}
		
		/// the currencies that show up at all, in a stable, familiar order
		var currencyIDs: [Currency.ID] {
			let known: [Currency.ID] = [.valorantPoints, .radianitePoints, .kingdomCredits]
			let present = Set(spent.keys).union(earned.keys)
			let knownPresent = known.filter(present.contains)
			let others = present.subtracting(known).sorted { $0.description < $1.description }
			return knownPresent + others
		}
	}
	
	private func formattedAmount(_ amount: Decimal, currency: String) -> String {
		let number = NSDecimalNumber(decimal: amount)
		let formatter = NumberFormatter()
		formatter.numberStyle = .currency
		formatter.currencyCode = currency
		return formatter.string(from: number) ?? "\(amount) \(currency)"
	}
	
	private func loadHistory() async {
		guard let client = accountManager.activeAccount?.client else {
			loader.state = .failed("Sign in to load purchase history.")
			return
		}
		await loader.start(cookies: await client.getSessionCookies())
	}
}
