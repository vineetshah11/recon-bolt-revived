import Foundation
import CryptoKit
import ValorantAPI

@MainActor
struct BackupStores {
	let accountManager: AccountManager
	let bookmarkList: BookmarkList
	let settings: AppSettings
	let loadoutPresetManager: LoadoutPresetManager
	let wishlistManager: WishlistManager
	let shopHistoryStore: ShopHistoryStore
	let usernameHistoryStore: UsernameHistoryStore
	let playerSettingsSnapshotStore: PlayerSettingsSnapshotStore
	let seasonGoalStore: SeasonGoalStore
	let progressTimelineStore: ProgressTimelineStore
	let socialManager: SocialManager
	let lineupsManager: LineupsManager
}

struct BackupSelectablePlayer: Identifiable, Hashable {
	var id: User.ID
	var gameName: String
	var tagLine: String
	var role: BackupPlayerSummary.Role
	var matchCount: Int
	var estimatedBytes: Int64?
	
	var displayName: String {
		if !gameName.isEmpty {
			return tagLine.isEmpty ? gameName : "\(gameName) #\(tagLine)"
		}
		return String(id.description.prefix(8)) + "…"
	}
	
	func toSummary() -> BackupPlayerSummary {
		BackupPlayerSummary(
			id: id,
			gameName: gameName,
			tagLine: tagLine,
			role: role,
			matchCount: matchCount
		)
	}
}

struct BackupInventory {
	var players: [BackupSelectablePlayer] = []
	var matchIDsByPlayer: [User.ID: Set<Match.ID>] = [:]
	var matchListSizes: [User.ID: Int64] = [:]
	var allCachedMatchDetailIDs: Set<Match.ID> = []
	var matchDetailSizes: [Match.ID: Int64] = [:]
	var careerIDs: Set<User.ID> = []
	var careerSizes: [User.ID: Int64] = [:]
	var userIDs: Set<User.ID> = []
	var userSizes: [User.ID: Int64] = [:]
	var identityIDs: Set<User.ID> = []
	var identitySizes: [User.ID: Int64] = [:]
	var usernameHistoryPlayers: Set<User.ID> = []
	var bookmarkedUserIDs: Set<User.ID> = []
	var lookupUserIDs: Set<User.ID> = []
	var shopDayCountsByPlayer: [User.ID: Int] = [:]
	var goalAccountIDs: [User.ID?] = []
	var progressPointCountsByPlayer: [User.ID: Int] = [:]
	var presetAccountIDs: [User.ID?] = []
	var favoritesPresetAccountIDs: [User.ID?] = []
	var snapshotAccountIDs: [User.ID?] = []
	var socialFriendPlayers: Set<User.ID> = []
	var socialMessageCountsByPlayer: [User.ID: Int] = [:]
	var wishlistCount: Int = 0
	var lineupsCount: Int = 0
	var allPlayerIDs: Set<User.ID> = []
	
	func itemCount(for kind: BackupModuleKind, selectedPlayers: Set<User.ID>) -> Int {
		let allSelected = selectedPlayers == allPlayerIDs
		switch kind {
		case .matchLists:
			return matchIDsByPlayer.keys.filter { selectedPlayers.contains($0) }.count
		case .matchDetails:
			if allSelected {
				return allCachedMatchDetailIDs.count
			}
			let referenced = matchIDsByPlayer
				.filter { selectedPlayers.contains($0.key) }
				.values
				.reduce(into: Set<Match.ID>()) { $0.formUnion($1) }
			return referenced.intersection(allCachedMatchDetailIDs).count
		case .careerSummaries:
			return careerIDs.intersection(selectedPlayers).count
		case .users:
			return allSelected ? userIDs.count : userIDs.intersection(selectedPlayers).count
		case .playerIdentities:
			return allSelected ? identityIDs.count : identityIDs.intersection(selectedPlayers).count
		case .usernameHistory:
			return usernameHistoryPlayers.intersection(selectedPlayers).count
		case .bookmarks:
			return bookmarkedUserIDs.intersection(selectedPlayers).count
		case .lookupHistory:
			return lookupUserIDs.intersection(selectedPlayers).count
		case .shopHistory:
			return shopDayCountsByPlayer
				.filter { selectedPlayers.contains($0.key) }
				.values
				.reduce(0, +)
		case .seasonGoals:
			return goalAccountIDs.count { id in
				guard let id else { return !selectedPlayers.isEmpty }
				return selectedPlayers.contains(id)
			}
		case .progressTimeline:
			return progressPointCountsByPlayer
				.filter { selectedPlayers.contains($0.key) }
				.values
				.reduce(0, +)
		case .loadoutPresets:
			return presetAccountIDs.count { id in
				guard let id else { return !selectedPlayers.isEmpty }
				return selectedPlayers.contains(id)
			}
		case .favoritesPresets:
			return favoritesPresetAccountIDs.count { id in
				guard let id else { return !selectedPlayers.isEmpty }
				return selectedPlayers.contains(id)
			}
		case .settingsSnapshots:
			return snapshotAccountIDs.count { id in
				guard let id else { return !selectedPlayers.isEmpty }
				return selectedPlayers.contains(id)
			}
		case .socialFriends:
			return socialFriendPlayers.intersection(selectedPlayers).count
		case .socialMessages:
			return socialMessageCountsByPlayer
				.filter { selectedPlayers.contains($0.key) }
				.values
				.reduce(0, +)
		case .wishlist:
			return wishlistCount
		case .lineupFavorites:
			return lineupsCount
		case .appSettings:
			return 1
		}
	}
	
