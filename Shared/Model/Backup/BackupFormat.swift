import Foundation
import UniformTypeIdentifiers
import ValorantAPI

extension UTType {
	static let reconBoltBackup = UTType(exportedAs: "com.dtl21.recon-bolt.backup", conformingTo: .data)
}

enum BackupModuleGroup: String, CaseIterable, Identifiable, Sendable {
	case matches
	case profiles
	case accountData
	case social
	case appData
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .matches: return "Matches"
		case .profiles: return "Player Profiles"
		case .accountData: return "Account & Bookmarks"
		case .social: return "Social"
		case .appData: return "App & Preferences"
		}
	}
}

enum BackupModuleKind: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
	case matchLists = "matches.lists"
	case matchDetails = "matches.details"
	case careerSummaries = "players.career"
	case users = "players.users"
	case playerIdentities = "players.identities"
	case usernameHistory = "players.usernames"
	case bookmarks = "bookmarks"
	case lookupHistory = "lookupHistory"
	case shopHistory = "account.shopHistory"
	case seasonGoals = "account.seasonGoals"
	case progressTimeline = "account.progressTimeline"
	case loadoutPresets = "account.loadoutPresets"
	case favoritesPresets = "account.favoritesPresets"
	case settingsSnapshots = "account.settingsSnapshots"
	case socialFriends = "social.friends"
	case socialMessages = "social.messages"
	case wishlist = "global.wishlist"
	case lineupFavorites = "global.lineups"
	case appSettings = "global.appSettings"
	
	var id: String { rawValue }
	
	static let currentSchemaVersion = 1
	
	static var defaultExportSelection: Set<BackupModuleKind> {
		Set(allCases).subtracting([.socialMessages])
	}
	
	static var essentialSelection: Set<BackupModuleKind> {
		Set(allCases).subtracting([.socialMessages, .appSettings])
	}
	
	var group: BackupModuleGroup {
		switch self {
		case .matchLists, .matchDetails:
			return .matches
		case .careerSummaries, .users, .playerIdentities, .usernameHistory:
			return .profiles
		case .bookmarks, .lookupHistory, .shopHistory, .seasonGoals, .progressTimeline, .loadoutPresets, .favoritesPresets, .settingsSnapshots:
			return .accountData
		case .socialFriends, .socialMessages:
			return .social
		case .wishlist, .lineupFavorites, .appSettings:
			return .appData
		}
	}
	
	var displayName: String {
		switch self {
		case .matchLists: return "Match History Lists"
		case .matchDetails: return "Full Match Details"
		case .careerSummaries: return "Career & Rank Summaries"
		case .users: return "Player Names & Tags"
		case .playerIdentities: return "Cards, Titles & Levels"
		case .usernameHistory: return "Username History"
		case .bookmarks: return "Bookmarked Players"
		case .lookupHistory: return "Recent Player Searches"
		case .shopHistory: return "Daily Shop & Night Market History"
		case .seasonGoals: return "Season Rank Goals"
		case .progressTimeline: return "Progress Timelines"
		case .loadoutPresets: return "Loadout Presets"
		case .favoritesPresets: return "Favorites Presets"
		case .settingsSnapshots: return "Player Settings Snapshots"
		case .socialFriends: return "Friends List & Activity"
		case .socialMessages: return "Chat Messages"
		case .wishlist: return "Skin Wishlist"
		case .lineupFavorites: return "Favorite Line-Ups"
		case .appSettings: return "App Settings & Theme"
		}
	}
	
	var subtitle: String {
		switch self {
		case .matchLists: return "Competitive updates, RR changes, and match index per player"
		case .matchDetails: return "Scoreboards, rounds, economy, kills, and player stats"
		case .careerSummaries: return "Seasonal ranks, act badges, and win counts"
		case .users: return "Game names and taglines (includes incognito co-players in exported matches)"
		case .playerIdentities: return "Player cards, titles, and account levels"
		case .usernameHistory: return "Tracked Riot ID name changes over time"
		case .bookmarks: return "Saved player bookmarks and regions"
		case .lookupHistory: return "Recent career search history"
		case .shopHistory: return "Recorded daily store and Night Market offers"
		case .seasonGoals: return "Target ranks and climb baselines"
		case .progressTimeline: return "Account level, leaderboard rank, and wallet history over time"
		case .loadoutPresets: return "Saved weapon skin and expression loadouts"
		case .favoritesPresets: return "Saved in-game VALORANT favorites collections"
		case .settingsSnapshots: return "Backed-up in-game Valorant settings"
		case .socialFriends: return "Cached friends, cards, and friend list events"
		case .socialMessages: return "Private XMPP chat history (unchecked by default)"
		case .wishlist: return "Wishlisted weapon skins"
		case .lineupFavorites: return "Saved Tricks.gg line-up guides"
		case .appSettings: return "Theme, custom accent color, interface, and auto-delete rules"
		}
	}
	
	var icon: String {
		switch self {
		case .matchLists: return "list.bullet.rectangle"
		case .matchDetails: return "sportscourt"
		case .careerSummaries: return "chart.bar"
		case .users: return "person.text.rectangle"
		case .playerIdentities: return "person.crop.square"
		case .usernameHistory: return "clock.arrow.circlepath"
		case .bookmarks: return "bookmark"
		case .lookupHistory: return "magnifyingglass"
		case .shopHistory: return "bag"
		case .seasonGoals: return "flag"
		case .progressTimeline: return "chart.xyaxis.line"
		case .loadoutPresets: return "square.3.layers.3d"
		case .favoritesPresets: return "star.square.on.square"
		case .settingsSnapshots: return "slider.horizontal.below.rectangle"
		case .socialFriends: return "person.2"
		case .socialMessages: return "bubble.left.and.bubble.right"
		case .wishlist: return "heart"
		case .lineupFavorites: return "map"
		case .appSettings: return "gearshape"
		}
	}
	
	var isPlayerScoped: Bool {
		switch self {
		case .wishlist, .lineupFavorites, .appSettings:
			return false
		default:
			return true
		}
	}
	
	var isSensitivePrivate: Bool {
		self == .socialMessages
	}
}

