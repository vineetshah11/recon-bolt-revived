import Foundation
import Combine
import HandyOperators

typealias LocalDataPublisher<Value> = AnyPublisher<(value: Value, wasCached: Bool), Never>

/// - "mom can we have a database?"
/// - "no honey we have a database at home"
/// - database at home:
@MainActor
final class LocalDataManager<Object: Identifiable & Codable> where Object.ID: LosslessStringConvertible {
	private typealias Subject = PassthroughSubject<Object, Never>
	
	// not @Published so we have manual control, avoiding many publishes when working in bulk
	private var cache: [Object.ID: Entry?] = [:] // nil values represent that we've confirmed there's no cache file
	private var subjects: [Object.ID: Subject] = [:]
	private var inFlightDiskLoads: [Object.ID: Task<Entry?, Never>] = [:]
	private var accessOrder: [Object.ID] = []
	private let maxInMemoryEntries: Int?
	private let storage: Storage
	
	let changePublisher = PassthroughSubject<Void, Never>()
	
	nonisolated let folderURL: URL
	/// When the object was last updated longer ago than this, it is automatically updated on next fetch.
	let ageCausingAutoUpdate: TimeInterval?
	
	nonisolated init(
		localPath: String = "\(Object.self)",
		ageCausingAutoUpdate: TimeInterval? = nil,
		maxInMemoryEntries: Int? = nil
	) {
		self.folderURL = FolderLocations.localData.appendingPathComponent(localPath) <- {
			try? FileManager.default.createDirectory(
				at: $0,
				withIntermediateDirectories: true,
				attributes: nil
			)
		}
		self.ageCausingAutoUpdate = ageCausingAutoUpdate
		self.maxInMemoryEntries = maxInMemoryEntries
		self.storage = .init(folderURL: folderURL)
	}
	
	private func recordAccess(for id: Object.ID) {
		guard maxInMemoryEntries != nil else { return }
		accessOrder.removeAll { $0 == id }
		accessOrder.append(id)
	}
	
	private func evictIfNeeded() {
		guard let limit = maxInMemoryEntries, limit > 0 else { return }
		while accessOrder.count > limit {
			let oldest = accessOrder.removeFirst()
			cache.removeValue(forKey: oldest)
		}
	}
	
	private static func areEqual(_ lhs: Object, _ rhs: Object) -> Bool {
		guard let eqL = lhs as? any Equatable else { return false }
		return isEqualAny(eqL, rhs)
	}
	
	private static func isEqualAny<T: Equatable>(_ lhs: T, _ rhs: Object) -> Bool {
		guard let typedR = rhs as? T else { return false }
		return lhs == typedR
	}
	
	func store<S: Sequence>(_ objects: S, asOf updateTime: Date) where S.Element == Object {
		var didChange = false
		var entriesToSave: [Entry] = []
		
		for object in objects {
			if let existing = cache[object.id] ?? nil {
				if existing.lastUpdate > updateTime {
					continue
				}
				if Self.areEqual(existing.object, object) {
					cache[object.id] = Entry(lastUpdate: updateTime, object: existing.object)
					recordAccess(for: object.id)
					continue
				}
			}
			let entry = Entry(lastUpdate: updateTime, object: object)
			cache[object.id] = entry
			recordAccess(for: object.id)
			subjects[object.id]?.send(object)
			entriesToSave.append(entry)
			didChange = true
		}
		
		guard didChange else { return }
		evictIfNeeded()
		changePublisher.send()
		
		Task.detached(priority: .utility) { [storage] in
			await storage.trySaveEntries(entriesToSave)
		}
	}
	
	func store(_ object: Object, asOf updateTime: Date) {
		let existing = cache[object.id] ?? nil
		if let existing {
			if existing.lastUpdate > updateTime { return }
			if Self.areEqual(existing.object, object) {
				cache[object.id] = Entry(lastUpdate: updateTime, object: existing.object)
				recordAccess(for: object.id)
				return
			}
		}
		
		let entry = Entry(lastUpdate: updateTime, object: object)
		cache[object.id] = entry
		recordAccess(for: object.id)
		evictIfNeeded()
		subjects[object.id]?.send(object)
		changePublisher.send()
		
		Task.detached(priority: .utility) { [storage] in
			await storage.trySave(entry)
		}
	}
	
	func loadedObject(for id: Object.ID) -> Object? {
		cache[id]??.object
	}
	
	func hasCachedFile(for id: Object.ID) async -> Bool {
		if let cached = cache[id] {
			return cached != nil
		}
		if let inFlight = inFlightDiskLoads[id] {
			return await inFlight.value != nil
		}
		return await storage.fileExists(for: id)
	}
	
