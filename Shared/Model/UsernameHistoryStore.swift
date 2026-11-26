import Foundation
import ValorantAPI

struct NameHistoryRecord: Identifiable, Codable, Equatable {
	var id = UUID()
	var gameName: String
	var tagLine: String
	var firstSeen: Date
	var lastSeen: Date
	
	var displayName: String {
		"\(gameName) #\(tagLine)"
	}
}

struct PlayerNameTimeline: Identifiable {
	var id: User.ID
	var records: [NameHistoryRecord]
	
	var latest: NameHistoryRecord? {
		records.max { $0.lastSeen < $1.lastSeen }
	}
}

@MainActor
final class UsernameHistoryStore: ObservableObject {
	static let shared = UsernameHistoryStore()
	
	@Published private(set) var recordsByPlayer: [User.ID: [NameHistoryRecord]] = [:]
	
	private let filename = "UsernameHistory.v1.json"
	private var hasLoadedFromDisk = false
	private var initialLoadTask: Task<Void, Never>?
	private var debouncedSaveTask: Task<Void, Never>?
	
	init() {
		initialLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let diskRecords = await LocalJSONStore.loadAsync([User.ID: [NameHistoryRecord]].self, from: self.filename) ?? [:]
			self.mergeDiskRecords(diskRecords)
		}
	}
	
	private func mergeDiskRecords(_ diskRecords: [User.ID: [NameHistoryRecord]]) {
		hasLoadedFromDisk = true
		guard !diskRecords.isEmpty else { return }
		
		if recordsByPlayer.isEmpty {
			recordsByPlayer = diskRecords
			return
		}
		
		var merged = diskRecords
		for (id, inMemoryList) in recordsByPlayer {
			var list = merged[id] ?? []
			for entry in inMemoryList {
				if let idx = list.lastIndex(where: { $0.gameName == entry.gameName && $0.tagLine == entry.tagLine }) {
					list[idx].firstSeen = min(list[idx].firstSeen, entry.firstSeen)
					list[idx].lastSeen = max(list[idx].lastSeen, entry.lastSeen)
				} else {
					list.append(entry)
				}
			}
			list.sort { $0.firstSeen < $1.firstSeen }
			merged[id] = list
		}
		recordsByPlayer = merged
	}
	
	nonisolated static func record(_ user: User) {
		Task { @MainActor in
			shared.record(id: user.id, gameName: user.gameName, tagLine: user.tagLine)
		}
	}
	
	nonisolated static func record(players: [Player]) {
		let valid = players.filter { !$0.gameName.isEmpty }
		guard !valid.isEmpty else { return }
		Task { @MainActor in
			shared.recordBatch(valid)
		}
	}
	
	private func recordBatch(_ players: [Player]) {
		let now = Date()
		var working = recordsByPlayer
		var didChange = false
		for player in players {
			if applyRecord(id: player.id, gameName: player.gameName, tagLine: player.tagLine, now: now, into: &working) {
				didChange = true
			}
		}
		if didChange {
			recordsByPlayer = working
			schedulePersist()
		}
	}
	
	func record(id: User.ID, gameName: String, tagLine: String, persistImmediately: Bool = true) {
		var working = recordsByPlayer
		guard applyRecord(id: id, gameName: gameName, tagLine: tagLine, now: Date(), into: &working) else {
			return
		}
		recordsByPlayer = working
		if persistImmediately {
			schedulePersist()
		}
	}
	
	private func applyRecord(
		id: User.ID,
		gameName: String,
		tagLine: String,
		now: Date,
		into map: inout [User.ID: [NameHistoryRecord]]
	) -> Bool {
		let cleanName = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
		let cleanTag = tagLine.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleanName.isEmpty else { return false }
		
		var history = map[id] ?? []
		if let latest = history.last, latest.gameName == cleanName, latest.tagLine == cleanTag {
			guard now.timeIntervalSince(latest.lastSeen) >= 3600 else {
				return false
			}
			history[history.count - 1].lastSeen = now
		} else {
			history.append(
				NameHistoryRecord(
					gameName: cleanName,
					tagLine: cleanTag,
					firstSeen: now,
					lastSeen: now
				)
			)
		}
		map[id] = history
		return true
	}
	
	func allTimelines() -> [PlayerNameTimeline] {
		recordsByPlayer.map { id, records in
			PlayerNameTimeline(id: id, records: records.sorted { $0.lastSeen > $1.lastSeen })
		}
		.sorted { ($0.latest?.lastSeen ?? .distantPast) > ($1.latest?.lastSeen ?? .distantPast) }
	}
	
	func clearHistory(for id: User.ID) {
		debouncedSaveTask?.cancel()
		recordsByPlayer.removeValue(forKey: id)
		Task { @MainActor [weak self] in
			guard let self else { return }
			if let loadTask = self.initialLoadTask, !self.hasLoadedFromDisk {
				await loadTask.value
			}
			self.recordsByPlayer.removeValue(forKey: id)
			LocalJSONStore.save(self.recordsByPlayer, to: self.filename)
		}
	}
	
	func exportRecords(for playerIDs: Set<User.ID>?) async -> [User.ID: [NameHistoryRecord]] {
		if let loadTask = initialLoadTask, !hasLoadedFromDisk {
			await loadTask.value
		}
		guard let playerIDs else { return recordsByPlayer }
		return recordsByPlayer.filter { playerIDs.contains($0.key) }
	}
	
	@discardableResult
	func importRecords(_ incoming: [User.ID: [NameHistoryRecord]], replaceAll: Bool) async -> Int {
		debouncedSaveTask?.cancel()
		if let loadTask = initialLoadTask, !hasLoadedFromDisk {
			await loadTask.value
		}
		
		var working = replaceAll ? [:] : recordsByPlayer
		var changedCount = 0
		
		for (userID, incomingList) in incoming {
			var list = working[userID] ?? []
			var userChanged = false
			for entry in incomingList {
				let cleanName = entry.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
				let cleanTag = entry.tagLine.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !cleanName.isEmpty else { continue }
				if let idx = list.firstIndex(where: { $0.gameName == cleanName && $0.tagLine == cleanTag }) {
					let mergedFirst = min(list[idx].firstSeen, entry.firstSeen)
					let mergedLast = max(list[idx].lastSeen, entry.lastSeen)
					if mergedFirst != list[idx].firstSeen || mergedLast != list[idx].lastSeen {
						list[idx].firstSeen = mergedFirst
						list[idx].lastSeen = mergedLast
						userChanged = true
					}
				} else {
					var sanitized = entry
					sanitized.gameName = cleanName
					sanitized.tagLine = cleanTag
					list.append(sanitized)
					userChanged = true
				}
			}
			list.sort { $0.firstSeen < $1.firstSeen }
			if replaceAll || userChanged {
				working[userID] = list
				changedCount += 1
			}
		}
		
		recordsByPlayer = working
		await LocalJSONStore.saveAndWait(recordsByPlayer, to: filename)
		return replaceAll ? working.count : changedCount
	}
	
	private func schedulePersist() {
		debouncedSaveTask?.cancel()
		debouncedSaveTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(2))
			guard !Task.isCancelled, let self else { return }
			if let loadTask = self.initialLoadTask, !self.hasLoadedFromDisk {
				await loadTask.value
			}
			guard !Task.isCancelled else { return }
			LocalJSONStore.save(self.recordsByPlayer, to: self.filename)
		}
	}
}
