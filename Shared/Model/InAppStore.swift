import StoreKit
import HandyOperators
import UserDefault
import WidgetKit

// MARK: - REVIVAL NOTE
// The original app had a "Pro" in-app purchase gating certain features.
// For this personal revival build, ALL features are unlocked for free.
// The StoreKit machinery is kept intact but ownsProVersion always returns true.

@MainActor
final class InAppStore: ObservableObject {
	@UserDefault("ownedProducts", migratingTo: .shared)
	private var storedProducts: Set<Product.ID> = [] {
		didSet {
			#if !WIDGETS
			if ownedProducts != oldValue {
				WidgetCenter.shared.reloadAllTimelines()
			}
			#endif
		}
	}
	
	@Published
	private(set) var proVersion = ResolvableProduct(id: "ReconBolt.Pro")
	
	// REVIVAL: Always returns true — all Pro features are free in this build.
	var ownsProVersion: Bool { true }
	
	private var updateListenerTask: Task<Void, Never>? = nil
	
	@Published
	private var ownedProducts: Set<Product.ID> {
		didSet { storedProducts = ownedProducts }
	}
	
	init(isReadOnly: Bool = false) {
		ownedProducts = _storedProducts.wrappedValue
		
		if !isReadOnly {
			updateListenerTask = listenForTransactions()
			
			Task {
				var owned: Set<Product.ID> = []
				for await existing in Transaction.currentEntitlements {
					guard let transaction = try? existing.payloadValue else { continue }
					print("found existing transaction for \(transaction.productID)")
					update(&owned, from: transaction)
				}
				ownedProducts = owned
			}
			
			Task { await fetchProducts() }
		}
	}
	
	deinit {
		updateListenerTask?.cancel()
	}
	
	func fetchProducts() async {
		do {
			let products = try await Product.products(for: [proVersion.id])
			try proVersion.resolve(from: products)
		} catch {
			// Silently ignore — no App Store connection needed for this build
			print("fetchProducts skipped (revival build):", error)
		}
	}
	
	func owns(_ product: ResolvableProduct) -> Bool {
		// REVIVAL: All products are owned for free in this build
		true
	}
	
	func purchase(_ product: Product) async throws {
		// REVIVAL: No purchase needed — features are already unlocked
		print("purchase() called but not needed in revival build")
	}
	
	func restorePurchase(for product: ResolvableProduct) async throws {
		// REVIVAL: Nothing to restore — everything is free
		print("restorePurchase() called but not needed in revival build")
	}
	
	private func listenForTransactions() -> Task<Void, Never> {
		.detached { [weak self] in
			for await result in Transaction.updates {
				do {
					guard let self else { break }
					print("received", result)
					let transaction = try result.payloadValue
					await self.update(from: transaction)
					await transaction.finish()
				} catch {
					print("error processing listened transaction:", error)
				}
			}
		}
	}
	
	private func update(from transaction: Transaction) {
		update(&ownedProducts, from: transaction)
	}
	
	private func update(_ products: inout Set<Product.ID>, from transaction: Transaction) {
		if transaction.revocationDate == nil {
			products.insert(transaction.productID)
		} else {
			products.remove(transaction.productID)
		}
	}
}

enum PurchaseRestorationError: LocalizedError {
	case noTransaction
	case transactionRevoked(Transaction.RevocationReason)
	case errorVerifying(Error)
	
	var errorDescription: String? {
		switch self {
		case .noTransaction:
			return String(
				localized: "No previous transaction found!",
				table: "Errors",
				comment: "Pro Store: error restoring purchase"
			)
		case .transactionRevoked(let reason):
			let description: String
			if #available(iOS 15.4, *) {
				description = reason.localizedDescription
			} else {
				description = String(
					localized: "Update to iOS 15.4 to see the reason!",
					table: "Errors",
					comment: "Pro Store: error restoring purchase: replacement for revokation reason on outdated iOS where it's not available"
				)
			}
			return String(
				localized: "Previous purchase was revoked! Reason: \(description)",
				table: "Errors",
				comment: "Pro Store: error restoring purchase (placeholder is reason why it was revoked)"
			)
		case .errorVerifying(let error):
			return String(
				localized: "A previous transaction was found, but it could not be verified! \(error.localizedDescription)",
				table: "Errors",
				comment: "Pro Store: error restoring purchase"
			)
		}
	}
}

struct ResolvableProduct {
	let id: Product.ID
	private(set) var resolved: Product?
	
	mutating func resolve<S>(from products: S) throws where S: Sequence, S.Element == Product {
		if let match = products.first(where: { $0.id == id }) {
			resolved = match
		} else {
			print("could not resolve product with id \(id)")
		}
	}
	
	enum ResolutionError: Error {
		case noProductWithID(Product.ID)
	}
}
