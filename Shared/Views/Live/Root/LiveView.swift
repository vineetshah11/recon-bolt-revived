import SwiftUI
import WidgetKit
import ValorantAPI
import HandyOperators
import UserDefault

struct LiveView: View {
	let userID: User.ID
	@State var contractsProgress: ContractsProgress? {
		didSet {
			if let oldValue, let contractsProgress, contractsProgress.contracts != oldValue.contracts {
				WidgetCenter.shared.reloadTimelines(ofKind: "view missions")
			}
		}
	}
	@State fileprivate var loadoutInfo: LoadoutInfo?
	@State fileprivate var loadoutError: String?
	@State fileprivate var storeInfo: StoreInfo?
	
	@UserDefault.State("LiveView.expandedBoxes")
	var expandedBoxes: Set<Box> = [.party]
	
	@LocalData var user: User?
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.accountManager) private var accountManager
	
	@Namespace private var missionsBoxID
	@Namespace private var storeBoxID
	
	var body: some View {
		ScrollViewReader { scrollView in
			ScrollView {
				VStack(spacing: 16) {
					LiveGameBox(userID: userID, isExpanded: $expandedBoxes.contains(.party))
					
					missionsBox
					
					loadoutBox
					
					storeBox
				}
				.padding()
				.compositingGroup() // avoid shadows overlapping other boxes
				.shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
			}
			.background(Color.groupedBackground)
			.deepLinkHandler { handle($0, scrollView: scrollView) }
		}
		.navigationTitle("Live")
		.withLocalData($user, id: userID)
		.id(userID) // when user changes, current state is bound to become invalid/irrelevant
		.updatingGameConfig()
	}
	
	var missionsBox: some View {
		RefreshableBox(title: "Missions", isExpanded: $expandedBoxes.contains(.missions)) {
			infoOrPlaceholder(placeholder: "Missions didn't load", contractsProgress) {
				ContractDetailsView(contracts: .init(progress: $0, assets: assets, seasons: seasons))
			}
		} refresh: {
			contractsProgress = try await $0.getContractsProgress()
		}
		.id(missionsBoxID)
	}
	
	var loadoutBox: some View {
		RefreshableBox(title: "Loadout", isExpanded: $expandedBoxes.contains(.loadout)) {
			if let loadoutInfo {
				LoadoutDetailsView(loadout: loadoutInfo.loadout, inventory: loadoutInfo.inventory)
			} else {
				Divider()
				LoadoutUnavailableView(reason: loadoutError)
			}
		} refresh: {
			do {
				loadoutInfo = try await .init(using: $0)
				loadoutError = nil
			} catch Loadout.FetchError.uninitialized {
				loadoutInfo = nil
				loadoutError = nil
				throw WrongAccountError(user: user)
			} catch APIError.badResponseCode(404, _, _), APIError.resourceNotFound {
				// Riot's personalization service can't find anything for requests carrying an outdated
				// client version, so try once more with a freshly fetched one before giving up.
				loadoutInfo = nil
				loadoutError = nil
				if
					let version = await AccountManager.fetchLatestClientVersion(),
					version != $0.clientVersion
				{
					if let accountManager {
						await MainActor.run { accountManager.clientVersion = version }
					}
					
					var retryClient = $0
					retryClient.clientVersion = version
					loadoutInfo = try? await LoadoutInfo(using: retryClient)
				}
				if loadoutInfo == nil {
					loadoutError = String(
						localized: "Riot didn't return a loadout for this account (404). Loadouts are only available for the signed-in account, in its own region.",
						comment: "Loadout box: reason shown when Riot answers with 404"
					)
				}
			} catch {
				guard !Task.isCancelled else { return }
				loadoutInfo = nil
				loadoutError = Self.message(for: error)
			}
		}
	}
	
	var storeBox: some View {
		RefreshableBox(title: "Store", isExpanded: $expandedBoxes.contains(.store)) {
			infoOrPlaceholder(placeholder: "Store didn't load", storeInfo) { info in
				StoreDetailsView(
					updateTime: info.updateTime,
					storefront: info.storefront, wallet: info.wallet
				)
			}
		} refresh: {
			storeInfo = try await .init(using: $0)
		}
		.id(storeBoxID)
	}
	
	private static func message(for error: Error) -> String {
		if let apiError = error as? APIError, apiError.recommendsReauthentication {
			return String(
				localized: "Your Riot session has expired. Sign in again to load your loadout.",
				comment: "Loadout box: shown when the session has expired"
			)
		}
		if error is DecodingError {
			return String(
				localized: "Riot's response couldn't be read. The app's copy of the Valorant API library is likely outdated.",
				comment: "Loadout box: shown when the loadout response fails to decode"
			)
		}
		return error.localizedDescription
	}
	
	func handle(_ link: DeepLink, scrollView: ScrollViewProxy) {
		switch link {
		case .widget(let link):
			switch link.destination {
			case .missions:
				expandedBoxes.insert(.missions)
				scrollView.scrollTo(missionsBoxID)
			case .store:
				expandedBoxes.insert(.store)
				scrollView.scrollTo(storeBoxID)
			default:
				break
			}
		default:
			break
		}
	}
	
	@ViewBuilder
	func infoOrPlaceholder<Data, Content: View>(
		placeholder: LocalizedStringKey,
		_ data: Data?,
		@ViewBuilder content: (Data) -> Content
	) -> some View {
		if let data {
			content(data)
		} else {
			Divider()
			
			GroupBox {
				Text(placeholder)
					.foregroundColor(.secondary)
			}
			.padding(16)
		}
	}
	
	enum Box: String, Hashable, DefaultsValueConvertible {
		typealias DefaultsRepresentation = String
		
		case party
		case missions
		case loadout
		case store
	}
}

