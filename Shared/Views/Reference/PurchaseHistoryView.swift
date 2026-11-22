import SwiftUI
import ValorantAPI

struct PurchaseHistoryView: View {
	enum Tab: String, CaseIterable, Identifiable {
		case payments = "Payments"
		case transactions = "Wallet Deltas"
		
		var id: String { rawValue }
	}
	
	@EnvironmentObject private var accountManager: AccountManager
	@Environment(\.assets) private var assets
	
	@State private var tab: Tab = .payments
	@State private var history: PurchaseHistory?
	@State private var isLoading = false
	@State private var errorMessage: String?
	@State private var search = ""
	
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
						ProgressView("Loading from Riot Player Support...")
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
		.refreshable {
			await loadHistory()
		}
		.task {
			if history == nil {
				await loadHistory()
			}
		}
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
		
		Section("Wallet Transactions (\(sorted.count))") {
			if sorted.isEmpty {
				Text("No wallet delta entries recorded.")
					.foregroundStyle(.secondary)
			} else {
				ForEach(sorted) { tx in
					HStack(alignment: .top) {
						Text(tx.createdTime.formatted(date: .abbreviated, time: .shortened))
							.font(.caption)
							.foregroundStyle(.secondary)
						Spacer()
						VStack(alignment: .trailing, spacing: 4) {
							ForEach(Array(tx.deltas.enumerated()), id: \.offset) { _, delta in
								HStack(spacing: 6) {
									if let amt = delta.amount {
										Text(amt > 0 ? "+\(amt)" : "\(amt)")
											.font(.subheadline.bold().monospacedDigit())
											.foregroundStyle(amt > 0 ? Color.green : Color.red)
									}
									(assets?.currencies[delta.type]?.displayIcon).view()
										.frame(width: 16, height: 16)
								}
							}
						}
					}
					.padding(.vertical, 2)
				}
			}
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
			errorMessage = "Sign in to load purchase history."
			return
		}
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }
		
		do {
			history = try await client.getPurchaseHistory()
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
