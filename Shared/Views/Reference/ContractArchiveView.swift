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
	
	@Environment(\.assets) private var assets
	@State private var category: Category = .battlePasses
	@State private var search = ""
	
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
						NavigationLink {
							ContractPassDetailsView(contractInfo: contract, progress: nil)
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
									Text("\(levelCount) tiers")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
							.padding(.vertical, 2)
						}
					}
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search contracts"))
		.navigationTitle("Contracts")
	}
}
