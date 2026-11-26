import SwiftUI
import ValorantAPI

struct PartyServerSelectionView: View {
	@Binding var party: Party
	let userID: User.ID
	let isOwner: Bool
	
	@State private var selectedIDs: Set<String>
	@State private var isSaving = false
	
	@Environment(\.assets) private var assets
	@Environment(\.valorantLoad) private var load
	@Environment(\.dismiss) private var dismiss
	
	init(party: Binding<Party>, userID: User.ID, isOwner: Bool) {
		self._party = party
		self.userID = userID
		self.isOwner = isOwner
		self._selectedIDs = State(initialValue: Set(party.wrappedValue.matchmakingData.preferredGamePods))
	}
	
	private var selfMember: Party.Member? {
		party.members.firstElement(withID: userID) ?? party.members.first
	}
	
	private var sortedPings: [Party.Member.ServerPing] {
		(selfMember?.pings ?? []).sorted { lhs, rhs in
			if lhs.ping != rhs.ping { return lhs.ping < rhs.ping }
			return serverName(for: lhs.serverID) < serverName(for: rhs.serverID)
		}
	}
	
	private var canEdit: Bool {
		isOwner && party.state != .inMatchmaking && !isSaving
	}
	
	var body: some View {
		let pings = sortedPings
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				if pings.isEmpty {
					VStack(spacing: 8) {
						Image(systemName: "server.rack")
							.font(.title2)
							.foregroundStyle(.secondary)
						Text("Server ping data unavailable")
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.secondary)
					}
					.frame(maxWidth: .infinity)
					.padding(24)
					.background(
						Color.secondaryGroupedBackground,
						in: RoundedRectangle(cornerRadius: 18, style: .continuous)
					)
				} else {
					VStack(spacing: 0) {
						ForEach(Array(pings.enumerated()), id: \.element.id) { index, ping in
							let isSelected = selectedIDs.contains(ping.serverID)
							Button {
								toggleServer(ping.serverID)
							} label: {
								HStack(spacing: 12) {
									Image(systemName: "checkmark")
										.font(.body.weight(.semibold))
										.foregroundStyle(Color.accentColor)
										.opacity(isSelected ? 1 : 0)
										.frame(width: 22, alignment: .leading)
									
									Text(serverName(for: ping.serverID))
										.font(.body)
										.foregroundStyle(isSelected ? .primary : .secondary)
									
									Spacer()
									
									Text("\(ping.ping)")
										.font(.body.weight(.medium))
										.monospacedDigit()
										.foregroundStyle(pingColor(for: ping.ping))
								}
								.padding(.horizontal, 16)
								.padding(.vertical, 14)
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
							.disabled(!canEdit)
							
							if index < pings.count - 1 {
								Divider()
									.padding(.leading, 50)
							}
						}
					}
					.background(
						Color.secondaryGroupedBackground,
						in: RoundedRectangle(cornerRadius: 18, style: .continuous)
					)
				}
				
				Text("The optimal setting balances low ping with reasonable queue times. You can select preferred servers, but queue times may increase. Preferences are not guaranteed.")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.padding(.horizontal, 6)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Server Selection")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					saveServers()
				} label: {
					if isSaving {
						ProgressView()
							.tint(.white)
					} else {
						Image(systemName: "checkmark")
							.fontWeight(.semibold)
					}
				}
				.buttonStyle(.borderedProminent)
				.tint(Color.accentColor)
				.disabled(!canEdit)
			}
		}
	}
	
	private func serverName(for gamePodID: String) -> String {
		assets?.serverDisplayName(for: gamePodID)
			?? MatchAnalytics.parseServerName(from: gamePodID)
			?? gamePodID
	}
	
	private func pingColor(for ping: Int) -> Color {
		if ping < 50 { return .green }
		if ping < 100 { return .yellow }
		return .red
	}
	
	private func toggleServer(_ serverID: String) {
		if selectedIDs.contains(serverID) {
			selectedIDs.remove(serverID)
		} else {
			selectedIDs.insert(serverID)
		}
	}
	
	private func saveServers() {
		let orderedIDs = sortedPings.map(\.serverID).filter { selectedIDs.contains($0) }
		Task {
			isSaving = true
			defer { isSaving = false }
			var didSucceed = false
			await load {
				party = try await $0.setPreferredServers(in: party.id, to: orderedIDs)
				didSucceed = true
			}
			if didSucceed {
				dismiss()
			}
		}
	}
}
