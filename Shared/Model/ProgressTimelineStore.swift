import Foundation
import ValorantAPI

enum ProgressTimeRange: String, CaseIterable, Identifiable, Hashable {
	case days30 = "30 Days"
	case days90 = "90 Days"
	case year = "Year"
	case allTime = "All Time"
	
	var id: String { rawValue }
	
	var days: Int? {
		switch self {
		case .days30: return 30
		case .days90: return 90
		case .year: return 365
		case .allTime: return nil
		}
	}
	
	func cutoffDate(relativeTo now: Date = .now) -> Date? {
		guard let days else { return nil }
		return Calendar.current.date(byAdding: .day, value: -days, to: now)
	}
}

struct ProgressTimelinePoint: Identifiable, Codable, Equatable {
	var id: String
	var accountID: User.ID
	var dayKey: String
	var recordedAt: Date
	var accountLevel: Int?
	var accountXP: Int?
	var leaderboardRank: Int?
	var competitiveTier: Int?
	var rankedRating: Int?
	var vp: Int?
	var rp: Int?
	var kc: Int?
}

@MainActor
final class ProgressTimelineStore: ObservableObject {
	@Published private(set) var points: [ProgressTimelinePoint] = []
	
	private let filename = "ProgressTimeline.v1.json"
	private static let maxStoredPoints = 10_000
	
	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.timeZone = .current
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	init() {
		let loaded = LocalJSONStore.load([ProgressTimelinePoint].self, from: filename) ?? []
		self.points = loaded.sorted {
			if $0.recordedAt != $1.recordedAt {
				return $0.recordedAt < $1.recordedAt
			}
			return $0.id < $1.id
		}
	}
	
	static func dayKey(for date: Date) -> String {
		dayFormatter.string(from: date)
	}
	
	static func pointID(accountID: User.ID, dayKey: String) -> String {
		"\(accountID.description.lowercased())_\(dayKey)"
	}
	
	// MARK: - Passive Recording
	
	func record(accountXP: AccountXP, for accountID: User.ID) {
		var working = points
		var changed = false
		
		let historyEntries = accountXP.history.sorted { $0.matchStart < $1.matchStart }
		for entry in historyEntries {
			changed = applyMutation(
				in: &working,
				accountID: accountID,
				date: entry.matchStart
			) { point in
				if point.accountLevel == nil || entry.matchStart >= point.recordedAt {
					point.accountLevel = entry.endProgress.level
					point.accountXP = max(0, min(5_000, entry.endProgress.xp))
				}
			} || changed
		}
		
		let now = Date()
		changed = applyMutation(
			in: &working,
			accountID: accountID,
			date: now
		) { point in
			point.accountLevel = accountXP.progress.level
			point.accountXP = max(0, min(5_000, accountXP.progress.xp))
		} || changed
		
		if changed {
			commit(working)
		}
	}
	
	func record(wallet: StoreWallet, for accountID: User.ID) {
		upsert(accountID: accountID, date: Date()) { point in
			point.vp = wallet[.valorantPoints]
			point.rp = wallet[.radianitePoints]
			point.kc = wallet[.kingdomCredits]
		}
	}
	
	func record(summary: CareerSummary, seasons: SeasonCollection.Accessor?, for accountID: User.ID) {
		guard let currentAct = seasons?.currentAct(),
			  let info = summary.competitiveInfo?.inSeason(currentAct.id) else {
			return
		}
		
		upsert(accountID: accountID, date: Date()) { point in
			if info.competitiveTier > 0 {
				point.competitiveTier = info.competitiveTier
				point.rankedRating = info.adjustedRankedRating
			}
			if info.leaderboardRank > 0 {
				point.leaderboardRank = info.leaderboardRank
			} else if point.recordedAt <= Date(), point.leaderboardRank != nil, info.competitiveTier > 0 {
				// Leave prior days untouched; today's rank is no longer on leaderboard.
				point.leaderboardRank = nil
			}
		}
	}
	
	func record(identity: Player.Identity, for accountID: User.ID) {
		guard identity.accountLevel > 0 else { return }
		upsert(accountID: accountID, date: Date()) { point in
			if let existingLevel = point.accountLevel {
				if identity.accountLevel > existingLevel {
					point.accountLevel = identity.accountLevel
					point.accountXP = nil
				}
			} else {
				point.accountLevel = identity.accountLevel
			}
		}
	}
	
	// MARK: - Queries
	
	func points(for accountID: User.ID, in range: ProgressTimeRange = .allTime) -> [ProgressTimelinePoint] {
		let cutoff = range.cutoffDate()
		return points.filter { point in
			guard point.accountID == accountID else { return false }
			if let cutoff, point.recordedAt < cutoff {
				return false
			}
			return true
		}
	}
	
	func firstRecordedDate(for accountID: User.ID) -> Date? {
		points.lazy
			.filter { $0.accountID == accountID }
			.map(\.recordedAt)
			.min()
	}
	
