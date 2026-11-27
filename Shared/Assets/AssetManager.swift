import SwiftUI
import ValorantAPI
import UserDefault
import HandyOperators
import WidgetKit

@MainActor
final class AssetManager: ObservableObject {
	@Published private(set) var assets: AssetCollection?
	@Published private(set) var error: Error?
	private var isDownloading = false
	private var initialDiskLoadTask: Task<Void, Never>?
	
	var languageOverride: String? {
		storage.languageOverride
	}
	
	var installedAt: Date? {
		storage.installedAt
	}
	
	var hasBackup: Bool {
		FileManager.default.fileExists(atPath: Self.backupFileURL.path)
	}
	
	@Published private var storage: Storage
	
	private nonisolated static let legacyStoredDefaultsKey = "AssetManager.stored"
	
	nonisolated static var storedFileURL: URL {
		FolderLocations.localData.appendingPathComponent("AssetCollection.json", isDirectory: false)
	}
	
	nonisolated static var backupFileURL: URL {
		FolderLocations.localData.appendingPathComponent("AssetBackup.bin", isDirectory: false)
	}
	
	init() {
		let storage = PerfMonitor.measure("AssetManager.init", warnOverMs: 0) {
			Storage()
		}
		self.storage = storage
		
#if WIDGETS
		let loaded = Self.loadStoredAssetsFromDiskOrMigrate()
		self.assets = loaded
		if loaded != nil, storage.installedAt == nil {
			self.storage.installedAt = Date()
		}
		Task { await tryLoadAssets() }
#else
		if isInSwiftUIPreview {
			let loaded = Self.loadStoredAssetsFromDiskOrMigrate()
			self.assets = loaded
			if loaded != nil, storage.installedAt == nil {
				self.storage.installedAt = Date()
			}
			Task { await tryLoadAssets() }
		} else {
			let loadTask = Task { @MainActor [weak self] in
				let loaded = await Task.detached(priority: .userInitiated) {
					Self.loadStoredAssetsFromDiskOrMigrate()
				}.value
				guard let self else { return }
				if self.assets == nil, let loaded {
					self.assets = loaded
					if self.storage.installedAt == nil {
						self.storage.installedAt = Date()
					}
				}
			}
			self.initialDiskLoadTask = loadTask
			Task { [weak self] in
				await loadTask.value
				await self?.tryLoadAssets()
			}
		}
#endif
	}
	
	private init(assets: AssetCollection?) {
		self.storage = Storage()
		self.assets = assets
		
		Task { await tryLoadAssets() }
	}
	
	func setLanguageOverride(to language: String?) async {
		storage.languageOverride = language
		await tryLoadAssets()
		WidgetCenter.shared.reloadAllTimelines()
	}
	
	func tryLoadAssets() async {
		await initialDiskLoadTask?.value
		guard !isDownloading else { return }
		isDownloading = true
		defer { isDownloading = false }
		
		// Only publish actual changes: this runs on every scene activation (e.g. returning from Mail
		// during 2FA), and a spurious objectWillChange re-renders the whole app, including open sheets.
		if self.error != nil { self.error = nil }
		do {
			let loaded = try await loadAssets()
			if let current = assets, current.version == loaded.version, current.language == loaded.language, storage.schemaVersion == Self.currentSchemaVersion {
				if current.flex.isEmpty != loaded.flex.isEmpty
					|| current.levelBorders.isEmpty != loaded.levelBorders.isEmpty
					|| current.gamePods.isEmpty != loaded.gamePods.isEmpty {
					assets = loaded
				}
				return
			}
			assets = loaded
		} catch {
			self.error = error
		}
	}
	
	/// Checks for newer assets on Valorant-API and downloads them if an update is available.
	/// - returns: `true` if new assets were downloaded, `false` if already up to date.
	@discardableResult
	func checkForUpdates() async throws -> Bool {
		await initialDiskLoadTask?.value
		guard !isDownloading else { return false }
		isDownloading = true
		defer { isDownloading = false }
		
		error = nil
		let language = resolvedLanguage
		let client = AssetClient(language: language)
		let newest = try await client.getCurrentVersion()
		
		if let current = assets, storage.schemaVersion == Self.currentSchemaVersion, current.version == newest, current.language == language {
			return false
		}
		
		let downloaded = try await downloadAndStore(client: client, version: newest, existingAssets: assets)
		assets = downloaded
		return true
	}
	
