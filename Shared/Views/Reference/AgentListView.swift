import SwiftUI

struct AgentListView: View {
	@Environment(\.assets) private var assets
	
	var body: some View {
		AssetsUnwrappingView { assets in
			List {
				let agents = assets.agents.values
					.filter(\.isPlayableCharacter)
					.sorted(on: \.displayName)
				let groups = Dictionary(grouping: agents) { $0.role }
					.compactMap { role, agents in role.map { ($0, agents) } }
					.sorted(on: \.0.displayName)
				ForEach(groups, id: \.0.id) { (role: AgentInfo.Role, agents: [AgentInfo]) in
					Section {
						ForEach(agents) { agent in
							NavigationLink(destination: AgentInfoView(agent: agent)) {
								row(for: agent)
							}
						}
					} header: {
						Label {
							Text(role.displayName)
						} icon: {
							role.displayIcon.view(renderingMode: .template)
								.frame(height: 20)
						}
						.foregroundStyle(.secondary)
					}
					.headerProminence(.increased)
				}
			}
		}
		.navigationTitle("Agents")
	}
	
	func row(for agent: AgentInfo) -> some View {
		HStack(spacing: 12) {
			SquareAgentIcon(agentID: agent.id)
				.frame(height: 48)
			
			Text("\(agent.displayName)")
				.fontWeight(.medium)
				.font(.title2)
			
			Spacer()
		}
		.padding(.vertical, 4)
	}
}

#if DEBUG
struct AgentListView_Previews: PreviewProvider {
	static var previews: some View {
		AgentListView()
			.withToolbar()
	}
}
#endif
