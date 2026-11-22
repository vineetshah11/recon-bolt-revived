import Foundation
import Combine
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
	
	init() {
		recordsByPlayer = LocalJSONStore.load([User.ID: [NameHistoryRecord]].self, from: filename) ?? [:]
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
			for player in valid {
				shared.record(id: player.id, gameName: player.gameName, tagLine: player.tagLine, persistImmediately: false)
			}
			shared.persist()
		}
	}
	
	func record(id: User.ID, gameName: String, tagLine: String, persistImmediately: Bool = true) {
		let cleanName = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
		let cleanTag = tagLine.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleanName.isEmpty else { return }
		
		var history = recordsByPlayer[id] ?? []
		let now = Date()
		
		if let latest = history.last, latest.gameName == cleanName, latest.tagLine == cleanTag {
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
		recordsByPlayer[id] = history
		if persistImmediately {
			persist()
		}
	}
	
	func allTimelines() -> [PlayerNameTimeline] {
		recordsByPlayer.map { id, records in
			PlayerNameTimeline(id: id, records: records.sorted { $0.lastSeen > $1.lastSeen })
		}
		.sorted { ($0.latest?.lastSeen ?? .distantPast) > ($1.latest?.lastSeen ?? .distantPast) }
	}
	
	func clearHistory(for id: User.ID) {
		recordsByPlayer.removeValue(forKey: id)
		persist()
	}
	
	private func persist() {
		LocalJSONStore.save(recordsByPlayer, to: filename)
	}
}
