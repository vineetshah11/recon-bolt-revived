import SwiftUI
import ValorantAPI

struct ContractDetailsView: View {
	enum SectionTab: String, CaseIterable, Identifiable {
		case missions = "Missions"
		case battlePass = "Battle Pass"
		case newAgent = "New Agent"
		case account = "Account"
		case agents = "Agents"
		
		var id: String { rawValue }
	}
	
	var contracts: ResolvedContracts
	var userID: User.ID? = nil
	var accountXP: AccountXP? = nil
	var activeRecruitment: ActiveRecruitmentEvent? = nil
	var agentMastery: AgentMastery? = nil
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	
	@State private var selectedTab: SectionTab = .missions
	@State private var includeEpilogue = true
	@State private var cachedMasterySummaries: [AgentMasterySummary] = []
	@State private var cachedMasteryActEndDate: Date?
	
	private struct MasteryCacheKey: Equatable {
		var isAgentsTab: Bool
		var userID: User.ID?
		var mastery: AgentMastery?
		var assetVersion: AssetVersion?
		var currentActID: Season.ID?
		var contractCount: Int
	}
	
	var body: some View {
		VStack(spacing: 14) {
			tabPicker
			
			Group {
				switch selectedTab {
				case .missions:
					VStack(spacing: 0) {
						dailyProgress
						currentMissionsInfo
						upcomingMissionsInfo
					}
				case .battlePass:
					battlePassView
						.padding(.horizontal, 12)
						.padding(.bottom, 14)
				case .newAgent:
					newAgentView
						.padding(.horizontal, 12)
						.padding(.bottom, 14)
				case .account:
					AccountXPView(accountXP: accountXP)
						.padding(.horizontal, 12)
						.padding(.bottom, 14)
				case .agents:
					agentsMasteryView
						.padding(.horizontal, 12)
						.padding(.bottom, 14)
				}
			}
		}
		.padding(.top, 8)
		.task(id: MasteryCacheKey(
			isAgentsTab: selectedTab == .agents,
			userID: userID,
			mastery: agentMastery,
			assetVersion: assets?.version,
			currentActID: seasons?.currentAct()?.id,
			contractCount: contracts.details.contracts.count
		)) {
			guard selectedTab == .agents else { return }
			let computed = buildMasterySummaries()
			cachedMasterySummaries = computed.summaries
			cachedMasteryActEndDate = computed.actEndDate
		}
	}
	
