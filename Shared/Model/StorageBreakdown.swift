import Foundation
import ValorantAPI

struct StorageBreakdown: Sendable {
	var gameAssetsBytes: Int64 = 0
	var matchesBytes: Int64 = 0
	var playerProfilesBytes: Int64 = 0
	var cachedImagesBytes: Int64 = 0
	var deviceOnlyBytes: Int64 = 0
	
	var totalBytes: Int64 {
		gameAssetsBytes + matchesBytes + playerProfilesBytes + cachedImagesBytes + deviceOnlyBytes
	}
	
	var matchesAndDownloadsBytes: Int64 {
		matchesBytes + playerProfilesBytes + cachedImagesBytes
	}
	
	@MainActor
	static func compute(assetManager: AssetManager) async -> StorageBreakdown {
		let matchListURL = LocalDataProvider.shared.matchListManager.folderURL
		let matchDetailsURL = LocalDataProvider.shared.matchDetailsManager.folderURL
		let summaryURL = LocalDataProvider.shared.careerSummaryManager.folderURL
		let userURL = LocalDataProvider.shared.userManager.folderURL
		let identityURL = LocalDataProvider.shared.playerIdentityManager.folderURL
		let imageCacheURL = AssetImage.cacheFolderURL
		let localRootURL = FolderLocations.localData
		
		let managedFolderNames: Set<String> = [
			matchListURL.lastPathComponent,
			matchDetailsURL.lastPathComponent,
			summaryURL.lastPathComponent,
			userURL.lastPathComponent,
			identityURL.lastPathComponent,
			AssetManager.storedFileURL.lastPathComponent,
			AssetManager.backupFileURL.lastPathComponent,
		]
		
		return await Task.detached(priority: .userInitiated) {
			let assetSizes = await AssetManager.computeStorageSizes()
			let assets = assetSizes.installedBytes + assetSizes.backupBytes + assetSizes.widgetBytes
			let matches = Self.directorySize(of: matchListURL) + Self.directorySize(of: matchDetailsURL)
			let profiles = Self.directorySize(of: summaryURL)
				+ Self.directorySize(of: userURL)
				+ Self.directorySize(of: identityURL)
			let images = Self.directorySize(of: imageCacheURL)
			let deviceOnly = Self.deviceOnlySize(in: localRootURL, excluding: managedFolderNames)
			
			return StorageBreakdown(
				gameAssetsBytes: assets,
				matchesBytes: matches,
				playerProfilesBytes: profiles,
				cachedImagesBytes: images,
				deviceOnlyBytes: deviceOnly
			)
		}.value
	}
	
	private nonisolated static func directorySize(of url: URL) -> Int64 {
		let fm = FileManager.default
		guard fm.fileExists(atPath: url.path) else { return 0 }
		guard let items = try? fm.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
		) else {
			return 0
		}
		var total: Int64 = 0
		for item in items {
			guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
			if values.isDirectory == true {
				total += directorySize(of: item)
			} else {
				total += Int64(values.fileSize ?? 0)
			}
		}
		return total
	}
	
	private nonisolated static func deviceOnlySize(in rootURL: URL, excluding excludedNames: Set<String>) -> Int64 {
		let fm = FileManager.default
		guard let items = try? fm.contentsOfDirectory(
			at: rootURL,
			includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
		) else {
			return 0
		}
		var total: Int64 = 0
		for item in items {
			guard !excludedNames.contains(item.lastPathComponent) else { continue }
			guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
			if values.isDirectory == true {
				total += directorySize(of: item)
			} else {
				total += Int64(values.fileSize ?? 0)
			}
		}
		return total
	}
}

@MainActor
enum MatchRetentionManager {
	@discardableResult
	static func pruneIfEnabled(
		settings: AppSettings,
		accountManager: AccountManager,
		bookmarkList: BookmarkList
	) async -> Int {
		let maxAgeDays = settings.matchRetentionDays
		guard maxAgeDays > 0 else { return 0 }
		
		let listManager = LocalDataProvider.shared.matchListManager
		let detailsManager = LocalDataProvider.shared.matchDetailsManager
		
		let ownAccounts = accountManager.storedAccounts
		let bookmarkedUsers = bookmarkList.bookmarks.map(\.user)
		
		let ownLists = await listManager.cachedObjects(for: ownAccounts)
		let bookmarkedLists = await listManager.cachedObjects(for: bookmarkedUsers)
		
		let ownMatchIDs = Set(ownLists.flatMap { $0.matches.map(\.id) })
		let bookmarkedMatchIDs = Set(bookmarkedLists.flatMap { $0.matches.map(\.id) })
		let allLinkedIDs = ownMatchIDs.union(bookmarkedMatchIDs)
		
		let keepsOwn = settings.keepsOwnMatches
		let keepsBookmarked = settings.keepsBookmarkedMatches
		let keepsUnlinked = settings.keepsUnlinkedMatches
		
		let cutoffDate = Date().addingTimeInterval(-Double(maxAgeDays) * Double(86400))
		let folderURL = detailsManager.folderURL
		
		let candidateIDs: Set<Match.ID> = await Task.detached(priority: .utility) {
			let fm = FileManager.default
			guard let files = try? fm.contentsOfDirectory(
				at: folderURL,
				includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
			) else {
				return []
			}
			var toDelete: Set<Match.ID> = []
			for file in files {
				guard let matchID = Match.ID(file.deletingPathExtension().lastPathComponent) else { continue }
				let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
				let modified = values?.contentModificationDate ?? values?.creationDate ?? .now
				guard modified < cutoffDate else { continue }
				
				let isOwn = ownMatchIDs.contains(matchID)
				let isBookmarked = bookmarkedMatchIDs.contains(matchID)
				let isUnlinked = !allLinkedIDs.contains(matchID)
				
				if isOwn && keepsOwn { continue }
				if isBookmarked && keepsBookmarked { continue }
				if isUnlinked && keepsUnlinked { continue }
				
				toDelete.insert(matchID)
			}
			return toDelete
		}.value
		
		guard !candidateIDs.isEmpty else { return 0 }
		do {
			try await detailsManager.clearOut(idFilter: candidateIDs)
			AccoladesCacheStore.shared.remove(matchIDs: candidateIDs)
			GroupPerformanceCacheStore.shared.remove(matchIDs: candidateIDs)
			return candidateIDs.count
		} catch {
			return 0
		}
	}
	
	static func deleteUnlinkedMatches(
		accountManager: AccountManager,
		bookmarkList: BookmarkList
	) async throws -> Int {
		let listManager = LocalDataProvider.shared.matchListManager
		let detailsManager = LocalDataProvider.shared.matchDetailsManager
		
		let knownAccounts = accountManager.storedAccounts + bookmarkList.bookmarks.map(\.user)
		let matchLists = await listManager.cachedObjects(for: knownAccounts)
		let linkedIDs = matchLists.flatMap { $0.matches.map(\.id) }
		let usage = try await detailsManager.diskUsage(for: linkedIDs)
		guard !usage.unknownIDs.isEmpty else { return 0 }
		try await detailsManager.clearOut(idFilter: usage.unknownIDs)
		AccoladesCacheStore.shared.remove(matchIDs: usage.unknownIDs)
		GroupPerformanceCacheStore.shared.remove(matchIDs: usage.unknownIDs)
		return usage.unknownIDs.count
	}
	
	static func deleteAllMatches() async throws {
		try await LocalDataProvider.shared.matchDetailsManager.clearOut()
		AccoladesCacheStore.shared.clearAll()
		GroupPerformanceCacheStore.shared.clearAll()
	}
}