	// MARK: - Backup Support
	
	func exportPoints(for playerFilter: Set<User.ID>?) -> [ProgressTimelinePoint] {
		guard let playerFilter else { return points }
		return points.filter { playerFilter.contains($0.accountID) }
	}
	
	@discardableResult
	func importPoints(_ incoming: [ProgressTimelinePoint], replaceAll: Bool) async -> Int {
		var workingByID: [String: ProgressTimelinePoint] = [:]
		if !replaceAll {
			for existing in points {
				let normalizedID = Self.pointID(accountID: existing.accountID, dayKey: existing.dayKey)
				var copy = existing
				copy.id = normalizedID
				workingByID[normalizedID] = copy
			}
		}
		
		var changedCount = 0
		for rawPoint in incoming {
			let normalizedID = Self.pointID(accountID: rawPoint.accountID, dayKey: rawPoint.dayKey)
			var normalized = rawPoint
			normalized.id = normalizedID
			
			if let existing = workingByID[normalizedID] {
				let merged = Self.merge(existing: existing, incoming: normalized)
				if merged != existing {
					workingByID[normalizedID] = merged
					changedCount += 1
				}
			} else {
				workingByID[normalizedID] = normalized
				changedCount += 1
			}
		}
		
		let mergedSorted = Self.sortedAndTrimmed(Array(workingByID.values))
		points = mergedSorted
		await LocalJSONStore.saveAndWait(points, to: filename)
		return replaceAll ? mergedSorted.count : changedCount
	}
	
	// MARK: - Helpers
	
	private func upsert(accountID: User.ID, date: Date, mutate: (inout ProgressTimelinePoint) -> Void) {
		var working = points
		if applyMutation(in: &working, accountID: accountID, date: date, mutate: mutate) {
			commit(working)
		}
	}
	
	private func applyMutation(
		in working: inout [ProgressTimelinePoint],
		accountID: User.ID,
		date: Date,
		mutate: (inout ProgressTimelinePoint) -> Void
	) -> Bool {
		let key = Self.dayKey(for: date)
		let id = Self.pointID(accountID: accountID, dayKey: key)
		
		if let index = working.firstIndex(where: { $0.id == id || ($0.accountID == accountID && $0.dayKey == key) }) {
			let original = working[index]
			var updated = original
			updated.id = id
			mutate(&updated)
			if date > updated.recordedAt {
				updated.recordedAt = date
			}
			guard updated != original else { return false }
			working[index] = updated
			return true
		} else {
			var created = ProgressTimelinePoint(
				id: id,
				accountID: accountID,
				dayKey: key,
				recordedAt: date
			)
			mutate(&created)
			working.append(created)
			return true
		}
	}
	
	private func commit(_ working: [ProgressTimelinePoint]) {
		points = Self.sortedAndTrimmed(working)
		LocalJSONStore.save(points, to: filename)
	}
	
	private static func sortedAndTrimmed(_ list: [ProgressTimelinePoint]) -> [ProgressTimelinePoint] {
		var sorted = list.sorted {
			if $0.recordedAt != $1.recordedAt {
				return $0.recordedAt < $1.recordedAt
			}
			return $0.id < $1.id
		}
		if sorted.count > maxStoredPoints {
			sorted.removeFirst(sorted.count - maxStoredPoints)
		}
		return sorted
	}
	
	private static func merge(
		existing: ProgressTimelinePoint,
		incoming: ProgressTimelinePoint
	) -> ProgressTimelinePoint {
		let preferIncoming = incoming.recordedAt >= existing.recordedAt
		var result = existing
		result.recordedAt = max(existing.recordedAt, incoming.recordedAt)
		if preferIncoming {
			result.accountLevel = incoming.accountLevel ?? existing.accountLevel
			result.accountXP = incoming.accountXP ?? existing.accountXP
			result.leaderboardRank = incoming.leaderboardRank ?? existing.leaderboardRank
			result.competitiveTier = incoming.competitiveTier ?? existing.competitiveTier
			result.rankedRating = incoming.rankedRating ?? existing.rankedRating
			result.vp = incoming.vp ?? existing.vp
			result.rp = incoming.rp ?? existing.rp
			result.kc = incoming.kc ?? existing.kc
		} else {
			result.accountLevel = existing.accountLevel ?? incoming.accountLevel
			result.accountXP = existing.accountXP ?? incoming.accountXP
			result.leaderboardRank = existing.leaderboardRank ?? incoming.leaderboardRank
			result.competitiveTier = existing.competitiveTier ?? incoming.competitiveTier
			result.rankedRating = existing.rankedRating ?? incoming.rankedRating
			result.vp = existing.vp ?? incoming.vp
			result.rp = existing.rp ?? incoming.rp
			result.kc = existing.kc ?? incoming.kc
		}
		return result
	}
}
