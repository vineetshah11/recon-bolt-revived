import SwiftUI
import ValorantAPI

struct AccountOverviewView: View {
	@ObservedObject var accountManager: AccountManager
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@EnvironmentObject private var progressTimelineStore: ProgressTimelineStore
	
	@State private var snapshots: [User.ID: AccountSnapshot] = [:]
	@State private var isRefreshing = false
	@State private var switchError: Error?
	
	struct AccountSnapshot {
		var accountXP: AccountXP?
		var contractsProgress: ContractsProgress?
		var summary: CareerSummary?
		var loadError: String?
		var isLoading = false
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 14) {
				if accountManager.storedAccounts.isEmpty {
					emptyState
				} else {
					ForEach(accountManager.storedAccounts, id: \.self) { accountID in
						AccountOverviewCard(
							accountID: accountID,
							isActive: accountManager.activeAccount?.id == accountID,
							snapshot: snapshots[accountID]
						) {
							switchToAccount(accountID)
						}
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground.ignoresSafeArea())
		.navigationTitle("Account Overview")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				if isRefreshing {
					ProgressView()
				}
			}
		}
		.task(id: accountManager.storedAccounts) {
			await refreshAllAccounts()
		}
		.refreshable {
			await refreshAllAccounts()
		}
		.alert(Text("Could Not Switch Account!"), for: $switchError)
	}
	
	private var emptyState: some View {
		VStack(spacing: 8) {
			Image(systemName: "person.2.slash")
				.font(.title2)
				.foregroundStyle(.secondary)
			Text("No Stored Accounts")
				.font(.headline)
			Text("Add an account in Settings to compare your rank, level, and missions across all your accounts.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(24)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	@MainActor
	private func switchToAccount(_ accountID: User.ID) {
		do {
			try withAnimation {
				try accountManager.setActive(accountID)
			}
		} catch {
			switchError = error
		}
	}
	
	@MainActor
	private func refreshAllAccounts() async {
		let accounts = accountManager.storedAccounts
		guard !accounts.isEmpty, !isRefreshing else { return }
		isRefreshing = true
		defer { isRefreshing = false }
		
		for accountID in accounts {
			var existing = snapshots[accountID] ?? AccountSnapshot()
			existing.isLoading = true
			existing.loadError = nil
			snapshots[accountID] = existing
		}
		
		let tasks: [(User.ID, Task<AccountSnapshot, Never>)] = accounts.map { accountID in
			let client: ValorantClient? = (accountManager.activeAccount?.id == accountID)
				? accountManager.activeAccount?.client
				: accountManager.makeReadOnlyClient(for: accountID)
			let task = Task { @MainActor in
				await Self.fetchSnapshot(for: accountID, using: client)
			}
			return (accountID, task)
		}
		
		for (accountID, task) in tasks {
			let result = await task.value
			snapshots[accountID] = result
			
			if let summary = result.summary {
				LocalDataProvider.shared.careerSummaryManager.store(summary, asOf: .now)
				progressTimelineStore.record(summary: summary, seasons: seasons, for: accountID)
			}
			if let xp = result.accountXP {
				progressTimelineStore.record(accountXP: xp, for: accountID)
			}
		}
	}
	
	private static func fetchSnapshot(
		for accountID: User.ID,
		using client: ValorantClient?
	) async -> AccountSnapshot {
		guard let client else {
			return AccountSnapshot(
				loadError: "Session missing — switch to sign in.",
				isLoading: false
			)
		}
		
		async let xpTask = try? client.getAccountXP()
		async let contractsTask = try? client.getContractsProgress()
		async let summaryTask = try? client.getCareerSummary(userID: accountID)
		async let identityTask: ()? = try? client.fetchIdentity(for: accountID, forceFetch: false)
		async let userTask: ()? = try? client.fetchUsers(for: [accountID])
		
		let (xp, contracts, summary, _, _) = await (
			xpTask,
			contractsTask,
			summaryTask,
			identityTask,
			userTask
		)
		
		let loadError: String? = (xp == nil && contracts == nil && summary == nil)
			? "Could not refresh — session may have expired."
			: nil
		
		return AccountSnapshot(
			accountXP: xp,
			contractsProgress: contracts,
			summary: summary,
			loadError: loadError,
			isLoading: false
		)
	}
}

private struct AccountOverviewCard: View {
	let accountID: User.ID
	let isActive: Bool
	let snapshot: AccountOverviewView.AccountSnapshot?
	let onSwitch: () -> Void
	
	@LocalData var identity: Player.Identity?
	@LocalData var cachedSummary: CareerSummary?
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	
	init(
		accountID: User.ID,
		isActive: Bool,
		snapshot: AccountOverviewView.AccountSnapshot?,
		onSwitch: @escaping () -> Void
	) {
		self.accountID = accountID
		self.isActive = isActive
		self.snapshot = snapshot
		self.onSwitch = onSwitch
		self._identity = .init(id: accountID)
		self._cachedSummary = .init(id: accountID)
	}
	
	var body: some View {
		let activeSummary = snapshot?.summary ?? cachedSummary
		let currentAct = seasons?.currentAct()
		let seasonInfo = currentAct.flatMap { activeSummary?.competitiveInfo?.inSeason($0.id) }
		let tier = seasonInfo?.competitiveTier ?? 0
		let rr = seasonInfo?.adjustedRankedRating ?? 0
		let tierInfo = currentAct.flatMap { assets?.seasons.tierInfo(number: tier, in: $0.id) }
		
		let level = snapshot?.accountXP?.progress.level ?? identity?.accountLevel
		let currentXP = max(0, min(5_000, snapshot?.accountXP?.progress.xp ?? 0))
		let xpRatio = Double(currentXP) / Double(5_000)
		
		let resolvedContracts = snapshot?.contractsProgress.map {
			ResolvedContracts(progress: $0, assets: assets, seasons: seasons)
		}
		
		VStack(alignment: .leading, spacing: 14) {
			headerRow
			
			rankAndLevelRow(
				tier: tier,
				rr: rr,
				tierInfo: tierInfo,
				level: level,
				xp: snapshot?.accountXP != nil ? currentXP : nil,
				xpRatio: xpRatio
			)
			
			Divider()
				.opacity(0.35)
			
			progressRows(resolved: resolvedContracts)
			
			if let loadError = snapshot?.loadError {
				Text(loadError)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		.withLocalData($identity, id: accountID, shouldAutoUpdate: false)
		.withLocalData($cachedSummary, id: accountID, shouldAutoUpdate: false)
	}
	
	private var headerRow: some View {
		HStack(spacing: 10) {
			PlayerCardImage.small(identity?.cardID)
				.frame(width: 38, height: 38)
				.cornerRadius(8)
			
			UserLabel(userID: accountID, shouldAutoUpdate: false, allowTapToCopy: false)
				.font(.headline)
				.lineLimit(1)
			
			Spacer(minLength: 8)
			
			if isActive {
				HStack(spacing: 5) {
					Image(systemName: "checkmark.circle.fill")
						.font(.subheadline)
					Text("Active")
						.font(.subheadline.weight(.semibold))
				}
				.foregroundStyle(Color.accentColor)
			} else {
				Button(action: onSwitch) {
					Text("Switch")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(Color.accentColor)
						.padding(.horizontal, 14)
						.padding(.vertical, 6)
						.background(Color.accentColor.opacity(0.18), in: Capsule())
				}
				.buttonStyle(.plain)
			}
		}
	}
	
	private func rankAndLevelRow(
		tier: Int,
		rr: Int,
		tierInfo: CompetitiveTier?,
		level: Int?,
		xp: Int?,
		xpRatio: Double
	) -> some View {
		HStack(alignment: .center, spacing: 12) {
			HStack(spacing: 10) {
				if let tierInfo {
					CompetitiveTierImage(tierInfo: tierInfo)
						.frame(width: 36, height: 36)
				} else {
					Circle()
						.fill(Color.tertiaryGroupedBackground)
						.overlay {
							Circle()
								.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
						}
						.frame(width: 36, height: 36)
				}
				
				VStack(alignment: .leading, spacing: 2) {
					Text(tier >= 3 ? (tierInfo?.name ?? "Ranked") : "Unranked")
						.font(.subheadline.weight(.semibold))
					if tier >= 3 {
						Text("\(rr) RR")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					}
				}
			}
			
			Spacer(minLength: 12)
			
			VStack(alignment: .trailing, spacing: 5) {
				Text(level.map { "Level \($0)" } ?? "Level —")
					.font(.subheadline.weight(.semibold).monospacedDigit())
				
				GeometryReader { geo in
					ZStack(alignment: .leading) {
						Capsule()
							.fill(Color.secondary.opacity(0.25))
						if xp != nil, xpRatio > 0 {
							Capsule()
								.fill(Color.primary)
								.frame(width: max(4, geo.size.width * CGFloat(xpRatio)))
						}
					}
				}
				.frame(width: 84, height: 4)
			}
		}
	}
	
	@ViewBuilder
	private func progressRows(resolved: ResolvedContracts?) -> some View {
		VStack(spacing: 10) {
			overviewRow(title: "Daily Checkpoints") {
				if let resolved {
					let completed = resolved.daily.milestones.count(where: \.isComplete)
					let total = resolved.daily.milestones.count
					Text("\(completed)/\(total)")
						.font(.subheadline.monospacedDigit())
						.foregroundStyle(.secondary)
				} else {
					loadingValuePlaceholder
				}
			}
			
			overviewRow(title: "Weekly Missions") {
				if let resolved {
					HStack(spacing: 8) {
						let completed = resolved.weeklies.count(where: \.mission.isComplete)
						let total = resolved.weeklies.count
						Text("\(completed)/\(total)")
							.monospacedDigit()
						if let weeklyRefresh = resolved.weeklyRefresh, weeklyRefresh > Date() {
							HStack(spacing: 3) {
								Image(systemName: "clock")
								CountdownText(target: weeklyRefresh)
							}
						}
					}
					.font(.subheadline)
					.foregroundStyle(.secondary)
				} else {
					loadingValuePlaceholder
				}
			}
			
			overviewRow(title: "Battle Pass") {
				if let resolved, let (bpInfo, bpContract) = currentBattlePass(from: resolved) {
					let progress = PassPlanner.levelProgress(
						contract: bpInfo,
						details: bpContract,
						includeEpilogue: true
					)
					Text("Level \(progress.currentLevel) / \(progress.totalLevels)")
						.font(.subheadline.monospacedDigit())
						.foregroundStyle(.secondary)
				} else {
					loadingValuePlaceholder
				}
			}
			
			overviewRow(title: "First Win of the Day") {
				if let xp = snapshot?.accountXP {
					if let next = xp.nextTimeFirstWinAvailable, next > Date() {
						HStack(spacing: 4) {
							Image(systemName: "clock")
							CountdownText(target: next)
						}
						.font(.subheadline)
						.foregroundStyle(.secondary)
					} else {
						Text("Available")
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.green)
					}
				} else {
					loadingValuePlaceholder
				}
			}
		}
	}
	
	private var loadingValuePlaceholder: some View {
		Group {
			if snapshot?.isLoading == true {
				ProgressView()
					.controlSize(.mini)
			} else {
				Text("—")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
	}
	
	private func overviewRow<Value: View>(
		title: LocalizedStringKey,
		@ViewBuilder value: () -> Value
	) -> some View {
		HStack {
			Text(title)
				.font(.subheadline)
				.foregroundStyle(.secondary)
			Spacer(minLength: 8)
			value()
		}
	}
	
	private func currentBattlePass(from resolved: ResolvedContracts) -> (ContractInfo, Contract?)? {
		guard let assets else { return nil }
		let progressByID = Dictionary(uniqueKeysWithValues: resolved.details.contracts.map { ($0.id, $0) })
		let currentActID = seasons?.currentAct()?.id
		
		let seasonContracts = assets.contracts.values.filter { $0.content.relationType == .season }
		if let currentActID,
		   let active = seasonContracts.first(where: { $0.content.seasonID == currentActID }) {
			return (active, progressByID[active.id])
		}
		if let specialID = resolved.details.activeSpecialContract,
		   let special = assets.contracts[specialID],
		   special.content.relationType == .season {
			return (special, progressByID[specialID])
		}
		if let matched = seasonContracts.first(where: { progressByID[$0.id] != nil }) ?? seasonContracts.last {
			return (matched, progressByID[matched.id])
		}
		return nil
	}
}

#if DEBUG
struct AccountOverviewView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			AccountOverviewView(accountManager: .mocked)
		}
		.environmentObject(ProgressTimelineStore())
		.withToolbar()
	}
}
#endif