extension LiveView {
	init(userID: User.ID) {
		self.init(userID: userID, user: .init(id: userID))
	}
}

private struct LoadoutUnavailableView: View {
	var reason: String?
	
	var body: some View {
		VStack(spacing: 8) {
			Image(systemName: "shippingbox")
				.font(.title2)
				.foregroundColor(.secondary)
			
			Text("Loadout didn't load", comment: "Live: loadout box placeholder")
				.font(.headline)
			
			if let reason {
				Text(reason)
					.font(.caption)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
			}
			
			Text("Tap the refresh button above to try again.", comment: "Live: loadout box placeholder hint")
				.font(.caption)
				.foregroundColor(.secondary)
		}
		.padding()
		.frame(maxWidth: .infinity)
	}
}

private struct WrongAccountError: Error, LocalizedError {
	var user: User?
	
	var errorDescription: String? {
		let accountDesc: String
		if let user {
			accountDesc = String(localized: "this one is:\n\n\(user.name)", table: "Errors", comment: "wrong account error")
		} else {
			accountDesc = String(localized: "this one has no Riot ID & Tagline.", table: "Errors", comment: "wrong account error")
		}
		return String(
			localized: """
			It looks like this account has never played Valorant!

			You've probably signed into the wrong account; \(accountDesc)
			""",
			table: "Errors",
			comment: "wrong account error"
		)
	}
}

private struct LoadoutInfo {
	var loadout: Loadout
	/// Only needed for editing, so a failure here doesn't take the whole loadout down.
	var inventory: Inventory?
	
	init(using client: ValorantClient) async throws {
		async let loadout = client.getLoadout()
		self.inventory = try? await client.getInventory()
		self.loadout = try await loadout
	}
}

private struct StoreInfo {
	var updateTime: Date
	var storefront: Storefront
	var wallet: StoreWallet
}

extension StoreInfo {
	init(using client: ValorantClient) async throws {
		async let storefront = client.getStorefront()
		async let wallet = client.getStoreWallet()
		
		self.storefront = try await storefront
		self.wallet = try await wallet
		self.updateTime = .now
	}
}

struct ActiveMatch: Hashable {
	var id: Match.ID
	var inPregame: Bool
}

extension ValorantClient {
	func getActiveMatch() async throws -> ActiveMatch? {
		async let liveGame = getLiveMatch(inPregame: false)
		async let livePregame = getLiveMatch(inPregame: true)
		
		if let match = try await liveGame {
			return .init(id: match, inPregame: false)
		} else if let match = try await livePregame {
			return .init(id: match, inPregame: true)
		} else {
			return nil
		}
	}
}

#if DEBUG
struct LiveView_Previews: PreviewProvider {
	static var previews: some View {
		LiveView(
			userID: PreviewData.userID,
			contractsProgress: PreviewData.contractsProgress
		)
		.withToolbar()
	}
}
#endif
