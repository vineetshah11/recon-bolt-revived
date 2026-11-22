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
	
	var languageOverride: String? {
		storage.languageOverride
	}
	
	var installedAt: Date? {
		storage.installedAt
	}
	
	var hasBackup: Bool {
		FileManager.default.fileExists(atPath: Self.backupFileURL.path)
	}
	
	@Published private var storage = Storage()
	
	nonisolated static var backupFileURL: URL {
		FolderLocations.localData.appendingPathComponent("AssetBackup.bin", isDirectory: false)
	}
	
	init() {
		let storage = Storage()
		self.storage = storage
		self.assets = storage.assets
		if storage.assets != nil, storage.installedAt == nil {
			self.storage.installedAt = Date()
		}
		
		Task { await tryLoadAssets() }
	}
	
	private init(assets: AssetCollection?) {
		self.assets = assets
		
		Task { await tryLoadAssets() }
	}
	
	func setLanguageOverride(to language: String?) async {
		storage.languageOverride = language
		await tryLoadAssets()
		WidgetCenter.shared.reloadAllTimelines()
	}
	
	func tryLoadAssets() async {
		guard !isDownloading else { return }
		isDownloading = true
		defer { isDownloading = false }
		
		// Only publish actual changes: this runs on every scene activation (e.g. returning from Mail
		// during 2FA), and a spurious objectWillChange re-renders the whole app, including open sheets.
		if self.error != nil { self.error = nil }
		do {
			let loaded = try await loadAssets()
			if let current = assets, current.version == loaded.version, current.language == loaded.language, !current.flex.isEmpty, !current.levelBorders.isEmpty {
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
		guard !isDownloading else { return false }
		isDownloading = true
		defer { isDownloading = false }
		
		error = nil
		let language = resolvedLanguage
		let client = AssetClient(language: language)
		let newest = try await client.getCurrentVersion()
		
		if let current = assets, current.version == newest, current.language == language, !current.flex.isEmpty, !current.levelBorders.isEmpty {
			return false
		}
		
		let downloaded = try await downloadAndStore(client: client, version: newest)
		assets = downloaded
		return true
	}
	
	func repairAssets(imageManager: ImageManager) async {
		imageManager.clear()
		error = nil
		assets = nil
		storage.assets = nil
		await tryLoadAssets()
	}
	
	func reset() async {
		error = nil
		assets = nil
		storage.assets = nil
	}
	
	func storageSizes() -> (installedBytes: Int64, backupBytes: Int64, widgetBytes: Int64) {
		let storedData = (UserDefaults.shared.array(forKey: "AssetManager.stored") as? [Data])?.first
			?? UserDefaults.shared.data(forKey: "AssetManager.stored")
		let installedBytes = Int64(storedData?.count ?? 0)
		let backupBytes = Int64(FileManager.default.sizeOfItem(atPath: Self.backupFileURL.path) ?? 0)
		let widgetBytes = Self.computeWidgetBytes()
		return (installedBytes, backupBytes, widgetBytes)
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
	
	private static let currentSchemaVersion = 5
	
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
			let stored = storage.assets,
			stored.version == version,
			stored.language == language,
			!stored.flex.isEmpty,
			!stored.levelBorders.isEmpty
		{
			return stored
		} else {
			return try await downloadAndStore(client: client, version: version)
		}
	}
	
	private func downloadAndStore(client: AssetClient, version: AssetVersion) async throws -> AssetCollection {
		let downloaded = try await client.collectAssets(for: version)
		if let existingData = (UserDefaults.shared.array(forKey: "AssetManager.stored") as? [Data])?.first
			?? UserDefaults.shared.data(forKey: "AssetManager.stored")
		{
			try? FileManager.default.createDirectory(
				at: Self.backupFileURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try? existingData.write(to: Self.backupFileURL, options: .atomic)
		}
		storage.assets = downloaded
		storage.schemaVersion = Self.currentSchemaVersion
		storage.installedAt = Date()
		return downloaded
	}
	
	private struct Storage {
		@UserDefault("AssetManager.stored", defaults: .shared)
		var assets: AssetCollection?
		@UserDefault("AssetManager.languageOverride", defaults: .shared)
		var languageOverride: String?
		@UserDefault("AssetManager.schemaVersion", defaults: .shared)
		var schemaVersion = 0
		@UserDefault("AssetManager.installedAt", defaults: .shared)
		var installedAt: Date?
	}
}

extension AssetCollection: DefaultsValueConvertible {}

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