	private func cachedEntry(for id: Object.ID) async -> Entry? {
		if let cached = cache[id] {
			if cached != nil {
				recordAccess(for: id)
			}
			return cached
		}
		if let existingTask = inFlightDiskLoads[id] {
			return await existingTask.value
		}
		let task = Task { [storage] in
			await storage.tryLoadEntry(with: id)
		}
		inFlightDiskLoads[id] = task
		let loaded = await task.value
		inFlightDiskLoads[id] = nil
		if let existing = cache[id] {
			if existing != nil {
				recordAccess(for: id)
			}
			return existing
		}
		cache[id] = loaded
		if loaded != nil {
			recordAccess(for: id)
			evictIfNeeded()
			changePublisher.send()
		}
		return loaded
	}
	
	private func cachedEntries(for ids: Set<Object.ID>) async -> [Entry] {
		var resolved: [Entry] = []
		var missingIDs: Set<Object.ID> = []
		var pendingTasks: [(Object.ID, Task<Entry?, Never>)] = []
		
		for id in ids {
			if let cached = cache[id] {
				if let cached {
					recordAccess(for: id)
					resolved.append(cached)
				}
			} else if let inFlight = inFlightDiskLoads[id] {
				pendingTasks.append((id, inFlight))
			} else {
				missingIDs.insert(id)
			}
		}
		
		for (id, task) in pendingTasks {
			if let entry = await task.value {
				resolved.append(entry)
				recordAccess(for: id)
			}
		}
		
		if !missingIDs.isEmpty {
			let loadedEntries = await storage.tryLoadEntries(with: missingIDs)
			let loadedByID = Dictionary(values: loadedEntries)
			for id in missingIDs {
				if let existing = cache[id] {
					if let existing {
						recordAccess(for: id)
						resolved.append(existing)
					}
					continue
				}
				let entry = loadedByID[id]
				cache[id] = entry
				if let entry {
					recordAccess(for: id)
					resolved.append(entry)
				}
			}
			evictIfNeeded()
			if !loadedEntries.isEmpty {
				changePublisher.send()
			}
		}
		
		return resolved
	}
	
	func cachedObject(for id: Object.ID) async -> Object? {
		await cachedEntry(for: id)?.object
	}
	
	func cachedObjects(for ids: some Sequence<Object.ID>) async -> [Object] {
		await cachedEntries(for: Set(ids)).map(\.object)
	}
	
	/// Loads objects directly from disk without populating or evicting the in-memory LRU cache.
	func loadFromDiskOnly(for ids: some Sequence<Object.ID>) async -> [Object] {
		let uniqueIDs = Set(ids)
		guard !uniqueIDs.isEmpty else { return [] }
		return await storage.tryLoadEntries(with: uniqueIDs).map(\.object)
	}
	
	func allCachedIDs() async -> [Object.ID] {
		var ids = Set(await storage.allStoredIDs())
		for (id, entry) in cache where entry != nil {
			ids.insert(id)
		}
		return Array(ids)
	}
	
	func diskSizesByID() async -> [Object.ID: Int64] {
		await storage.fileSizesByID()
	}
	
	/// Loads `Entry` values for backup export without altering the in-memory LRU cache.
	/// Prefers non-nil in-memory entries so freshly stored objects whose async write may still be pending are included.
	func loadEntriesFromDiskOnly(for ids: some Sequence<Object.ID>) async -> [Entry] {
		let uniqueIDs = Set(ids)
		guard !uniqueIDs.isEmpty else { return [] }
		var entries: [Entry] = []
		var remaining: [Object.ID] = []
		for id in uniqueIDs {
			if let cached = cache[id] ?? nil {
				entries.append(cached)
			} else {
				remaining.append(id)
			}
		}
		if !remaining.isEmpty {
			entries.append(contentsOf: await storage.tryLoadEntries(with: remaining))
		}
		return entries
	}
	
	@discardableResult
	func importEntries(_ entries: [Entry], replaceAll: Bool) async throws -> Int {
		var deduplicated: [Object.ID: Entry] = [:]
		for entry in entries {
			if let existing = deduplicated[entry.id], existing.lastUpdate >= entry.lastUpdate {
				continue
			}
			deduplicated[entry.id] = entry
		}
		
		if replaceAll {
			try await clearOut()
		}
		
		let toSave: [Entry]
		if replaceAll {
			toSave = Array(deduplicated.values)
		} else {
			let incomingIDs = Array(deduplicated.keys)
			let existingByID = await existingEntriesByID(for: incomingIDs)
			toSave = deduplicated.values.filter { incoming in
				guard let existing = existingByID[incoming.id] else { return true }
				return incoming.lastUpdate > existing.lastUpdate
			}
		}
		
		return try await persistImportedEntries(toSave, forceChangeNotification: replaceAll)
	}
	
