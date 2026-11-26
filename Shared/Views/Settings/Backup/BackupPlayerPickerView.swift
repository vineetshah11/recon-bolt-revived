import SwiftUI
import ValorantAPI

struct BackupPlayerPickerView: View {
	let players: [BackupSelectablePlayer]
	@Binding var selectedPlayerIDs: Set<User.ID>
	
	@State private var searchText = ""
	
	private var filteredPlayers: [BackupSelectablePlayer] {
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !query.isEmpty else { return players }
		return players.filter { player in
			player.displayName.lowercased().contains(query)
			|| player.gameName.lowercased().contains(query)
			|| player.tagLine.lowercased().contains(query)
			|| player.id.description.lowercased().contains(query)
		}
	}
	
	private var groupedRoles: [(role: BackupPlayerSummary.Role, list: [BackupSelectablePlayer])] {
		let allRoles: [BackupPlayerSummary.Role] = [.account, .bookmark, .cached]
		return allRoles.compactMap { role in
			let matches = filteredPlayers.filter { $0.role == role }
			return matches.isEmpty ? nil : (role, matches)
		}
	}
	
	private var ownAndBookmarkedIDs: Set<User.ID> {
		Set(players.filter { $0.role == .account || $0.role == .bookmark }.map(\.id))
	}
	
	var body: some View {
		List {
			Section {
				HStack(spacing: 10) {
					quickButton(title: "All (\(players.count))") {
						selectedPlayerIDs = Set(players.map(\.id))
					}
					if !ownAndBookmarkedIDs.isEmpty && ownAndBookmarkedIDs.count < players.count {
						quickButton(title: "Mine & Bookmarks") {
							selectedPlayerIDs = ownAndBookmarkedIDs
						}
					}
					quickButton(title: "None") {
						selectedPlayerIDs.removeAll()
					}
				}
				.listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
			}
			
			if groupedRoles.isEmpty {
				Section {
					Text("No players match your search.")
						.foregroundStyle(.secondary)
				}
			} else {
				ForEach(groupedRoles, id: \.role) { group in
					Section {
						ForEach(group.list) { player in
							playerRow(player)
						}
					} header: {
						HStack {
							Text(group.role.sectionTitle)
							Spacer()
							let groupIDs = Set(group.list.map(\.id))
							let allGroupSelected = !groupIDs.isEmpty && groupIDs.isSubset(of: selectedPlayerIDs)
							Button(allGroupSelected ? "Deselect" : "Select All") {
								if allGroupSelected {
									selectedPlayerIDs.subtract(groupIDs)
								} else {
									selectedPlayerIDs.formUnion(groupIDs)
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