	func estimatedBytes(for kind: BackupModuleKind, selectedPlayers: Set<User.ID>) -> Int64? {
		let allSelected = selectedPlayers == allPlayerIDs
		switch kind {
		case .matchLists:
			return matchListSizes
				.filter { selectedPlayers.contains($0.key) }
				.values
				.reduce(0, +)
		case .matchDetails:
			let targetIDs: Set<Match.ID>
			if allSelected {
				targetIDs = allCachedMatchDetailIDs
			} else {
				let referenced = matchIDsByPlayer
					.filter { selectedPlayers.contains($0.key) }
					.values
					.reduce(into: Set<Match.ID>()) { $0.formUnion($1) }
				targetIDs = referenced.intersection(allCachedMatchDetailIDs)
			}
			return targetIDs.reduce(0) { $0 + (matchDetailSizes[$1] ?? 0) }
		case .careerSummaries:
			return careerSizes
				.filter { selectedPlayers.contains($0.key) }
				.values
				.reduce(0, +)
		case .users:
			return userSizes
				.filter { allSelected || selectedPlayers.contains($0.key) }
				.values
				.reduce(0, +)
		case .playerIdentities:
			return identitySizes
				.filter { allSelected || selectedPlayers.contains($0.key) }
				.values
				.reduce(0, +)
		default:
			return nil
		}
	}
}

struct BackupExportOptions {
	var selectedModules: Set<BackupModuleKind>
	var selectedPlayerIDs: Set<User.ID>
	var allPlayersSelected: Bool
	var password: String?
}

struct BackupExportResult: Identifiable {
	let id = UUID()
	let fileURL: URL
	let byteCount: Int64
	let moduleCount: Int
	let totalItems: Int
	let playerCount: Int
	let fingerprint: String
	let isEncrypted: Bool
}

struct BackupImportOptions {
	var selectedModules: Set<BackupModuleKind>
	var selectedPlayerIDs: Set<User.ID>
	var allManifestPlayersSelected: Bool
	var mode: BackupImportMode
}

struct BackupImportSummary {
	let trustStatus: BackupTrustStatus
	let mode: BackupImportMode
	let importedCounts: [BackupModuleKind: Int]
	let skippedUnknownModules: [String]
	
	var totalImportedItems: Int {
		importedCounts.values.reduce(0, +)
	}
}

enum BackupService {
	private static let maxBackupFileBytes = 512 * 1024 * 1024
	
