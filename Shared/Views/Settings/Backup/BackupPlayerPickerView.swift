import SwiftUI
import ValorantAPI

struct BackupPlayerPickerView: View {
	let players: [BackupSelectablePlayer]
	@Binding var selectedPlayerIDs: Set<User.ID>
	
	@State private var searchText = ""
	@State private var cachedGroupedRoles: [GroupedRoleSection] = []
	@State private var cachedOwnAndBookmarkedIDs: Set<User.ID> = []
	
	private struct GroupedRoleSection: Identifiable {
		let role: BackupPlayerSummary.Role
		let list: [BackupSelectablePlayer]
		let playerIDs: Set<User.ID>
		var id: BackupPlayerSummary.Role { role }
	}
	
	private struct FilterKey: Equatable {
		let players: [BackupSelectablePlayer]
		let searchText: String
	}
	
	private var allPlayerIDs: Set<User.ID> {
		Set(players.map(\.id))
	}
	
	var body: some View {
		List {
			Section {
				HStack(spacing: 10) {
					quickButton(title: "All (\(players.count))") {
						selectedPlayerIDs = allPlayerIDs
					}
					if !cachedOwnAndBookmarkedIDs.isEmpty && cachedOwnAndBookmarkedIDs.count < players.count {
						quickButton(title: "Mine & Bookmarks") {
							selectedPlayerIDs = cachedOwnAndBookmarkedIDs
						}
					}
					quickButton(title: "None") {
						selectedPlayerIDs.removeAll()
					}
				}
				.listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
			}
			
			if cachedGroupedRoles.isEmpty {
				Section {
					Text("No players match your search.")
						.foregroundStyle(.secondary)
				}
			} else {
				ForEach(cachedGroupedRoles) { group in
					Section {
						ForEach(group.list) { player in
							playerRow(player)
						}
					} header: {
						HStack {
							Text(group.role.sectionTitle)
							Spacer()
							let allGroupSelected = !group.playerIDs.isEmpty && group.playerIDs.isSubset(of: selectedPlayerIDs)
							Button(allGroupSelected ? "Deselect" : "Select All") {
								if allGroupSelected {
									selectedPlayerIDs.subtract(group.playerIDs)
								} else {
									selectedPlayerIDs.formUnion(group.playerIDs)
								}
							}
							.font(.caption.weight(.medium))
							.textCase(nil)
						}
					}
				}
			}
		}
		.listStyle(.insetGrouped)
		.searchable(text: $searchText, prompt: "Search player name or UUID")
		.navigationTitle("Select Players")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: players) {
			cachedOwnAndBookmarkedIDs = Set(
				players.filter { $0.role == .account || $0.role == .bookmark }.map(\.id)
			)
		}
		.task(id: FilterKey(players: players, searchText: searchText)) {
			recomputeGroups()
		}
	}
	
	private func recomputeGroups() {
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		let filtered: [BackupSelectablePlayer]
		if query.isEmpty {
			filtered = players
		} else {
			filtered = players.filter { player in
				player.displayName.localizedCaseInsensitiveContains(query)
					|| player.gameName.localizedCaseInsensitiveContains(query)
					|| player.tagLine.localizedCaseInsensitiveContains(query)
					|| player.id.description.localizedCaseInsensitiveContains(query)
			}
		}
		
		var byRole: [BackupPlayerSummary.Role: [BackupSelectablePlayer]] = [:]
		for player in filtered {
			byRole[player.role, default: []].append(player)
		}
		let allRoles: [BackupPlayerSummary.Role] = [.account, .bookmark, .cached]
		cachedGroupedRoles = allRoles.compactMap { role in
			guard let list = byRole[role], !list.isEmpty else { return nil }
			return GroupedRoleSection(
				role: role,
				list: list,
				playerIDs: Set(list.map(\.id))
			)
		}
	}
	
	private func quickButton(title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.caption.weight(.medium))
				.foregroundStyle(.tint)
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.background(Color.accentColor.opacity(0.12), in: Capsule())
		}
		.buttonStyle(.plain)
	}
	
	private func playerRow(_ player: BackupSelectablePlayer) -> some View {
		let isSelected = selectedPlayerIDs.contains(player.id)
		return Button {
			if isSelected {
				selectedPlayerIDs.remove(player.id)
			} else {
				selectedPlayerIDs.insert(player.id)
			}
		} label: {
			HStack(spacing: 12) {
				Image(systemName: player.role.icon)
					.font(.system(size: 16))
					.foregroundStyle(.tint)
					.frame(width: 22)
				
				VStack(alignment: .leading, spacing: 2) {
					Text(player.displayName)
						.font(.body)
						.foregroundStyle(.primary)
						.lineLimit(1)
					
					HStack(spacing: 6) {
						Text("\(player.matchCount) match\(player.matchCount == 1 ? "" : "es")")
						if let bytes = player.estimatedBytes, bytes > 0 {
							Text("•")
							Text(bytes, format: .byteCount(style: .file))
						}
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					.font(.system(size: 20))
					.foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}