struct BackupEncryptionMetadata: Codable, Equatable, Sendable {
	var algorithm: String
	var kdf: String
	var iterations: Int
	var saltBase64: String
}

struct BackupPlayerSummary: Codable, Identifiable, Equatable, Hashable {
	enum Role: String, Codable, Comparable, Sendable {
		case account
		case bookmark
		case cached
		
		private var sortRank: Int {
			switch self {
			case .account: return 0
			case .bookmark: return 1
			case .cached: return 2
			}
		}
		
		var sectionTitle: String {
			switch self {
			case .account: return "My Accounts"
			case .bookmark: return "Bookmarked Players"
			case .cached: return "Other Cached Players"
			}
		}
		
		var icon: String {
			switch self {
			case .account: return "person.crop.circle"
			case .bookmark: return "bookmark"
			case .cached: return "person.2"
			}
		}
		
		static func < (lhs: Role, rhs: Role) -> Bool {
			lhs.sortRank < rhs.sortRank
		}
	}
	
	var id: User.ID
	var gameName: String
	var tagLine: String
	var role: Role
	var matchCount: Int
	
	var displayName: String {
		if !gameName.isEmpty {
			return tagLine.isEmpty ? gameName : "\(gameName) #\(tagLine)"
		}
		return String(id.description.prefix(8)) + "…"
	}
}

struct BackupModuleDescriptor: Codable, Equatable, Identifiable, Sendable {
	var id: String
	var schemaVersion: Int
	var compression: String
	var itemCount: Int
	var uncompressedBytes: Int
	var wireBytes: Int
	var wireSHA256: String
	var plaintextSHA256: String
	
	var knownKind: BackupModuleKind? {
		BackupModuleKind(rawValue: id)
	}
}

struct BackupManifest: Codable, Equatable {
	var formatVersion: Int
	var exportID: UUID
	var createdAt: Date
	var appVersion: String
	var encryption: BackupEncryptionMetadata?
	var players: [BackupPlayerSummary]
	var modules: [BackupModuleDescriptor]
}

struct BackupIntegrityBlock: Codable, Equatable, Sendable {
	var hmacAlgorithm: String
	var appHMACBase64: String
	var signatureAlgorithm: String
	var signerPublicKeyBase64: String
	var signerFingerprint: String
	var deviceSignatureBase64: String
	var passwordHMACBase64: String?
}

enum BackupImportMode: String, CaseIterable, Identifiable, Sendable {
	case merge
	case replace
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .merge: return "Merge with Existing"
		case .replace: return "Replace Selected"
		}
	}
	
	var subtitle: String {
		switch self {
		case .merge: return "Keeps existing local data and adds or updates newer entries from the backup."
		case .replace: return "Clears each selected category before restoring data from the backup."
		}
	}
}

enum BackupTrustStatus: Equatable, Sendable {
	case verifiedThisDevice(fingerprint: String)
	case verifiedOtherDevice(fingerprint: String)
	
	var fingerprint: String {
		switch self {
		case .verifiedThisDevice(let fp), .verifiedOtherDevice(let fp):
			return fp
		}
	}
	
	var isThisDevice: Bool {
		if case .verifiedThisDevice = self { return true }
		return false
	}
}

enum BackupError: Error, LocalizedError {
	case emptySelection
	case invalidFormat(String)
	case unsupportedVersion(Int)
	case integrityViolation(String)
	case passwordRequired
	case wrongPassword
	case decryptionFailed
	case decompressionFailed(String)
	case semanticValidationFailed(String)
	case cryptoFailure(String)
	
	var errorDescription: String? {
		switch self {
		case .emptySelection:
			return "Select at least one category with data to continue."
		case .invalidFormat(let reason):
			return "Invalid backup file: \(reason)"
		case .unsupportedVersion(let version):
			return "Backup format version \(version) is not supported by this version of Recon Bolt."
		case .integrityViolation(let reason):
			return "Integrity verification failed — this backup has been modified or corrupted (\(reason)). Import has been blocked."
		case .passwordRequired:
			return "This backup is password-encrypted. Enter the password to unlock it."
		case .wrongPassword:
			return "Incorrect password. Unable to verify and decrypt this backup."
		case .decryptionFailed:
			return "Decryption failed — the encrypted payload may have been tampered with."
		case .decompressionFailed(let reason):
			return "Could not decompress backup payload: \(reason)"
		case .semanticValidationFailed(let reason):
			return "Backup data failed validation checks and was rejected: \(reason)"
		case .cryptoFailure(let reason):
			return "Cryptographic operation failed: \(reason)"
		}
	}
}

enum BackupCoders {
	static func makeEncoder() -> JSONEncoder {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
		encoder.dateEncodingStrategy = .millisecondsSince1970
		return encoder
	}
	
	static func makeDecoder() -> JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .millisecondsSince1970
		return decoder
	}
}