	private static var appVersionString: String {
		(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.0"
	}
	
	// MARK: - Store Readiness

	@MainActor
	private static func waitUntilStoresLoaded(_ stores: BackupStores) async {
		async let wishlist: Void = stores.wishlistManager.waitUntilLoaded()
		async let shop: Void = stores.shopHistoryStore.waitUntilLoaded()
		async let timeline: Void = stores.progressTimelineStore.waitUntilLoaded()
		async let presets: Void = stores.loadoutPresetManager.waitUntilLoaded()
		async let goals: Void = stores.seasonGoalStore.waitUntilLoaded()
		async let snapshots: Void = stores.playerSettingsSnapshotStore.waitUntilLoaded()
		async let lineups: Void = stores.lineupsManager.waitUntilLoaded()
		async let accolades: Void = AccoladesCacheStore.shared.waitUntilLoaded()
		async let groupPerf: Void = GroupPerformanceCacheStore.shared.waitUntilLoaded()
		_ = await (wishlist, shop, timeline, presets, goals, snapshots, lineups, accolades, groupPerf)
	}
	
	// MARK: - Inventory Discovery
	
	@MainActor
	static func buildInventory(stores: BackupStores) async -> BackupInventory {
		await waitUntilStoresLoaded(stores)
		let provider = LocalDataProvider.shared
		
		async let matchListSizesTask = provider.matchListManager.diskSizesByID()
		async let matchDetailSizesTask = provider.matchDetailsManager.diskSizesByID()
		async let careerSizesTask = provider.careerSummaryManager.diskSizesByID()
		async let userSizesTask = provider.userManager.diskSizesByID()
		async let identitySizesTask = provider.playerIdentityManager.diskSizesByID()
		async let usernameHistoryTask = stores.usernameHistoryStore.exportRecords(for: nil)
		async let socialTask = stores.socialManager.exportSocialData(for: nil)
		
		let matchListSizes = await matchListSizesTask
		let matchListIDs = Array(matchListSizes.keys)
		let matchLists = await provider.matchListManager.loadEntriesFromDiskOnly(for: matchListIDs)
		let matchDetailSizes = await matchDetailSizesTask
		let matchDetailIDs = Set(matchDetailSizes.keys)
		let careerSizes = await careerSizesTask
		let careerIDs = Set(careerSizes.keys)
		let userSizes = await userSizesTask
		let userIDs = Set(userSizes.keys)
		let identitySizes = await identitySizesTask
		let identityIDs = Set(identitySizes.keys)
		let usernameHistory = await usernameHistoryTask
		let social = await socialTask
		
		let ownAccounts = Set(stores.accountManager.storedAccounts)
		let bookmarkedIDs = Set(stores.bookmarkList.bookmarks.map(\.user))
		let lookupEntries = LookupHistory.exportEntries(for: nil)
		let lookupIDs = Set(lookupEntries.map(\.user))
		let shopDays = stores.shopHistoryStore.exportDays(for: nil)
		let goals = stores.seasonGoalStore.exportGoals(for: nil)
		let progressPoints = stores.progressTimelineStore.exportPoints(for: nil)
		let presets = stores.loadoutPresetManager.exportPresets(for: nil)
		let favoritesPresets = stores.loadoutPresetManager.exportFavoritesPresets(for: nil)
		let snapshots = stores.playerSettingsSnapshotStore.exportSnapshots(for: nil)
		
		var matchIDsByPlayer: [User.ID: Set<Match.ID>] = [:]
		for entry in matchLists {
			matchIDsByPlayer[entry.id] = Set(entry.object.matches.map(\.id))
		}
		
		var shopDayCounts: [User.ID: Int] = [:]
		for day in shopDays {
			shopDayCounts[day.accountID, default: 0] += 1
		}
		
		var progressPointCounts: [User.ID: Int] = [:]
		for point in progressPoints {
			progressPointCounts[point.accountID, default: 0] += 1
		}
		
		var socialFriendPlayers: Set<User.ID> = []
		for key in social.friends.keys {
			if let id = User.ID(key.lowercased()) {
				socialFriendPlayers.insert(id)
			}
		}
		
		var socialMessageCounts: [User.ID: Int] = [:]
		for (key, conversations) in social.messages {
			if let id = User.ID(key.lowercased()) {
				let msgCount = conversations.values.reduce(0) { $0 + $1.count }
				if msgCount > 0 {
					socialMessageCounts[id] = msgCount
				}
			}
		}
		
		var discoveredIDs = Set<User.ID>()
		discoveredIDs.formUnion(ownAccounts)
		discoveredIDs.formUnion(bookmarkedIDs)
		discoveredIDs.formUnion(lookupIDs)
		discoveredIDs.formUnion(matchIDsByPlayer.keys)
		discoveredIDs.formUnion(careerIDs)
		discoveredIDs.formUnion(usernameHistory.keys)
		discoveredIDs.formUnion(shopDayCounts.keys)
		discoveredIDs.formUnion(goals.compactMap(\.accountID))
		discoveredIDs.formUnion(progressPointCounts.keys)
		discoveredIDs.formUnion(presets.compactMap(\.accountID))
		discoveredIDs.formUnion(favoritesPresets.compactMap(\.accountID))
		discoveredIDs.formUnion(snapshots.compactMap(\.accountID))
		discoveredIDs.formUnion(socialFriendPlayers)
		discoveredIDs.formUnion(socialMessageCounts.keys)
		
		let targetUserIDs = discoveredIDs.intersection(userIDs)
		let userEntries = await provider.userManager.loadEntriesFromDiskOnly(for: targetUserIDs)
		let usersByID = Dictionary(userEntries.map { ($0.id, $0.object) }, uniquingKeysWith: { first, _ in first })
		
		var players: [BackupSelectablePlayer] = discoveredIDs.map { (id: User.ID) -> BackupSelectablePlayer in
			let role: BackupPlayerSummary.Role
			if ownAccounts.contains(id) {
				role = .account
			} else if bookmarkedIDs.contains(id) {
				role = .bookmark
			} else {
				role = .cached
			}

			let cachedUser: User? = usersByID[id]
			let latestName = usernameHistory[id]?.max { $0.lastSeen < $1.lastSeen }
			let cachedGameName: String? = cachedUser?.gameName
			let cachedTagLine: String? = cachedUser?.tagLine
			let gameName: String = (cachedGameName?.isEmpty == false ? cachedGameName : nil) ?? latestName?.gameName ?? ""
			let tagLine: String = (cachedTagLine?.isEmpty == false ? cachedTagLine : nil) ?? latestName?.tagLine ?? ""

			let playerMatches: Set<Match.ID> = matchIDsByPlayer[id] ?? []
			let cachedMatchesForPlayer: Set<Match.ID> = playerMatches.intersection(matchDetailIDs)
			let cachedMatchBytes: Int64 = cachedMatchesForPlayer.reduce(Int64(0)) { (sum: Int64, matchID: Match.ID) -> Int64 in
				sum + (matchDetailSizes[matchID] ?? 0)
			}
			let estBytes: Int64 = (matchListSizes[id] ?? 0)
				+ (careerSizes[id] ?? 0)
				+ (userSizes[id] ?? 0)
				+ (identitySizes[id] ?? 0)
				+ cachedMatchBytes
			
			return BackupSelectablePlayer(
				id: id,
				gameName: gameName,
				tagLine: tagLine,
				role: role,
				matchCount: playerMatches.count,
				estimatedBytes: estBytes
			)
		}
		
		players.sort { lhs, rhs in
			if lhs.role != rhs.role {
				return lhs.role < rhs.role
			}
			if lhs.matchCount != rhs.matchCount {
				return lhs.matchCount > rhs.matchCount
			}
			return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
		}
		
		return BackupInventory(
			players: players,
			matchIDsByPlayer: matchIDsByPlayer,
			matchListSizes: matchListSizes,
			allCachedMatchDetailIDs: matchDetailIDs,
			matchDetailSizes: matchDetailSizes,
			careerIDs: careerIDs,
			careerSizes: careerSizes,
			userIDs: userIDs,
			userSizes: userSizes,
			identityIDs: identityIDs,
			identitySizes: identitySizes,
			usernameHistoryPlayers: Set(usernameHistory.keys),
			bookmarkedUserIDs: bookmarkedIDs,
			lookupUserIDs: lookupIDs,
			shopDayCountsByPlayer: shopDayCounts,
			goalAccountIDs: goals.map(\.accountID),
			progressPointCountsByPlayer: progressPointCounts,
			presetAccountIDs: presets.map(\.accountID),
			favoritesPresetAccountIDs: favoritesPresets.map(\.accountID),
			snapshotAccountIDs: snapshots.map(\.accountID),
			socialFriendPlayers: socialFriendPlayers,
			socialMessageCountsByPlayer: socialMessageCounts,
			wishlistCount: stores.wishlistManager.entries.count,
			lineupsCount: stores.lineupsManager.favorites.count,
			allPlayerIDs: discoveredIDs
		)
	}
	
	// MARK: - Export
	
	@MainActor
	static func exportBackup(
		options: BackupExportOptions,
		inventory: BackupInventory,
		stores: BackupStores
	) async throws -> BackupExportResult {
		guard !options.selectedModules.isEmpty else {
			throw BackupError.emptySelection
		}
		await waitUntilStoresLoaded(stores)
		
		let provider = LocalDataProvider.shared
		let playerFilter: Set<User.ID>? = options.allPlayersSelected ? nil : options.selectedPlayerIDs
		let selectedSet = options.selectedPlayerIDs
		
		let needMatchLists = options.selectedModules.contains(.matchLists)
			|| (options.selectedModules.contains(.matchDetails) && !options.allPlayersSelected)
		let matchListIDsToLoad: [User.ID] = needMatchLists
			? (playerFilter.map { Array($0.intersection(Set(inventory.matchIDsByPlayer.keys))) }
				?? Array(inventory.matchIDsByPlayer.keys))
			: []
		let careerIDsToLoad: Set<User.ID> = options.selectedModules.contains(.careerSummaries)
			? (playerFilter.map { $0.intersection(inventory.careerIDs) } ?? inventory.careerIDs)
			: []
		
		// Gather independent disk/store reads concurrently
		async let matchListTask: [LocalDataManager<MatchList>.Entry] = needMatchLists
			? provider.matchListManager.loadEntriesFromDiskOnly(for: matchListIDsToLoad)
			: []
		async let careerTask: [LocalDataManager<CareerSummary>.Entry] = options.selectedModules.contains(.careerSummaries)
			? provider.careerSummaryManager.loadEntriesFromDiskOnly(for: careerIDsToLoad)
			: []
		async let usernameTask: [User.ID: [NameHistoryRecord]] = options.selectedModules.contains(.usernameHistory)
			? stores.usernameHistoryStore.exportRecords(for: playerFilter)
			: [:]
		async let socialTask: (friends: [String: SocialFriendsBackup], messages: [String: [String: [XMPPChatMessage]]]) = (options.selectedModules.contains(.socialFriends) || options.selectedModules.contains(.socialMessages))
			? stores.socialManager.exportSocialData(for: playerFilter)
			: (friends: [:], messages: [:])
		
		let matchListEntries = await matchListTask
		
		let matchDetailEntries: [LocalDataManager<MatchDetails>.Entry]
		if options.selectedModules.contains(.matchDetails) {
			let targetMatchIDs: Set<Match.ID>
			if options.allPlayersSelected {
				targetMatchIDs = inventory.allCachedMatchDetailIDs
			} else {
				targetMatchIDs = matchListEntries
					.reduce(into: Set<Match.ID>()) { $0.formUnion($1.object.matches.map(\.id)) }
					.intersection(inventory.allCachedMatchDetailIDs)
			}
			matchDetailEntries = await provider.matchDetailsManager.loadEntriesFromDiskOnly(for: targetMatchIDs)
		} else {
			matchDetailEntries = []
		}
		
		// Automatically bundle cached User records for incognito co-players in exported matches
		var incognitoParticipantIDs: Set<User.ID> = []
		if (options.selectedModules.contains(.users) || options.selectedModules.contains(.playerIdentities)),
		   playerFilter != nil {
			for entry in matchDetailEntries {
				for player in entry.object.players where player.gameName.isEmpty {
					incognitoParticipantIDs.insert(player.id)
				}
			}
		}
		
		let userIDsToLoad: Set<User.ID> = options.selectedModules.contains(.users)
			? (playerFilter.map { $0.union(incognitoParticipantIDs).intersection(inventory.userIDs) } ?? inventory.userIDs)
			: []
		let identityIDsToLoad: Set<User.ID> = options.selectedModules.contains(.playerIdentities)
			? (playerFilter.map { $0.union(incognitoParticipantIDs).intersection(inventory.identityIDs) } ?? inventory.identityIDs)
			: []
		
		async let userTask: [LocalDataManager<User>.Entry] = options.selectedModules.contains(.users)
			? provider.userManager.loadEntriesFromDiskOnly(for: userIDsToLoad)
			: []
		async let identityTask: [LocalDataManager<Player.Identity>.Entry] = options.selectedModules.contains(.playerIdentities)
			? provider.playerIdentityManager.loadEntriesFromDiskOnly(for: identityIDsToLoad)
			: []
		
		let careerEntries = await careerTask
		let userEntries = await userTask
		let identityEntries = await identityTask
		let usernameRecords = await usernameTask
		let socialExport = await socialTask
		
		let bookmarks = options.selectedModules.contains(.bookmarks)
			? stores.bookmarkList.exportBookmarks(for: playerFilter)
			: []
		
		let lookupHistory = options.selectedModules.contains(.lookupHistory)
			? LookupHistory.exportEntries(for: playerFilter)
			: []
		
		let shopHistory = options.selectedModules.contains(.shopHistory)
			? stores.shopHistoryStore.exportDays(for: playerFilter)
			: []
		
		let seasonGoals = options.selectedModules.contains(.seasonGoals)
			? stores.seasonGoalStore.exportGoals(for: playerFilter)
			: []
		
		let progressTimeline = options.selectedModules.contains(.progressTimeline)
			? stores.progressTimelineStore.exportPoints(for: playerFilter)
			: []
		
		let loadoutPresets = options.selectedModules.contains(.loadoutPresets)
			? stores.loadoutPresetManager.exportPresets(for: playerFilter)
			: []
		
		let favoritesPresets = options.selectedModules.contains(.favoritesPresets)
			? stores.loadoutPresetManager.exportFavoritesPresets(for: playerFilter)
			: []
		
		let settingsSnapshots = options.selectedModules.contains(.settingsSnapshots)
			? stores.playerSettingsSnapshotStore.exportSnapshots(for: playerFilter)
			: []
		
		let wishlistEntries = options.selectedModules.contains(.wishlist)
			? stores.wishlistManager.entries
			: []
		
		let lineupFavorites = options.selectedModules.contains(.lineupFavorites)
			? stores.lineupsManager.favorites
			: []
		
		let appSettingsSnapshot: AppSettings.BackupSnapshot? = options.selectedModules.contains(.appSettings)
			? stores.settings.exportSnapshot()
			: nil
		
		let playerSummaries = inventory.players
			.filter { options.allPlayersSelected || selectedSet.contains($0.id) }
			.map { $0.toSummary() }
		
		let appVersion = appVersionString
		let selectedModules = options.selectedModules
		let password = options.password
		let socialFriendsPayload = selectedModules.contains(.socialFriends) ? socialExport.friends : [:]
		let socialMessagesPayload = selectedModules.contains(.socialMessages) ? socialExport.messages : [:]
		let exportedMatchListEntries = selectedModules.contains(.matchLists) ? matchListEntries : []
		
		return try await Task.detached(priority: .userInitiated) {
			let encoder = BackupCoders.makeEncoder()
			var builder = try BackupContainer.StreamingBuilder(
				appVersion: appVersion,
				players: playerSummaries,
				password: password,
				expectedModuleCount: selectedModules.count
			)
			var moduleCount = 0
			var totalItems = 0
			
			func appendModule<T: Encodable>(_ kind: BackupModuleKind, value: T, itemCount: Int) throws {
				guard itemCount > 0 else { return }
				let json = try encoder.encode(value)
				try builder.addModule(
					kindID: kind.rawValue,
					schemaVersion: BackupModuleKind.currentSchemaVersion,
					itemCount: itemCount,
					rawJSON: json
				)
				moduleCount += 1
				totalItems += itemCount
			}
			
			if selectedModules.contains(.matchLists) {
				try appendModule(.matchLists, value: exportedMatchListEntries, itemCount: exportedMatchListEntries.count)
			}
			if selectedModules.contains(.matchDetails) {
				try appendModule(.matchDetails, value: matchDetailEntries, itemCount: matchDetailEntries.count)
			}
			if selectedModules.contains(.careerSummaries) {
				try appendModule(.careerSummaries, value: careerEntries, itemCount: careerEntries.count)
			}
			if selectedModules.contains(.users) {
				try appendModule(.users, value: userEntries, itemCount: userEntries.count)
			}
			if selectedModules.contains(.playerIdentities) {
				try appendModule(.playerIdentities, value: identityEntries, itemCount: identityEntries.count)
			}
			if selectedModules.contains(.usernameHistory) {
				try appendModule(.usernameHistory, value: usernameRecords, itemCount: usernameRecords.count)
			}
			if selectedModules.contains(.bookmarks) {
				try appendModule(.bookmarks, value: bookmarks, itemCount: bookmarks.count)
			}
			if selectedModules.contains(.lookupHistory) {
				try appendModule(.lookupHistory, value: lookupHistory, itemCount: lookupHistory.count)
			}
			if selectedModules.contains(.shopHistory) {
				try appendModule(.shopHistory, value: shopHistory, itemCount: shopHistory.count)
			}
			if selectedModules.contains(.seasonGoals) {
				try appendModule(.seasonGoals, value: seasonGoals, itemCount: seasonGoals.count)
			}
			if selectedModules.contains(.progressTimeline) {
				try appendModule(.progressTimeline, value: progressTimeline, itemCount: progressTimeline.count)
			}
			if selectedModules.contains(.loadoutPresets) {
				try appendModule(.loadoutPresets, value: loadoutPresets, itemCount: loadoutPresets.count)
			}
			if selectedModules.contains(.favoritesPresets) {
				try appendModule(.favoritesPresets, value: favoritesPresets, itemCount: favoritesPresets.count)
			}
			if selectedModules.contains(.settingsSnapshots) {
				try appendModule(.settingsSnapshots, value: settingsSnapshots, itemCount: settingsSnapshots.count)
			}
			if selectedModules.contains(.socialFriends) {
				try appendModule(.socialFriends, value: socialFriendsPayload, itemCount: socialFriendsPayload.count)
			}
			if selectedModules.contains(.socialMessages) {
				let msgCount = socialMessagesPayload.values.reduce(0) { acc, convs in
					acc + convs.values.reduce(0) { $0 + $1.count }
				}
				try appendModule(.socialMessages, value: socialMessagesPayload, itemCount: msgCount)
			}
			if selectedModules.contains(.wishlist) {
				try appendModule(.wishlist, value: wishlistEntries, itemCount: wishlistEntries.count)
			}
			if selectedModules.contains(.lineupFavorites) {
				try appendModule(.lineupFavorites, value: lineupFavorites, itemCount: lineupFavorites.count)
			}
			if let appSettingsSnapshot, selectedModules.contains(.appSettings) {
				try appendModule(.appSettings, value: appSettingsSnapshot, itemCount: 1)
			}
			
			guard moduleCount > 0 else {
				throw BackupError.emptySelection
			}
			
			let built = try builder.finalize()
			
			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.dateFormat = "yyyy-MM-dd-HHmm"
			let filename = "ReconBolt-Backup-\(formatter.string(from: built.manifest.createdAt)).rbbackup"
			let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
			try built.data.write(to: tempURL, options: .atomic)
			
			return BackupExportResult(
				fileURL: tempURL,
				byteCount: Int64(built.data.count),
				moduleCount: moduleCount,
				totalItems: totalItems,
				playerCount: playerSummaries.count,
				fingerprint: built.fingerprint,
				isEncrypted: password?.isEmpty == false
			)
		}.value
	}
	
	// MARK: - Inspection & Unlock
	
	static func inspectBackup(at url: URL) async throws -> VerifiedBackupArchive {
		let accessed = url.startAccessingSecurityScopedResource()
		defer {
			if accessed {
				url.stopAccessingSecurityScopedResource()
			}
		}
		
		let data = try await Task.detached(priority: .userInitiated) {
			let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
			if let fileSize = attrs?[.size] as? NSNumber, fileSize.int64Value > Int64(maxBackupFileBytes) {
				throw BackupError.invalidFormat("Backup file exceeds maximum supported size.")
			}
			let rawData = try Data(contentsOf: url, options: .mappedIfSafe)
			guard rawData.count <= maxBackupFileBytes else {
				throw BackupError.invalidFormat("Backup file exceeds maximum supported size.")
			}
			return rawData
		}.value
		
		return try await Task.detached(priority: .userInitiated) {
			try BackupContainer.inspectArchive(data)
		}.value
	}
	
	static func unlockBackup(
		_ archive: VerifiedBackupArchive,
		password: String
	) async throws -> SymmetricKey {
		try await Task.detached(priority: .userInitiated) {
			try BackupContainer.unlockEncryptionKey(for: archive, password: password)
		}.value
	}
	
	// MARK: - Import (2-Phase: Validate All -> Commit Atomically)
	
	private struct ValidatedImportPayload {
		var matchLists: [LocalDataManager<MatchList>.Entry]?
		var matchDetails: [LocalDataManager<MatchDetails>.Entry]?
		var careerSummaries: [LocalDataManager<CareerSummary>.Entry]?
		var users: [LocalDataManager<User>.Entry]?
		var playerIdentities: [LocalDataManager<Player.Identity>.Entry]?
		var usernameHistory: [User.ID: [NameHistoryRecord]]?
		var bookmarks: [BookmarkList.Entry]?
		var lookupHistory: [LookupHistory.Entry]?
		var shopHistory: [ShopHistoryDay]?
		var seasonGoals: [SeasonGoal]?
		var progressTimeline: [ProgressTimelinePoint]?
		var loadoutPresets: [LoadoutPreset]?
		var favoritesPresets: [FavoritesPreset]?
		var settingsSnapshots: [PlayerSettingsSnapshot]?
		var socialFriends: [String: SocialFriendsBackup]?
		var socialMessages: [String: [String: [XMPPChatMessage]]]?
		var wishlist: [WishlistEntry]?
		var lineupFavorites: [LineupGuide]?
		var appSettings: AppSettings.BackupSnapshot?
		var skippedUnknownModules: [String] = []
	}
	
	@MainActor
	static func importBackup(
		archive: VerifiedBackupArchive,
		encryptionKey: SymmetricKey?,
		options: BackupImportOptions,
		stores: BackupStores
	) async throws -> BackupImportSummary {
		guard !options.selectedModules.isEmpty else {
			throw BackupError.emptySelection
		}
		
		// Phase 1: Extract, decode, and strictly validate ALL selected modules off-MainActor before touching any store.
		let validated = try await Task.detached(priority: .userInitiated) {
			let decoder = BackupCoders.makeDecoder()
			var payload = ValidatedImportPayload()
			
			for descriptor in archive.manifest.modules {
				guard let kind = descriptor.knownKind else {
					payload.skippedUnknownModules.append(descriptor.id)
					continue
				}
				guard options.selectedModules.contains(kind) else { continue }
				
				let rawJSON = try BackupContainer.extractModuleJSON(
					descriptor: descriptor,
					from: archive,
					encryptionKey: encryptionKey
				)
				
				switch kind {
				case .matchLists:
					let entries = try decoder.decode([LocalDataManager<MatchList>.Entry].self, from: rawJSON)
					try BackupSemanticValidator.validateMatchLists(entries)
					payload.matchLists = entries
					
				case .matchDetails:
					let entries = try decoder.decode([LocalDataManager<MatchDetails>.Entry].self, from: rawJSON)
					try BackupSemanticValidator.validateMatchDetails(entries)
					payload.matchDetails = entries
					
				case .careerSummaries:
					let entries = try decoder.decode([LocalDataManager<CareerSummary>.Entry].self, from: rawJSON)
					try BackupSemanticValidator.validateCareerSummaries(entries)
					payload.careerSummaries = entries
					
				case .users:
					let entries = try decoder.decode([LocalDataManager<User>.Entry].self, from: rawJSON)
					try BackupSemanticValidator.validateUsers(entries)
					payload.users = entries
					
				case .playerIdentities:
					let entries = try decoder.decode([LocalDataManager<Player.Identity>.Entry].self, from: rawJSON)
					try BackupSemanticValidator.validatePlayerIdentities(entries)
					payload.playerIdentities = entries
					
				case .usernameHistory:
					let records = try decoder.decode([User.ID: [NameHistoryRecord]].self, from: rawJSON)
					try BackupSemanticValidator.validateUsernameHistory(records)
					payload.usernameHistory = records
					
				case .bookmarks:
					let entries = try decoder.decode([BookmarkList.Entry].self, from: rawJSON)
					try BackupSemanticValidator.validateBookmarks(entries)
					payload.bookmarks = entries
					
				case .lookupHistory:
					let entries = try decoder.decode([LookupHistory.Entry].self, from: rawJSON)
					try BackupSemanticValidator.validateLookupHistory(entries)
					payload.lookupHistory = entries
					
				case .shopHistory:
					let days = try decoder.decode([ShopHistoryDay].self, from: rawJSON)
					try BackupSemanticValidator.validateShopHistory(days)
					payload.shopHistory = days
					
				case .seasonGoals:
					let goals = try decoder.decode([SeasonGoal].self, from: rawJSON)
					try BackupSemanticValidator.validateSeasonGoals(goals)
					payload.seasonGoals = goals
					
				case .progressTimeline:
					let points = try decoder.decode([ProgressTimelinePoint].self, from: rawJSON)
					try BackupSemanticValidator.validateProgressTimeline(points)
					payload.progressTimeline = points
					
				case .loadoutPresets:
					let presets = try decoder.decode([LoadoutPreset].self, from: rawJSON)
					try BackupSemanticValidator.validateLoadoutPresets(presets)
					payload.loadoutPresets = presets
					
				case .favoritesPresets:
					let favorites = try decoder.decode([FavoritesPreset].self, from: rawJSON)
					try BackupSemanticValidator.validateFavoritesPresets(favorites)
					payload.favoritesPresets = favorites
					
				case .settingsSnapshots:
					let snapshots = try decoder.decode([PlayerSettingsSnapshot].self, from: rawJSON)
					try BackupSemanticValidator.validateSettingsSnapshots(snapshots)
					payload.settingsSnapshots = snapshots
					
				case .socialFriends:
					let friends = try decoder.decode([String: SocialFriendsBackup].self, from: rawJSON)
					try BackupSemanticValidator.validateSocialFriends(friends)
					payload.socialFriends = friends
					
				case .socialMessages:
					let messages = try decoder.decode([String: [String: [XMPPChatMessage]]].self, from: rawJSON)
					try BackupSemanticValidator.validateSocialMessages(messages)
					payload.socialMessages = messages
					
				case .wishlist:
					let entries = try decoder.decode([WishlistEntry].self, from: rawJSON)
					try BackupSemanticValidator.validateWishlist(entries)
					payload.wishlist = entries
					
				case .lineupFavorites:
					let guides = try decoder.decode([LineupGuide].self, from: rawJSON)
					try BackupSemanticValidator.validateLineupFavorites(guides)
					payload.lineupFavorites = guides
					
				case .appSettings:
					let settings = try decoder.decode(AppSettings.BackupSnapshot.self, from: rawJSON)
					try BackupSemanticValidator.validateAppSettings(settings)
					payload.appSettings = settings
				}
			}
			
			if !options.allManifestPlayersSelected {
				let selectedPlayers = options.selectedPlayerIDs
				let lowerSelectedKeys = Set(selectedPlayers.map { $0.description.lowercased() })
				
				if let lists = payload.matchLists {
					payload.matchLists = lists.filter { selectedPlayers.contains($0.id) }
				}
				
				let linkedMatchIDs = (payload.matchLists ?? [])
					.reduce(into: Set<Match.ID>()) { $0.formUnion($1.object.matches.map(\.id)) }
				
				if let details = payload.matchDetails {
					payload.matchDetails = details.filter { entry in
						if linkedMatchIDs.contains(entry.id) { return true }
						return entry.object.players.contains { selectedPlayers.contains($0.id) }
					}
				}
				
				var matchParticipantIDs: Set<User.ID> = []
				for entry in payload.matchDetails ?? [] {
					for player in entry.object.players {
						matchParticipantIDs.insert(player.id)
					}
				}
				let userAndIdentityAllowed = selectedPlayers.union(matchParticipantIDs)
				
				if let careers = payload.careerSummaries {
					payload.careerSummaries = careers.filter { selectedPlayers.contains($0.id) }
				}
				if let users = payload.users {
					payload.users = users.filter { userAndIdentityAllowed.contains($0.id) }
				}
				if let identities = payload.playerIdentities {
					payload.playerIdentities = identities.filter { userAndIdentityAllowed.contains($0.id) }
				}
				if let usernames = payload.usernameHistory {
					payload.usernameHistory = usernames.filter { selectedPlayers.contains($0.key) }
				}
				if let bookmarks = payload.bookmarks {
					payload.bookmarks = bookmarks.filter { selectedPlayers.contains($0.user) }
				}
				if let lookups = payload.lookupHistory {
					payload.lookupHistory = lookups.filter { selectedPlayers.contains($0.user) }
				}
				if let shop = payload.shopHistory {
					payload.shopHistory = shop.filter { selectedPlayers.contains($0.accountID) }
				}
				if let goals = payload.seasonGoals {
					payload.seasonGoals = goals.filter { goal in
						guard let id = goal.accountID else { return !selectedPlayers.isEmpty }
						return selectedPlayers.contains(id)
					}
				}
				if let progress = payload.progressTimeline {
					payload.progressTimeline = progress.filter { selectedPlayers.contains($0.accountID) }
				}
				if let presets = payload.loadoutPresets {
					payload.loadoutPresets = presets.filter { preset in
						guard let id = preset.accountID else { return !selectedPlayers.isEmpty }
						return selectedPlayers.contains(id)
					}
				}
				if let favPresets = payload.favoritesPresets {
					payload.favoritesPresets = favPresets.filter { preset in
						guard let id = preset.accountID else { return !selectedPlayers.isEmpty }
						return selectedPlayers.contains(id)
					}
				}
				if let snapshots = payload.settingsSnapshots {
					payload.settingsSnapshots = snapshots.filter { snapshot in
						guard let id = snapshot.accountID else { return !selectedPlayers.isEmpty }
						return selectedPlayers.contains(id)
					}
				}
				if let friends = payload.socialFriends {
					payload.socialFriends = friends.filter { lowerSelectedKeys.contains($0.key.lowercased()) }
				}
				if let messages = payload.socialMessages {
					payload.socialMessages = messages.filter { lowerSelectedKeys.contains($0.key.lowercased()) }
				}
			}
			
			return payload
		}.value
		
		// Phase 2: Commit validated data into stores.
		await waitUntilStoresLoaded(stores)
		let replaceAll = (options.mode == .replace)
		let provider = LocalDataProvider.shared
		var counts: [BackupModuleKind: Int] = [:]
		
		if let matchLists = validated.matchLists {
			counts[.matchLists] = try await provider.matchListManager.importMatchLists(matchLists, replaceAll: replaceAll)
		}
		if let matchDetails = validated.matchDetails {
			counts[.matchDetails] = try await provider.matchDetailsManager.importEntries(matchDetails, replaceAll: replaceAll)
		}
		if let careers = validated.careerSummaries {
			counts[.careerSummaries] = try await provider.careerSummaryManager.importEntries(careers, replaceAll: replaceAll)
		}
		if let users = validated.users {
			counts[.users] = try await provider.userManager.importEntries(users, replaceAll: replaceAll)
		}
		let derivedIdentities: [LocalDataManager<Player.Identity>.Entry]
		if let matchDetails = validated.matchDetails, !matchDetails.isEmpty {
			derivedIdentities = matchDetails.flatMap { entry in
				entry.object.players.map {
					LocalDataManager<Player.Identity>.Entry(
						lastUpdate: entry.object.matchInfo.gameStart,
						object: $0.identity
					)
				}
			}
		} else {
			derivedIdentities = []
		}
		if validated.playerIdentities != nil || !derivedIdentities.isEmpty {
			var mergedByID: [User.ID: LocalDataManager<Player.Identity>.Entry] = Dictionary(
				minimumCapacity: (validated.playerIdentities?.count ?? 0) + derivedIdentities.count
			)
			for entry in derivedIdentities {
				if let existing = mergedByID[entry.id], existing.lastUpdate >= entry.lastUpdate {
					continue
				}
				mergedByID[entry.id] = entry
			}
			for entry in validated.playerIdentities ?? [] {
				if let existing = mergedByID[entry.id], existing.lastUpdate > entry.lastUpdate {
					continue
				}
				mergedByID[entry.id] = entry
			}
			let importedCount = try await provider.playerIdentityManager.importEntries(
				Array(mergedByID.values),
				replaceAll: replaceAll && validated.playerIdentities != nil
			)
			if let identities = validated.playerIdentities {
				counts[.playerIdentities] = min(importedCount, identities.count)
			}
		}
		if let usernames = validated.usernameHistory {
			counts[.usernameHistory] = await stores.usernameHistoryStore.importRecords(usernames, replaceAll: replaceAll)
		}
		if let bookmarks = validated.bookmarks {
			counts[.bookmarks] = stores.bookmarkList.importBookmarks(bookmarks, replaceAll: replaceAll)
		}
		if let lookups = validated.lookupHistory {
			counts[.lookupHistory] = LookupHistory.importEntries(lookups, replaceAll: replaceAll)
		}
		if let shop = validated.shopHistory {
			counts[.shopHistory] = await stores.shopHistoryStore.importDays(shop, replaceAll: replaceAll)
		}
		if let goals = validated.seasonGoals {
			counts[.seasonGoals] = await stores.seasonGoalStore.importGoals(goals, replaceAll: replaceAll)
		}
		if let progress = validated.progressTimeline {
			counts[.progressTimeline] = await stores.progressTimelineStore.importPoints(progress, replaceAll: replaceAll)
		}
		if let presets = validated.loadoutPresets {
			counts[.loadoutPresets] = await stores.loadoutPresetManager.importPresets(presets, replaceAll: replaceAll)
		}
		if let favPresets = validated.favoritesPresets {
			counts[.favoritesPresets] = await stores.loadoutPresetManager.importFavoritesPresets(favPresets, replaceAll: replaceAll)
		}
		if let snapshots = validated.settingsSnapshots {
			counts[.settingsSnapshots] = await stores.playerSettingsSnapshotStore.importSnapshots(snapshots, replaceAll: replaceAll)
		}
		if let friends = validated.socialFriends {
			counts[.socialFriends] = await stores.socialManager.importSocialFriends(friends, replaceAll: replaceAll)
		}
		if let messages = validated.socialMessages {
			counts[.socialMessages] = await stores.socialManager.importSocialMessages(messages, replaceAll: replaceAll)
		}
		if let wishlist = validated.wishlist {
			counts[.wishlist] = await stores.wishlistManager.importEntries(wishlist, replaceAll: replaceAll)
		}
		if let lineups = validated.lineupFavorites {
			counts[.lineupFavorites] = await stores.lineupsManager.importFavorites(lineups, replaceAll: replaceAll)
		}
		if let appSettings = validated.appSettings {
			stores.settings.applySnapshot(appSettings)
			counts[.appSettings] = 1
		}
		
		// Recalculate derived accolades & group performance caches from validated MatchDetails
		if let matchDetails = validated.matchDetails {
			if replaceAll {
				AccoladesCacheStore.shared.clearAll()
				GroupPerformanceCacheStore.shared.clearAll()
			} else if !matchDetails.isEmpty {
				let importedIDs = matchDetails.map(\.id)
				AccoladesCacheStore.shared.remove(matchIDs: importedIDs)
				GroupPerformanceCacheStore.shared.remove(matchIDs: importedIDs)
			}
			var affectedUsers = Set((validated.matchLists ?? []).map(\.id))
			if !options.allManifestPlayersSelected {
				affectedUsers.formUnion(options.selectedPlayerIDs)
			} else {
				affectedUsers.formUnion(stores.accountManager.storedAccounts)
				affectedUsers.formUnion(stores.bookmarkList.bookmarks.map(\.user))
			}
			await AccoladesCacheStore.shared.refreshForImportedUsers(affectedUsers)
			await GroupPerformanceCacheStore.shared.refreshForImportedUsers(affectedUsers)
		} else if validated.matchLists != nil {
			var affectedUsers = Set((validated.matchLists ?? []).map(\.id))
			if options.allManifestPlayersSelected {
				affectedUsers.formUnion(stores.accountManager.storedAccounts)
				affectedUsers.formUnion(stores.bookmarkList.bookmarks.map(\.user))
			}
			await AccoladesCacheStore.shared.refreshForImportedUsers(affectedUsers)
			await GroupPerformanceCacheStore.shared.refreshForImportedUsers(affectedUsers)
		}
		
		return BackupImportSummary(
			trustStatus: archive.trustStatus,
			mode: options.mode,
			importedCounts: counts,
			skippedUnknownModules: validated.skippedUnknownModules
		)
	}
}