	func existingEntriesByID(for ids: [Object.ID]) async -> [Object.ID: Entry] {
		var result: [Object.ID: Entry] = [:]
		var missingIDs: [Object.ID] = []
		for id in ids {
			if let cached = cache[id] ?? nil {
				result[id] = cached
			} else {
				missingIDs.append(id)
			}
		}
		if !missingIDs.isEmpty {
			for entry in await storage.tryLoadEntries(with: missingIDs) {
				result[entry.id] = entry
			}
		}
		return result
	}
	
	func persistImportedEntries(_ toSave: [Entry], forceChangeNotification: Bool = false) async throws -> Int {
		if !toSave.isEmpty {
			try await storage.saveEntries(toSave)
		}
		for entry in toSave {
			if maxInMemoryEntries == nil || (cache[entry.id] ?? nil) != nil {
				cache[entry.id] = entry
				recordAccess(for: entry.id)
			} else {
				cache.removeValue(forKey: entry.id)
			}
			subjects[entry.id]?.send(entry.object)
		}
		evictIfNeeded()
		if !toSave.isEmpty || forceChangeNotification {
			changePublisher.send()
		}
		return toSave.count
	}
	
	nonisolated func objectPublisher(for id: Object.ID) -> LocalDataPublisher<Object> {
		Future { promise in
			Task {
				promise(.success(await self._objectPublisher(for: id)))
			}
		}
		.flatMap { $0 }
		.eraseToAnyPublisher()
	}
	
	private func _objectPublisher(for id: Object.ID) async -> LocalDataPublisher<Object> {
		await cachedObject(for: id).publisher.map { (value: $0, wasCached: true) }
			.merge(with: subject(for: id).map { (value: $0, wasCached: false) })
			.eraseToAnyPublisher()
	}
	
	private func subject(for id: Object.ID) -> Subject {
		subjects[id] ?? (.init() <- { subjects[id] = $0 })
	}
	
	private var inProgressUpdates: Set<Object.ID> = []
	
	func autoUpdateObject(for id: Object.ID, update: (Object?) async throws -> Object) async throws {
		guard inProgressUpdates.insert(id).inserted else { return }
		defer { inProgressUpdates.remove(id) }
		
		let cached = await cachedEntry(for: id)
		if let cached, !shouldAutoUpdate(cached) {
			return // nothing to do
		}
		
		// auto-update necessary
		try await tryLoad {
			try await update(cached?.object) <- { store($0, asOf: .now) }
		}
	}
	
	func fetchIfNecessary(for id: Object.ID, fetch: (Object.ID) async throws -> Object) async throws {
		try await autoUpdateObject(for: id) { _ in try await fetch(id) }
	}
	
	func fetchIfNecessary(_ ids: [Object.ID], fetch: ([Object.ID]) async throws -> [Object]) async throws {
		let uniqueIDs = Set(ids)
		guard !uniqueIDs.isEmpty else { return }
		let cached = await cachedEntries(for: uniqueIDs)
		let freshIDs = Set(cached.lazy.filter { !self.shouldAutoUpdate($0) }.map(\.id))
		let missingOrStale = uniqueIDs.subtracting(freshIDs)
		let toFetch = missingOrStale.subtracting(inProgressUpdates)
		guard !toFetch.isEmpty else { return }
		inProgressUpdates.formUnion(toFetch)
		defer { inProgressUpdates.subtract(toFetch) }
		try await fetch(Array(toFetch)) <- { store($0, asOf: .now) }
	}
	
	@discardableResult
	private nonisolated func tryLoad<T>(load: () async throws -> T) async throws -> T? {
		do {
			return try await load()
		} catch let error as URLError {
			// error loading data: assume offline
			dump(error)
			return nil
		}
	}
	
	private nonisolated func shouldAutoUpdate(_ entry: Entry) -> Bool {
		guard let threshold = ageCausingAutoUpdate else { return false }
		return -entry.lastUpdate.timeIntervalSinceNow > threshold
	}
	
	struct DiskUsage {
		var tally: [Object.ID: Int64] = [:]
		var unaccountedFor: Int64 = 0
		var unknownIDs: Set<Object.ID> = []
	}
	
	struct Entry: Codable, Identifiable {
		var lastUpdate = Date()
		var object: Object
		
		var id: Object.ID { object.id }
	}
	