	private var tabPicker: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(SectionTab.allCases) { tab in
					let isSelected = selectedTab == tab
					Button {
						withAnimation(.easeInOut(duration: 0.18)) {
							selectedTab = tab
						}
					} label: {
						Text(tab.rawValue)
							.font(.subheadline.weight(isSelected ? .semibold : .medium))
							.padding(.horizontal, 14)
							.padding(.vertical, 7)
							.background(
								isSelected ? Color.tertiaryGroupedBackground : Color.clear,
								in: Capsule()
							)
							.overlay {
								if isSelected {
									Capsule()
										.stroke(Color.separator, lineWidth: 1)
								}
							}
							.foregroundStyle(isSelected ? Color.accentColor : .secondary)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 14)
		}
	}
	
	// MARK: - Missions
	
	var dailyProgress: some View {
		Box(
			title: Text("Daily Checkpoints", comment: "Missions Box: header"),
			countdownTarget: contracts.dailyRefresh
		) {
			DailyTicketView(milestones: contracts.daily.milestones)
				.frame(maxWidth: 420)
		}
	}
	
	@ViewBuilder
	var currentMissionsInfo: some View {
		if !contracts.weeklies.isEmpty {
			Divider()
			
			Box(
				title: Text("Weekly Missions", comment: "Missions Box: header"),
				countdownTarget: contracts.weeklyRefresh
			) {
				ForEach(contracts.weeklies) { mission in
					if let info = mission.info {
						MissionView(missionInfo: info, mission: mission.mission)
					} else {
						Text("Unknown mission!")
							.foregroundStyle(.secondary)
					}
				}
			}
		}
	}
	
	@ViewBuilder
	var upcomingMissionsInfo: some View {
		if let upcomingMissions = contracts.upcomingMissions {
			let now = Date.now
			let futureStart = upcomingMissions.firstIndex { $0.activationDate! > now }
			?? upcomingMissions.endIndex
			
			UpcomingMissionsList(missions: upcomingMissions.prefix(upTo: futureStart)) {
				Text("\($0) Queued-Up Weeklies", comment: "Missions Box: always at least 3")
			}
			UpcomingMissionsList(missions: upcomingMissions.suffix(from: futureStart)) {
				Text("\($0) Future Weeklies", comment: "Missions Box: always at least 3")
			}
		}
	}
	
	// MARK: - Battle Pass
	
	@ViewBuilder
	private var battlePassView: some View {
		if let (info, progress) = currentBattlePass() {
			let act = info.content.seasonID.flatMap { seasons?.act($0) } ?? seasons?.currentAct()
			let stats = PassPlanner.levelProgress(contract: info, details: progress, includeEpilogue: includeEpilogue)
			let levels = (includeEpilogue ? info.content.chapters : info.content.chapters.filter { !$0.isEpilogue })
				.flatMap(\.levels)
			let nextLevel = stats.currentLevel < levels.count ? levels[stats.currentLevel] : nil
			
			VStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 12) {
					HStack(alignment: .top) {
						VStack(alignment: .leading, spacing: 2) {
							Text(info.displayName)
								.font(.headline)
						}
						Spacer()
						if let endDate = act?.timeSpan.end, endDate > Date() {
							HStack(spacing: 4) {
								CountdownText(target: endDate)
								Image(systemName: "clock")
							}
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
						}
					}
					
					if let nextLevel {
						HStack(spacing: 12) {
							nextRewardIcon(for: nextLevel.reward)
								.frame(width: 44, height: 44)
							VStack(alignment: .leading, spacing: 2) {
								Text(nextRewardTitle(for: nextLevel.reward))
									.font(.subheadline.weight(.semibold))
								Text("Level \(stats.currentLevel) / \(stats.totalLevels)")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Spacer()
						}
					} else {
						Text("Level \(stats.currentLevel) / \(stats.totalLevels) Completed")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.green)
					}
					
					let ratio = Double(stats.levelXP) / Double(max(1, stats.levelTotalXP))
					HorizontalFillCapsuleShape(fraction: ratio, minWidth: 6)
						.fill(Color.accentColor)
						.background(Color.secondary.opacity(0.2), in: Capsule())
						.frame(height: 6)
					
					HStack {
						let pct = Int((ratio * Double(100)).rounded())
						Text("\(pct)% — \(stats.levelXP.formatted()) / \(stats.levelTotalXP.formatted()) XP")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
						Spacer()
						let rem = max(0, stats.levelTotalXP - stats.levelXP)
						Text("\(rem.formatted()) XP")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					}
				}
				.padding(14)
				.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
				
				PassPlannerCard(
					planner: PassPlanner(
						totalXPRequired: stats.totalXP,
						currentXP: stats.earnedXP,
						endDate: act?.timeSpan.end
					),
					includeEpilogue: $includeEpilogue
				)
				
				NavigationLink {
					ContractPassDetailsView(contractInfo: info, progress: progress)
				} label: {
					Text("View \(info.displayName)")
						.font(.subheadline.weight(.semibold))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 10)
						.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
				}
				.buttonStyle(.plain)
			}
		} else {
			Text("No active Battle Pass contract found in current assets.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(14)
				.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
		}
	}
	
	private func currentBattlePass() -> (ContractInfo, Contract?)? {
		guard let assets else { return nil }
		let progressByID = Dictionary(uniqueKeysWithValues: contracts.details.contracts.map { ($0.id, $0) })
		let currentActID = seasons?.currentAct()?.id
		
		let seasonContracts = assets.contracts.values.filter { $0.content.relationType == .season }
		if let currentActID,
		   let active = seasonContracts.first(where: { $0.content.seasonID == currentActID }) {
			return (active, progressByID[active.id])
		}
		if let specialID = contracts.details.activeSpecialContract,
		   let special = assets.contracts[specialID],
		   special.content.relationType == .season {
			return (special, progressByID[specialID])
		}
		if let matched = seasonContracts.first(where: { progressByID[$0.id] != nil }) ?? seasonContracts.last {
			return (matched, progressByID[matched.id])
		}
		return nil
	}
	
	// MARK: - New Agent Recruitment
	
	@ViewBuilder
	private var newAgentView: some View {
		if let recruitment = resolvedRecruitmentInfo() {
			let pct = recruitment.threshold > 0
				? Double(min(recruitment.earned, recruitment.threshold)) / Double(recruitment.threshold)
				: Double(0)
			
			VStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 12) {
					HStack {
						Text("Agent Recruitment")
							.font(.headline)
						Spacer()
						if recruitment.endDate > Date() {
							HStack(spacing: 4) {
								CountdownText(target: recruitment.endDate)
								Image(systemName: "clock")
							}
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
						}
					}
					
					HStack(spacing: 12) {
						AgentImage.icon(recruitment.agentID)
							.frame(width: 48, height: 48)
							.cornerRadius(10)
						AgentLabel(agent: recruitment.agentID)
							.font(.headline)
						Spacer()
					}
					
					HorizontalFillCapsuleShape(fraction: pct, minWidth: 6)
						.fill(Color.accentColor)
						.background(Color.secondary.opacity(0.2), in: Capsule())
						.frame(height: 6)
					
					HStack {
						Text("\(Int((pct * Double(100)).rounded()))% — \(recruitment.earned.formatted()) / \(recruitment.threshold.formatted()) XP")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
						Spacer()
						let rem = max(0, recruitment.threshold - recruitment.earned)
						Text("\(rem.formatted()) XP")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					}
				}
				.padding(14)
				.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
				
				PassPlannerCard(
					planner: PassPlanner(
						totalXPRequired: recruitment.threshold,
						currentXP: recruitment.earned,
						endDate: recruitment.endDate
					)
				)
			}
		} else {
			VStack(alignment: .leading, spacing: 8) {
				Text("No Active Agent Recruitment")
					.font(.headline)
				Text("There is no limited-time agent recruitment event running right now. Unlock past agents in-game or browse archived contracts.")
					.font(.caption)
					.foregroundStyle(.secondary)
				NavigationLink {
					ContractArchiveView()
				} label: {
					Text("Browse Contracts Archive")
						.font(.subheadline.weight(.medium))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 8)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
				}
				.buttonStyle(.plain)
			}
			.padding(14)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
		}
	}
	
	private func resolvedRecruitmentInfo() -> (agentID: Agent.ID, earned: Int, threshold: Int, endDate: Date)? {
		if let activeRecruitment, activeRecruitment.isActive {
			let earned = contracts.details.recruitmentProgress?
				.first(where: { $0.agentID == activeRecruitment.agentID })?
				.progressionEarned ?? 0
			return (
				activeRecruitment.agentID,
				earned,
				max(1, activeRecruitment.milestoneThreshold),
				activeRecruitment.endDate
			)
		}
		if let progress = contracts.details.recruitmentProgress?.first,
		   let agent = assets?.agents[progress.agentID],
		   let data = agent.recruitmentData {
			return (
				agent.id,
				progress.progressionEarned,
				max(1, data.milestoneThreshold),
				data.endDate
			)
		}
		if let activeAssetAgent = assets?.agents.values.first(where: { ($0.recruitmentData?.endDate ?? .distantPast) > Date() }),
		   let data = activeAssetAgent.recruitmentData {
			return (
				activeAssetAgent.id,
				0,
				max(1, data.milestoneThreshold),
				data.endDate
			)
		}
		return nil
	}
	
	// MARK: - Agents Mastery Tab
	
	@ViewBuilder
	private var agentsMasteryView: some View {
		AgentMasterySectionView(
			summaries: cachedMasterySummaries,
			actEndDate: cachedMasteryActEndDate
		)
	}
	
	private func buildMasterySummaries() -> (summaries: [AgentMasterySummary], actEndDate: Date?) {
		let uid = userID
		let cachedMatches: [MatchDetails] = {
			guard let uid,
				  let list = LocalDataProvider.shared.matchListManager.loadedObject(for: uid) else { return [] }
			return list.matches.prefix(40).compactMap {
				LocalDataProvider.shared.matchDetailsManager.loadedObject(for: $0.id)
			}
		}()
		let currentAct = seasons?.currentAct()
		let prevAct = assets?.seasons.actBefore(currentAct)
		let summaries = AgentMasteryCalculator.buildFromRiot(
			agentMastery,
			userID: uid,
			matches: cachedMatches,
			assets: assets,
			contractsDetails: contracts.details,
			currentAct: currentAct,
			previousAct: prevAct
		)
		return (summaries, currentAct?.timeSpan.end)
	}
	
	// MARK: - Helpers
	
	@ViewBuilder
	private func nextRewardIcon(for reward: ContractInfo.Reward) -> some View {
		switch reward.type {
		case .currency:
			if let id = Currency.ID(reward.id) {
				(assets?.currencies[id]?.displayIcon).view(bucket: .icon)
			}
		case .skin:
			if let id = Weapon.Skin.Level.ID(reward.id) {
				assets?.resolveSkin(id)?.displayIcon?.view(bucket: .icon)
			}
		case .spray:
			if let id = Spray.ID(reward.id) {
				(assets?.sprays[id]?.bestIcon).view(bucket: .icon)
			}
		case .flex:
			if let id = Totem.ID(reward.id) {
				(assets?.flex[id]?.displayIcon).view(bucket: .icon)
			}
		case .playerCard:
			if let id = PlayerCard.ID(reward.id) {
				(assets?.playerCards[id]?.smallArt).view(bucket: .icon)
					.cornerRadius(6)
			}
		case .gunBuddy:
			if let id = Weapon.Buddy.Level.ID(reward.id) {
				(assets?.resolveBuddy(id)?.displayIcon).view(bucket: .icon)
			}
		default:
			Image(systemName: "gift.fill")
				.foregroundStyle(.secondary)
		}
	}
	
	private func nextRewardTitle(for reward: ContractInfo.Reward) -> String {
		switch reward.type {
		case .currency:
			let name = Currency.ID(reward.id).flatMap { assets?.currencies[$0]?.displayNamePlural } ?? "Radianite"
			return reward.amount > 1 ? "\(reward.amount) \(name)" : name
		case .skin:
			return Weapon.Skin.Level.ID(reward.id).flatMap { assets?.resolveSkin($0)?.skin.displayName } ?? "Weapon Skin"
		case .spray:
			return Spray.ID(reward.id).flatMap { assets?.sprays[$0]?.displayName } ?? "Spray"
		case .flex:
			return Totem.ID(reward.id).flatMap { assets?.flex[$0]?.displayName } ?? "Flex"
		case .playerCard:
			return PlayerCard.ID(reward.id).flatMap { assets?.playerCards[$0]?.displayName } ?? "Player Card"
		case .gunBuddy:
			return Weapon.Buddy.Level.ID(reward.id).flatMap { assets?.resolveBuddy($0)?.displayName } ?? "Gun Buddy"
		case .title:
			return PlayerTitle.ID(reward.id).flatMap { assets?.playerTitles[$0]?.displayName } ?? "Player Title"
		default:
			return reward.type.rawValue
		}
	}
	
	private struct Box<Content: View>: View {
		let title: Text
		let countdownTarget: Date?
		@ViewBuilder var content: Content
		
		var body: some View {
			VStack(spacing: 16) {
				HStack(alignment: .lastTextBaseline) {
					title
						.font(.headline)
						.multilineTextAlignment(.leading)
					
					Spacer()
					
					Group {
						if let countdownTarget {
							CountdownText(target: countdownTarget)
							Image(systemName: "clock")
						}
					}
					.font(.caption.weight(.medium))
					.foregroundStyle(.secondary)
				}
				
				GroupBox {
					content
				}
			}
			.padding(16)
		}
	}
}

#if DEBUG
struct ContractDetailsView_Previews: PreviewProvider, PreviewProviderWithAssets {
	static func previews(assets: AssetCollection) -> some View {
		RefreshableBox(title: "Contracts", isExpanded: .constant(true)) {
			ContractDetailsView(contracts: PreviewData.resolvedContracts, userID: PreviewData.userID)
		} refresh: { _ in }
			.forPreviews()
			.environmentObject(AccountManager.mocked)
	}
}
#endif
