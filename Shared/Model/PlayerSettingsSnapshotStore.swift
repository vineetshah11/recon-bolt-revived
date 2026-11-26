import Foundation
import ValorantAPI

struct PlayerSettingsSnapshot: Identifiable, Codable, Equatable {
	var id = UUID()
	var title: String
	var accountID: User.ID?
	var createdAt = Date()
	var rawData: String
}

@MainActor
final class PlayerSettingsSnapshotStore: ObservableObject {
	@Published var snapshots: [PlayerSettingsSnapshot] = []
	
	private let filename = "PlayerSettingsSnapshots.v1.json"
	
	init() {
		snapshots = LocalJSONStore.load([PlayerSettingsSnapshot].self, from: filename) ?? []
	}
	
	func snapshots(for accountID: User.ID?) -> [PlayerSettingsSnapshot] {
		snapshots
			.filter { $0.accountID == nil || accountID == nil || $0.accountID == accountID }
			.sorted { $0.createdAt > $1.createdAt }
	}
	
	func addSnapshot(title: String, rawData: String, accountID: User.ID?) {
		let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
		let snapshot = PlayerSettingsSnapshot(
			title: trimmed.isEmpty ? "Settings \(Date().formatted(date: .abbreviated, time: .shortened))" : trimmed,
			accountID: accountID,
			rawData: rawData
		)
		snapshots.insert(snapshot, at: 0)
		persist()
	}
	
	func rename(id: UUID, to newTitle: String) {
		let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
		snapshots[index].title = trimmed
		persist()
	}
	
	func delete(id: UUID) {
		snapshots.removeAll { $0.id == id }
		persist()
	}
	
	func exportSnapshots(for playerIDs: Set<User.ID>?) -> [PlayerSettingsSnapshot] {
		guard let playerIDs else { return snapshots }
		return snapshots.filter { snapshot in
			guard let accountID = snapshot.accountID else { return !playerIDs.isEmpty }
			return playerIDs.contains(accountID)
		}
	}
	
	@discardableResult
	func importSnapshots(_ incoming: [PlayerSettingsSnapshot], replaceAll: Bool) async -> Int {
		var working = replaceAll ? [] : snapshots
		var changedCount = 0
		
		for snapshot in incoming {
			if let idx = working.firstIndex(where: { $0.id == snapshot.id }) {
				if snapshot.createdAt > working[idx].createdAt {
					working[idx] = snapshot
					changedCount += 1
				}
			} else {
				working.append(snapshot)
				changedCount += 1
			}
		}
		
		working.sort { $0.createdAt > $1.createdAt }
		snapshots = working
		await LocalJSONStore.saveAndWait(snapshots, to: filename)
		return replaceAll ? working.count : changedCount
	}
	
	private func persist() {
		LocalJSONStore.save(snapshots, to: filename)
	}
}