	final actor Storage {
		let folderURL: URL
		private let decoder = JSONDecoder()
		private let encoder = JSONEncoder()
		
		init(folderURL: URL) {
			self.folderURL = folderURL
		}
		
		private nonisolated func fileURL(for id: Object.ID) -> URL {
			folderURL.appendingPathComponent("\(id.description).json")
		}
		
		func fileExists(for id: Object.ID) -> Bool {
			FileManager.default.fileExists(atPath: fileURL(for: id).path)
		}
		
		func trySave(_ entry: Entry) {
			do {
				try save(entry)
			} catch {
				print("error saving \(entry) to disk: \(error)")
				dump(error)
			}
		}
		
		func trySaveEntries(_ entries: [Entry]) {
			do {
				try saveEntries(entries)
			} catch {
				print("error saving \(entries.count) entries to disk: \(error)")
				dump(error)
			}
		}
		
		func tryLoadEntries(with ids: any Sequence<Object.ID>) -> [Entry] {
			ids.compactMap(tryLoadEntry(with:))
		}
		
		func tryLoadEntry(with id: Object.ID) -> Entry? {
			do {
				return try loadEntry(with: id)
			} catch {
				print("error loading entry with id \(id) from disk: \(error)")
				dump(error)
				return nil
			}
		}
		
		private func loadEntry(with id: Object.ID) throws -> Entry? {
			let url = fileURL(for: id)
			guard FileManager.default.fileExists(atPath: url.path) else { return nil }
			let data = try Data(contentsOf: url)
			return try decoder.decode(Entry.self, from: data)
		}
		
		private func save(_ entry: Entry) throws {
			let raw = try encoder.encode(entry)
			let url = fileURL(for: entry.id)
			try raw.write(to: url, options: .atomic)
		}
		
		func saveEntries(_ entries: [Entry]) throws {
			try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
			for entry in entries {
				try save(entry)
			}
		}
		
		func allStoredIDs() -> [Object.ID] {
			guard let files = try? FileManager.default.contentsOfDirectory(
				at: folderURL,
				includingPropertiesForKeys: []
			) else {
				return []
			}
			return files.compactMap { file in
				guard file.pathExtension.lowercased() == "json" else { return nil }
				return Object.ID(file.deletingPathExtension().lastPathComponent)
			}
		}
		
		func fileSizesByID() -> [Object.ID: Int64] {
			guard let files = try? FileManager.default.contentsOfDirectory(
				at: folderURL,
				includingPropertiesForKeys: [.fileSizeKey]
			) else {
				return [:]
			}
			var sizes: [Object.ID: Int64] = [:]
			for file in files where file.pathExtension.lowercased() == "json" {
				guard let id = Object.ID(file.deletingPathExtension().lastPathComponent) else { continue }
				let values = try? file.resourceValues(forKeys: [.fileSizeKey])
				sizes[id, default: 0] += Int64(values?.fileSize ?? 0)
			}
			return sizes
		}
	}
}

extension LocalDataManager {
	func diskUsage(for ids: some Sequence<Object.ID>) async throws -> DiskUsage {
		try await storage.diskUsage(for: ids)
	}
	
	func clearOut(idFilter: Set<Object.ID>? = nil) async throws {
		try await storage.clearOut(idFilter: idFilter)
		
		if let idFilter {
			for id in idFilter {
				cache.removeValue(forKey: id)
			}
			accessOrder.removeAll { idFilter.contains($0) }
		} else {
			cache = [:]
			accessOrder = []
		}
	}
}

extension LocalDataManager.Storage {
	func diskUsage(for ids: some Sequence<Object.ID>) throws -> LocalDataManager.DiskUsage {
		let files = try FileManager.default.contentsOfDirectory(
			at: folderURL,
			includingPropertiesForKeys: [.fileSizeKey]
		)
		let knownIDs = Set(ids)
		return .init() <- { usage in
			for file in files {
				guard file.pathExtension.lowercased() == "json",
				      let id = Object.ID(file.deletingPathExtension().lastPathComponent),
				      let rawSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
					continue
				}
				let size = Int64(rawSize)
				if knownIDs.contains(id) {
					usage.tally[id, default: 0] += size
				} else {
					usage.unaccountedFor += size
					usage.unknownIDs.insert(id)
				}
			}
		}
	}
	
	func clearOut(idFilter: Set<Object.ID>?) throws {
		let files = try FileManager.default.contentsOfDirectory(
			at: folderURL,
			includingPropertiesForKeys: []
		)
		if let idFilter {
			for file in files {
				guard
					let id = Object.ID(file.deletingPathExtension().lastPathComponent),
					idFilter.contains(id)
				else { continue }
				try FileManager.default.removeItem(at: file)
			}
		} else {
			for file in files {
				try FileManager.default.removeItem(at: file)
			}
		}
	}
}

extension TimeInterval {
	static func minutes(_ minutes: Double) -> Self {
		minutes * 60
	}
	
	static func hours(_ hours: Double) -> Self {
		minutes(hours * 60)
	}
}