	func repairAssets(imageManager: ImageManager = .shared) async {
		await imageManager.clear()
		await reset()
		await tryLoadAssets()
	}
	
	func reset() async {
		await initialDiskLoadTask?.value
		error = nil
		assets = nil
		storage.schemaVersion = 0
		await Task.detached(priority: .utility) {
			try? FileManager.default.removeItem(at: Self.storedFileURL)
			UserDefaults.shared.removeObject(forKey: Self.legacyStoredDefaultsKey)
		}.value
	}
	
	nonisolated static func computeStorageSizes() async -> (installedBytes: Int64, backupBytes: Int64, widgetBytes: Int64) {
		await Task.detached(priority: .userInitiated) {
			let fileBytes = FileManager.default.sizeOfItem(atPath: Self.storedFileURL.path)
			let installedBytes = Int64(fileBytes ?? Self.legacyStoredDefaultsData()?.count ?? 0)
			let backupBytes = Int64(FileManager.default.sizeOfItem(atPath: Self.backupFileURL.path) ?? 0)
			let widgetBytes = Self.computeWidgetBytes()
			return (installedBytes, backupBytes, widgetBytes)
		}.value
	}
	
	private nonisolated static func legacyStoredDefaultsData() -> Data? {
		(UserDefaults.shared.array(forKey: legacyStoredDefaultsKey) as? [Data])?.first
			?? UserDefaults.shared.data(forKey: legacyStoredDefaultsKey)
	}
	
	nonisolated static func loadCachedAssetsFromDisk() -> AssetCollection? {
		loadStoredAssetsFromDiskOrMigrate()
	}
	
	private nonisolated static func loadStoredAssetsFromDiskOrMigrate() -> AssetCollection? {
		PerfMonitor.measure("AssetManager.loadStoredAssets", warnOverMs: 5.0) {
			let fm = FileManager.default
			let decoder = JSONDecoder()
			
			if fm.fileExists(atPath: storedFileURL.path) {
				if let data = try? Data(contentsOf: storedFileURL),
				   let decoded = try? decoder.decode(AssetCollection.self, from: data) {
					return decoded
				}
				if fm.fileExists(atPath: backupFileURL.path),
				   let backupData = try? Data(contentsOf: backupFileURL),
				   let decodedBackup = try? decoder.decode(AssetCollection.self, from: backupData) {
					return decodedBackup
				}
				return nil
			}
			
			if let legacyData = legacyStoredDefaultsData(),
			   let decoded = try? decoder.decode(AssetCollection.self, from: legacyData) {
				do {
					try fm.createDirectory(
						at: storedFileURL.deletingLastPathComponent(),
						withIntermediateDirectories: true
					)
					try legacyData.write(to: storedFileURL, options: .atomic)
					UserDefaults.shared.removeObject(forKey: legacyStoredDefaultsKey)
				} catch {
					print("Failed to migrate AssetCollection to file:", error)
				}
				return decoded
			}
			
			if fm.fileExists(atPath: backupFileURL.path),
			   let backupData = try? Data(contentsOf: backupFileURL),
			   let decodedBackup = try? decoder.decode(AssetCollection.self, from: backupData) {
				return decodedBackup
			}
			return nil
		}
	}
	
