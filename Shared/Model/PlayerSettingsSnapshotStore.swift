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
	private var hasLoadedFromDisk = false
	private var initialLoadTask: Task<Void, Never>?
	private var pendingRemovedIDs: Set<UUID> = []
	private var pendingSaveTask: Task<Void, Never>?
	
	init() {
		initialLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let loaded = await LocalJSONStore.loadAsync([PlayerSettingsSnapshot].self, from: self.filename) ?? []
			self.mergeDiskSnapshots(loaded)
		}
	}
	
	func waitUntilLoaded() async {
		if let initialLoadTask, !hasLoadedFromDisk {
			await initialLoadTask.value
		}
	}
	
	private func mergeDiskSnapshots(_ diskSnapshots: [PlayerSettingsSnapshot]) {
		hasLoadedFromDisk = true
		let sortedDisk = diskSnapshots.sorted { $0.createdAt > $1.createdAt }
		guard !sortedDisk.isEmpty else {
			pendingRemovedIDs.removeAll()
			return
		}
		if snapshots.isEmpty && pendingRemovedIDs.isEmpty {
			snapshots = sortedDisk
			return
		}
		var working = snapshots
		var seenIDs = Set(working.map(\.id))
		for item in sortedDisk {
			guard !pendingRemovedIDs.contains(item.id), seenIDs.insert(item.id).inserted else { continue }
			working.append(item)
		}
		working.sort { $0.createdAt > $1.createdAt }
		pendingRemovedIDs.removeAll()
		snapshots = working
	}
	
	func snapshots(for accountID: User.ID?) -> [PlayerSettingsSnapshot] {
		snapshots
			.filter { $0.accountID == nil || accountID == nil || $0.accountID == accountID }
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
		if !hasLoadedFromDisk {
			pendingRemovedIDs.insert(id)
		}
		let before = snapshots.count
		snapshots.removeAll { $0.id == id }
		guard snapshots.count != before else { return }
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
		await waitUntilLoaded()
		pendingSaveTask?.cancel()
		var workingByID: [UUID: PlayerSettingsSnapshot] = [:]
		if !replaceAll {
			workingByID = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		}
		var changedCount = 0
		
		for snapshot in incoming {
			if let existing = workingByID[snapshot.id] {
				if snapshot.createdAt > existing.createdAt {
					workingByID[snapshot.id] = snapshot
					changedCount += 1
				}
			} else {
				workingByID[snapshot.id] = snapshot
				changedCount += 1
			}
		}
		
		let working = workingByID.values.sorted { $0.createdAt > $1.createdAt }
		snapshots = working
		await LocalJSONStore.saveAndWait(snapshots, to: filename)
		return replaceAll ? working.count : changedCount
	}
	
	private func persist() {
		if hasLoadedFromDisk {
			LocalJSONStore.save(snapshots, to: filename)
		} else {
			pendingSaveTask?.cancel()
			pendingSaveTask = Task { @MainActor [weak self] in
				await self?.waitUntilLoaded()
				guard let self, !Task.isCancelled else { return }
				LocalJSONStore.save(self.snapshots, to: self.filename)
			}
		}
	}
}
