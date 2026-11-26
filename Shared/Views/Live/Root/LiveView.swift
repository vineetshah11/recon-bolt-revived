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
	@State fileprivate var storeInfo: StoreInfo?
	@State private var accountXP: AccountXP?
	@State private var activeRecruitment: ActiveRecruitmentEvent?
	@State private var agentMastery: AgentMastery?
	@State private var resolvedContracts: ResolvedContracts?
	@State private var contractsGeneration = 0
	
	@UserDefault.State("LiveView.expandedBoxes")
	var expandedBoxes: Set<Box> = [.party]
	
	@LocalData var user: User?
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.favoritesManagerRef) private var favoritesManager
	@Environment(\.progressTimelineStoreRef) private var progressTimelineStore
	
	@Namespace private var missionsBoxID
	@Namespace private var storeBoxID
	
	private struct ContractRefreshKey: Hashable {
		let generation: Int
		let assetsVersion: AssetVersion?
		let currentActID: Act.ID?
	}
	
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
			}
			.background(Color.groupedBackground)
			.deepLinkHandler { handle($0, scrollView: scrollView) }
		}
		.navigationTitle("Live")
		.withLocalData($user, id: userID)
		.id(userID) // when user changes, current state is bound to become invalid/irrelevant
		.updatingGameConfig()
		.task(id: ContractRefreshKey(
			generation: contractsGeneration,
			assetsVersion: assets?.version,
			currentActID: seasons?.currentAct()?.id
		)) {
			resolvedContracts = contractsProgress.map {
				ResolvedContracts(progress: $0, assets: assets, seasons: seasons)
			}
		}
	}
	
	var missionsBox: some View {
		RefreshableBox(title: "Contracts", isExpanded: $expandedBoxes.contains(.missions)) {
			infoOrPlaceholder(placeholder: "Contracts not loaded!", contractsProgress) { progress in
				let resolved = resolvedContracts ?? ResolvedContracts(progress: progress, assets: assets, seasons: seasons)
				ContractDetailsView(
					contracts: resolved,
					userID: userID,
					accountXP: accountXP,
					activeRecruitment: activeRecruitment,
					agentMastery: agentMastery
				)
			}
		} refresh: { client in
			async let progressTask = client.getContractsProgress()
			async let xpTask = try? client.getAccountXP()
			async let recruitmentTask = try? client.getActiveRecruitmentEvent()
			async let masteryTask = try? client.getAgentMastery()
			let (progress, xp, recruitment, mastery) = try await (progressTask, xpTask, recruitmentTask, masteryTask)
			contractsProgress = progress
			contractsGeneration &+= 1
			resolvedContracts = ResolvedContracts(progress: progress, assets: assets, seasons: seasons)
			accountXP = xp
			if let xp {
				progressTimelineStore?.record(accountXP: xp, for: userID)
			}
			activeRecruitment = recruitment
			agentMastery = mastery
		}
		.id(missionsBoxID)
	}
	
	var loadoutBox: some View {
		RefreshableBox(title: "Loadout", isExpanded: $expandedBoxes.contains(.loadout)) {
			infoOrPlaceholder(placeholder: "Loadout not loaded!", loadoutInfo) { info in
				LoadoutDetailsView(loadout: info.loadout, inventory: info.inventory)
			}
		} refresh: { client in
			do {
				loadoutInfo = try await .init(using: client)
				await favoritesManager?.refresh(using: client)
			} catch Loadout.FetchError.uninitialized {
				throw WrongAccountError(user: user)
			}
		}
	}
	
	var storeBox: some View {
		RefreshableBox(title: "Store", isExpanded: $expandedBoxes.contains(.store)) {
			infoOrPlaceholder(placeholder: "Store not loaded!", storeInfo) { info in
				StoreDetailsView(
					updateTime: info.updateTime,
					storefront: info.storefront, wallet: info.wallet
				)
			}
		} refresh: {
			let fetched = try await StoreInfo(using: $0)
			storeInfo = fetched
			progressTimelineStore?.record(wallet: fetched.wallet, for: userID)
		}
		.id(storeBoxID)
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
	var inventory: Inventory
	
	init(using client: ValorantClient) async throws {
		async let loadout = client.getLoadout()
		async let inventory = client.getInventory()
		self.loadout = try await loadout <- LocalDataProvider.dataFetched
		self.inventory = try await inventory
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
		.environmentObject(FavoritesManager())
		.environmentObject(ProgressTimelineStore())
		.withToolbar()
	}
}
#endif