	private nonisolated static func computeWidgetBytes() -> Int64 {
		guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.juliand665.Recon-Bolt.shared") else {
			return 0
		}
		let cachesURL = groupURL.appendingPathComponent("Library/Caches", isDirectory: true)
		guard let contents = try? FileManager.default.contentsOfDirectory(
			at: cachesURL,
			includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
		) else {
			return 0
		}
		var total: Int64 = 0
		for item in contents where item.lastPathComponent != "AssetImage" {
			total += directoryOrFileSize(at: item)
		}
		return total
	}
	
	private nonisolated static func directoryOrFileSize(at url: URL) -> Int64 {
		guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else {
			return 0
		}
		if values.isDirectory == true {
			guard let children = try? FileManager.default.contentsOfDirectory(
				at: url,
				includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
			) else { return 0 }
			return children.reduce(0) { $0 + directoryOrFileSize(at: $1) }
		}
		return Int64(values.fileSize ?? 0)
	}
	
	#if DEBUG
	static let forPreviews = AssetManager()
	static let mockEmpty = AssetManager(assets: nil)
	#endif
	
	private static let currentSchemaVersion = 7
	
	var resolvedLanguage: String {
		languageOverride
		?? Bundle.preferredLocalizations(from: Locale.valorantLanguages).first
		?? "en-US"
	}
	
	private func loadAssets() async throws -> AssetCollection {
		let language = resolvedLanguage
		let client = AssetClient(language: language)
		
		let version = try await client.getCurrentVersion()
		if
			storage.schemaVersion == Self.currentSchemaVersion,
			let stored = self.assets,
			stored.version == version,
			stored.language == language
		{
			return stored
		} else {
			return try await downloadAndStore(client: client, version: version, existingAssets: self.assets)
		}
	}
	
	private func downloadAndStore(
		client: AssetClient,
		version: AssetVersion,
		existingAssets: AssetCollection?
	) async throws -> AssetCollection {
		var downloaded = try await client.collectAssets(for: version)
		if let existing = existingAssets, existing.language == downloaded.language {
			if (downloaded.flex.isEmpty && !existing.flex.isEmpty)
				|| (downloaded.levelBorders.isEmpty && !existing.levelBorders.isEmpty)
				|| (downloaded.gamePods.isEmpty && !existing.gamePods.isEmpty) {
				downloaded = AssetCollection(
					version: downloaded.version,
					language: downloaded.language,
					maps: downloaded.maps,
					agents: downloaded.agents,
					missions: downloaded.missions,
					contracts: downloaded.contracts,
					gameModes: downloaded.gameModes,
					queues: downloaded.queues,
					objectives: downloaded.objectives,
					playerCards: downloaded.playerCards,
					playerTitles: downloaded.playerTitles,
					weapons: downloaded.weapons,
					seasons: downloaded.seasons,
					skinsByLevelID: downloaded.skinsByLevelID,
					sprays: downloaded.sprays,
					buddies: downloaded.buddies,
					buddiesByLevelID: downloaded.buddiesByLevelID,
					currencies: downloaded.currencies,
					bundles: downloaded.bundles,
					contentTiers: downloaded.contentTiers,
					flex: downloaded.flex.isEmpty ? existing.flex : downloaded.flex,
					levelBorders: downloaded.levelBorders.isEmpty ? existing.levelBorders : downloaded.levelBorders,
					gamePods: downloaded.gamePods.isEmpty ? existing.gamePods : downloaded.gamePods
				)
			}
		}
		let finalCollection = downloaded
		try await Task.detached(priority: .userInitiated) {
			let fm = FileManager.default
			try fm.createDirectory(
				at: Self.storedFileURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			if fm.fileExists(atPath: Self.storedFileURL.path) {
				let tempBackup = Self.backupFileURL.appendingPathExtension("tmp")
				try? fm.removeItem(at: tempBackup)
				try? fm.copyItem(at: Self.storedFileURL, to: tempBackup)
				if fm.fileExists(atPath: tempBackup.path) {
					try? fm.removeItem(at: Self.backupFileURL)
					try? fm.moveItem(at: tempBackup, to: Self.backupFileURL)
				}
			} else if let legacyData = Self.legacyStoredDefaultsData() {
				try? legacyData.write(to: Self.backupFileURL, options: .atomic)
			}
			let encoded = try JSONEncoder().encode(finalCollection)
			try encoded.write(to: Self.storedFileURL, options: .atomic)
			UserDefaults.shared.removeObject(forKey: Self.legacyStoredDefaultsKey)
		}.value
		storage.schemaVersion = Self.currentSchemaVersion
		storage.installedAt = Date()
		return finalCollection
	}
	
	private struct Storage {
		@UserDefault("AssetManager.languageOverride", defaults: .shared)
		var languageOverride: String?
		@UserDefault("AssetManager.schemaVersion", defaults: .shared)
		var schemaVersion = 0
		@UserDefault("AssetManager.installedAt", defaults: .shared)
		var installedAt: Date?
	}
}

extension EnvironmentValues {
	var assets: AssetCollection? {
		get { self[Key.self] }
		set { self[Key.self] = newValue }
	}
	
	private enum Key: EnvironmentKey {
		#if WIDGETS
		@MainActor static let defaultValue: AssetCollection? = Managers.assets.assets
		#elseif DEBUG
		@MainActor static let defaultValue = isInSwiftUIPreview ? AssetManager.forPreviews.assets : nil
		#else
		@MainActor static let defaultValue: AssetCollection? = nil
		#endif
	}
}
