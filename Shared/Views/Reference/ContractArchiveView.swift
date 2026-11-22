import SwiftUI
import ValorantAPI

struct ContractArchiveView: View {
	enum Category: String, CaseIterable, Identifiable {
		case battlePasses = "Battle Passes"
		case agents = "Agents"
		case events = "Events"
		case all = "All"
		
		var id: String { rawValue }
	}
	
	@EnvironmentObject private var accountManager: AccountManager
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	
	@State private var category: Category = .agents
	@State private var search = ""
	@State private var agentMastery: AgentMastery?
	@State private var contractDetails: ContractDetails?
	@State private var masteriesExpanded = true
	@State private var legacyContractsExpanded = false
	
	var body: some View {
		List {
			Section {
				Picker("Category", selection: $category) {
					ForEach(Category.allCases) { item in
						Text(item.rawValue).tag(item)
					}
				}
				.pickerStyle(.segmented)
				.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
			}
			
			if let assets {
				if category == .agents {
					agentsDualDropdownSections(assets: assets)
				} else {
					let contracts = assets.contracts.values
						.filter { contract in
							switch category {
							case .battlePasses: return contract.content.relationType == .season
							case .agents: return contract.content.relationType == .agent
							case .events: return contract.content.relationType == .event
							case .all: return true
							}
						}
						.filter {
							search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)
						}
						.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
					
					Section("Contracts (\(contracts.count))") {
						ForEach(contracts) { contract in
							contractNavigationRow(contract)
						}
					}
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search agents or contracts"))
		.navigationTitle("Contracts")
		.task(id: accountManager.activeAccount?.id) {
			await loadLiveAgentData()
		}
		.refreshable {
			await loadLiveAgentData()
		}
	}
	
	@ViewBuilder
	private func agentsDualDropdownSections(assets: AssetCollection) -> some View {
		let uid = accountManager.activeAccount?.id
		let cachedMatches: [MatchDetails] = {
			guard let uid,
				  let list = LocalDataProvider.shared.matchListManager.loadedObject(for: uid) else { return [] }
			return list.matches.prefix(40).compactMap {
				LocalDataProvider.shared.matchDetailsManager.loadedObject(for: $0.id)
			}
		}()
		let currentAct = seasons?.currentAct()
		let prevAct = assets.seasons.actBefore(currentAct)
		let summaries = AgentMasteryCalculator.buildFromRiot(
			agentMastery,
			userID: uid,
			matches: cachedMatches,
			assets: assets,
			contractsDetails: contractDetails,
			currentAct: currentAct,
			previousAct: prevAct
		)
		.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
		
		let legacyContracts = assets.contracts.values
			.filter { $0.content.relationType == .agent }
			.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		
		Section {
			DisclosureGroup(isExpanded: $masteriesExpanded) {
				ForEach(summaries) { item in
					NavigationLink {
						AgentMasteryDetailView(summary: item, actEndDate: currentAct?.timeSpan.end)
					} label: {
						HStack(spacing: 12) {
							ZStack(alignment: .bottomTrailing) {
								AgentImage.icon(item.agentID)
									.frame(width: 44, height: 44)
									.cornerRadius(8)
								let badge = max(item.currentActLevel, item.lastActLevel)
								if badge > 0 {
									Text(String(format: "%02d", badge))
										.font(.system(size: 10, weight: .bold).monospacedDigit())
										.padding(.horizontal, 4)
										.padding(.vertical, 1)
										.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
								}
							}
							
							VStack(alignment: .leading, spacing: 4) {
								HStack {
									Text(item.displayName)
										.font(.body.weight(.semibold))
									Spacer()
									LaurelBadge(level: item.lifetimeLevel)
								}
								
								MasterySegmentedBar(
									actLevel: item.currentActLevel,
									inLevelProgress: item.levelProgress,
									compact: true
								)
								
								Text("Act Level \(item.currentActLevel) • \(item.xpInCurrentLevel.formatted()) / \(item.nextLevelMPNeeded.formatted()) MP")
									.font(.caption2.monospacedDigit())
									.foregroundStyle(.secondary)
							}
						}
						.padding(.vertical, 4)
					}
				}
			} label: {
				HStack {
					Image(systemName: "star.circle.fill")
						.foregroundStyle(Color.valorantRed)
					Text("Agent Masteries")
						.font(.headline)
					Spacer()
					Text("\(summaries.count)")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
		}
		
		Section {
			DisclosureGroup(isExpanded: $legacyContractsExpanded) {
				ForEach(legacyContracts) { contract in
					contractNavigationRow(contract)
				}
			} label: {
				HStack {
					Image(systemName: "archivebox.fill")
						.foregroundStyle(.secondary)
					Text("Legacy Agent Contracts")
						.font(.headline)
					Spacer()
					Text("\(legacyContracts.count)")
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
		}
	}
	
	private func contractNavigationRow(_ contract: ContractInfo) -> some View {
		let progress = contractDetails?.contracts.first { $0.id == contract.id }
		return NavigationLink {
			ContractPassDetailsView(contractInfo: contract, progress: progress)
		} label: {
			HStack(spacing: 12) {
				if let agentID = contract.content.agentID {
					AgentImage.icon(agentID)
						.frame(width: 36, height: 36)
						.cornerRadius(8)
				} else if let icon = contract.displayIcon {
					icon.view()
						.frame(width: 36, height: 36)
				} else {
					Image(systemName: "archivebox")
						.frame(width: 36, height: 36)
						.foregroundStyle(Color.valorantRed)
				}
				
				VStack(alignment: .leading, spacing: 2) {
					Text(contract.displayName)
						.font(.body.weight(.medium))
					let levelCount = contract.content.chapters.reduce(0) { $0 + $1.levels.count }
					if let progress {
						Text("Tier \(progress.levelReached) / \(levelCount)")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else {
						Text("\(levelCount) tiers")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(.vertical, 2)
		}
	}
	
	private func loadLiveAgentData() async {
		guard let client = accountManager.activeAccount?.client else { return }
		async let masteryTask = try? client.getAgentMastery()
		async let detailsTask = try? client.getContractDetails()
		let (m, d) = await (masteryTask, detailsTask)
		agentMastery = m
		contractDetails = d
	}
}
