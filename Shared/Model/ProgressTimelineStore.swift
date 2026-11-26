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
	private static let saveDebounceNanoseconds: UInt64 = 1_500_000_000
	
	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.timeZone = .autoupdatingCurrent
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	private var indexByID: [String: Int] = [:]
	private var hasLoadedFromDisk = false
	private var initialLoadTask: Task<Void, Never>?
	private var debouncedSaveTask: Task<Void, Never>?
	
	init() {
		initialLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let loaded = await LocalJSONStore.loadAsync([ProgressTimelinePoint].self, from: self.filename) ?? []
			self.mergeDiskPoints(loaded)
		}
	}
	
	func waitUntilLoaded() async {
		if let initialLoadTask, !hasLoadedFromDisk {
			await initialLoadTask.value
		}
	}
	
	private func mergeDiskPoints(_ diskPoints: [ProgressTimelinePoint]) {
		hasLoadedFromDisk = true
		guard !diskPoints.isEmpty else { return }
		if points.isEmpty {
			let sorted = Self.sortedAndTrimmed(diskPoints)
			applyCommittedPoints(sorted)
			return
		}
		var mergedByID: [String: ProgressTimelinePoint] = [:]
		mergedByID.reserveCapacity(diskPoints.count + points.count)
		for point in diskPoints {
			let normalizedID = Self.pointID(accountID: point.accountID, dayKey: point.dayKey)
			var copy = point
			copy.id = normalizedID
			mergedByID[normalizedID] = copy
		}
		for point in points {
			let normalizedID = Self.pointID(accountID: point.accountID, dayKey: point.dayKey)
			var copy = point
			copy.id = normalizedID
			if let existing = mergedByID[normalizedID] {
				mergedByID[normalizedID] = Self.merge(existing: existing, incoming: copy)
			} else {
				mergedByID[normalizedID] = copy
			}
		}
		let sorted = Self.sortedAndTrimmed(Array(mergedByID.values))
		applyCommittedPoints(sorted)
	}
	
	private func applyCommittedPoints(_ newPoints: [ProgressTimelinePoint]) {
		points = newPoints
		var idxMap: [String: Int] = [:]
		idxMap.reserveCapacity(newPoints.count)
		for (idx, p) in newPoints.enumerated() {
			idxMap[p.id] = idx
		}
		indexByID = idxMap
	}
	
	static func dayKey(for date: Date) -> String {
		dayFormatter.string(from: date)
	}
	
	static func pointID(accountID: User.ID, dayKey: String) -> String {
		"\(accountID.description.lowercased())_\(dayKey)"
	}
	
	// MARK: - Passive Recording
	
	func record(accountXP: AccountXP, for accountID: User.ID) {
		recordBatch(accountXP: accountXP, for: accountID)
	}
	
	func record(wallet: StoreWallet, for accountID: User.ID) {
		recordBatch(wallet: wallet, for: accountID)
	}
	
	func record(summary: CareerSummary, seasons: SeasonCollection.Accessor?, for accountID: User.ID) {
		recordBatch(summary: summary, seasons: seasons, for: accountID)
	}
	
	func record(identity: Player.Identity, for accountID: User.ID) {
		recordBatch(identity: identity, for: accountID)
	}
	
	func recordBatch(
		accountXP: AccountXP? = nil,
		wallet: StoreWallet? = nil,
		summary: CareerSummary? = nil,
		seasons: SeasonCollection.Accessor? = nil,
		identity: Player.Identity? = nil,
		for accountID: User.ID
	) {
		var working = points
		var workingIndex = indexByID
		var changed = false
		var orderMayHaveChanged = false
		let now = Date()
		
		if let accountXP {
			let historyEntries = accountXP.history.sorted { $0.matchStart < $1.matchStart }
			for entry in historyEntries {
				let res = applyMutation(
					in: &working,
					indexByID: &workingIndex,
					accountID: accountID,
					date: entry.matchStart
				) { point in
					if point.accountLevel == nil || entry.matchStart >= point.recordedAt {
						point.accountLevel = entry.endProgress.level
						point.accountXP = max(0, min(5_000, entry.endProgress.xp))
					}
				}
				if res.changed {
					changed = true
					if res.needsResort { orderMayHaveChanged = true }
				}
			}
			let res = applyMutation(
				in: &working,
				indexByID: &workingIndex,
				accountID: accountID,
				date: now
			) { point in
				point.accountLevel = accountXP.progress.level
				point.accountXP = max(0, min(5_000, accountXP.progress.xp))
			}
			if res.changed {
				changed = true
				if res.needsResort { orderMayHaveChanged = true }
			}
		}
		
		if let wallet {
			let res = applyMutation(
				in: &working,
				indexByID: &workingIndex,
				accountID: accountID,
				date: now
			) { point in
				point.vp = wallet[.valorantPoints]
				point.rp = wallet[.radianitePoints]
				point.kc = wallet[.kingdomCredits]
			}
			if res.changed {
				changed = true
				if res.needsResort { orderMayHaveChanged = true }
			}
		}
		
		if let summary,
		   let currentAct = seasons?.currentAct(),
		   let info = summary.competitiveInfo?.inSeason(currentAct.id) {
			let res = applyMutation(
				in: &working,
				indexByID: &workingIndex,
				accountID: accountID,
				date: now
			) { point in
				if info.competitiveTier > 0 {
					point.competitiveTier = info.competitiveTier
					point.rankedRating = info.adjustedRankedRating
				}
				if info.leaderboardRank > 0 {
					point.leaderboardRank = info.leaderboardRank
				} else if point.recordedAt <= now, point.leaderboardRank != nil, info.competitiveTier > 0 {
					point.leaderboardRank = nil
				}
			}
			if res.changed {
				changed = true
				if res.needsResort { orderMayHaveChanged = true }
			}
		}
		
		if let identity, identity.accountLevel > 0 {
			let res = applyMutation(
				in: &working,
				indexByID: &workingIndex,
				accountID: accountID,
				date: now
			) { point in
				if let existingLevel = point.accountLevel {
					if identity.accountLevel > existingLevel {
						point.accountLevel = identity.accountLevel
						point.accountXP = nil
					}
				} else {
					point.accountLevel = identity.accountLevel
				}
			}
			if res.changed {
				changed = true
				if res.needsResort { orderMayHaveChanged = true }
			}
		}
		
		guard changed else { return }
		commit(working, indexByID: workingIndex, needsResort: orderMayHaveChanged)
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
		points.first(where: { $0.accountID == accountID })?.recordedAt
	}
	
	// MARK: - Backup Support
	
	func exportPoints(for playerFilter: Set<User.ID>?) -> [ProgressTimelinePoint] {
		guard let playerFilter else { return points }
		return points.filter { playerFilter.contains($0.accountID) }
	}
	
	@discardableResult
	func importPoints(_ incoming: [ProgressTimelinePoint], replaceAll: Bool) async -> Int {
		await waitUntilLoaded()
		debouncedSaveTask?.cancel()
		var workingByID: [String: ProgressTimelinePoint] = [:]
		if !replaceAll {
			workingByID.reserveCapacity(points.count + incoming.count)
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
		applyCommittedPoints(mergedSorted)
		await LocalJSONStore.saveAndWait(points, to: filename)
		return replaceAll ? mergedSorted.count : changedCount
	}
	
	// MARK: - Helpers
	
	private func applyMutation(
		in working: inout [ProgressTimelinePoint],
		indexByID: inout [String: Int],
		accountID: User.ID,
		date: Date,
		mutate: (inout ProgressTimelinePoint) -> Void
	) -> (changed: Bool, needsResort: Bool) {
		let key = Self.dayKey(for: date)
		let id = Self.pointID(accountID: accountID, dayKey: key)
		
		if let index = indexByID[id] ?? working.firstIndex(where: { $0.id == id || ($0.accountID == accountID && $0.dayKey == key) }) {
			let original = working[index]
			var updated = original
			updated.id = id
			mutate(&updated)
			// Compare metric fields BEFORE updating recordedAt so no-op calls don't trigger re-sorts or disk rewrites.
			guard updated != original else { return (false, false) }
			if date > updated.recordedAt {
				updated.recordedAt = date
			}
			working[index] = updated
			indexByID[id] = index
			let needsResort = (index + 1 < working.count && updated.recordedAt > working[index + 1].recordedAt)
				|| (index > 0 && updated.recordedAt < working[index - 1].recordedAt)
			return (true, needsResort)
		} else {
			var created = ProgressTimelinePoint(
				id: id,
				accountID: accountID,
				dayKey: key,
				recordedAt: date
			)
			mutate(&created)
			let needsResort = working.last.map { created.recordedAt < $0.recordedAt || (created.recordedAt == $0.recordedAt && created.id < $0.id) } ?? false
			indexByID[id] = working.count
			working.append(created)
			return (true, needsResort)
		}
	}
	
	private func commit(_ working: [ProgressTimelinePoint], indexByID workingIndex: [String: Int], needsResort: Bool) {
		if needsResort || working.count > Self.maxStoredPoints {
			let sorted = Self.sortedAndTrimmed(working)
			applyCommittedPoints(sorted)
		} else {
			points = working
			indexByID = workingIndex
		}
		schedulePersist()
	}
	
	private func schedulePersist() {
		debouncedSaveTask?.cancel()
		debouncedSaveTask = Task { @MainActor [weak self] in
			try? await Task.sleep(nanoseconds: Self.saveDebounceNanoseconds)
			guard let self, !Task.isCancelled else { return }
			await self.waitUntilLoaded()
			guard !Task.isCancelled else { return }
			LocalJSONStore.save(self.points, to: self.filename)
		}
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
