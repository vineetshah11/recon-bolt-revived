import Foundation
import ValorantAPI

enum LineupSide: String, CaseIterable, Identifiable {
	case all = ""
	case attack
	case defense
	
	var id: String { rawValue }
	
	var displayName: String {
		switch self {
		case .all: return "All Sides"
		case .attack: return "Attack"
		case .defense: return "Defense"
		}
	}
}

enum LineupSort: String, CaseIterable, Identifiable {
	case top = "score"
	case trending = "trending"
	case views = "views"
	
	var id: String { rawValue }
	
	var displayName: String {
		switch self {
		case .top: return "Top Rated"
		case .trending: return "Trending"
		case .views: return "Most Viewed"
		}
	}
}

struct LineupGuide: Identifiable, Codable, Equatable {
	var id: String
	var title: String
	var titleSlug: String?
	var urlSlug: String?
	var videoUrl: String?
	var cloudflareSubdomain: String?
	var previewImageUrl: String?
	var score: Int?
	var views: Int?
	var viewsDisplay: String?
	var dateCreated: String?
	var creator: Creator?
	var attributes: Attributes?
	
	struct Creator: Codable, Equatable {
		var platformUserHandle: String?
		var avatarUrl: String?
	}
	
	struct Attributes: Codable, Equatable {
		var agent: String?
		var ability: String?
		var side: String?
		var location: String?
		var map: String?
	}
	
	var hlsStreamURL: URL? {
		guard let videoUrl, !videoUrl.isEmpty else { return nil }
		if videoUrl.hasSuffix(".m3u8"), let direct = URL(string: videoUrl) {
			return direct
		}
		if let url = URL(string: videoUrl), let host = url.host, host.contains("cloudflarestream.com") {
			let m3u8String = videoUrl
				.replacingOccurrences(of: "/manifest/video.mpd", with: "/manifest/video.m3u8")
				.replacingOccurrences(of: "/watch", with: "/manifest/video.m3u8")
			if let resolved = URL(string: m3u8String) {
				return resolved
			}
		}
		let videoID = videoUrl
			.replacingOccurrences(of: "/manifest/video.mpd", with: "")
			.split(separator: "/")
			.last
			.map(String.init) ?? videoUrl
		let host = (cloudflareSubdomain?.isEmpty == false)
			? cloudflareSubdomain!
			: "customer-9h7e8ahl6hivmjb6.cloudflarestream.com"
		return URL(string: "https://\(host)/\(videoID)/manifest/video.m3u8")
	}
	
	var trackerURL: URL {
		if let urlSlug, !urlSlug.isEmpty, let url = URL(string: "https://tracker.gg\(urlSlug)") {
			return url
		}
		return URL(string: "https://tracker.gg/valorant/guides/clips")!
	}
	
	private enum CodingKeys: String, CodingKey {
		case id
		case title
		case titleSlug
		case urlSlug
		case videoUrl
		case cloudflareSubdomain
		case previewImageUrl
		case score
		case views
		case viewsDisplay
		case dateCreated
		case creator
		case attributes
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if let str = try? container.decode(String.self, forKey: .id) {
			id = str
		} else if let intID = try? container.decode(Int.self, forKey: .id) {
			id = String(intID)
		} else {
			id = UUID().uuidString
		}
		title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Line-Up"
		titleSlug = try container.decodeIfPresent(String.self, forKey: .titleSlug)
		urlSlug = try container.decodeIfPresent(String.self, forKey: .urlSlug)
		videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)
		cloudflareSubdomain = try container.decodeIfPresent(String.self, forKey: .cloudflareSubdomain)
		previewImageUrl = try container.decodeIfPresent(String.self, forKey: .previewImageUrl)
		score = try container.decodeIfPresent(Int.self, forKey: .score)
		views = try container.decodeIfPresent(Int.self, forKey: .views)
		viewsDisplay = try container.decodeIfPresent(String.self, forKey: .viewsDisplay)
		dateCreated = try container.decodeIfPresent(String.self, forKey: .dateCreated)
		creator = try container.decodeIfPresent(Creator.self, forKey: .creator)
		attributes = try container.decodeIfPresent(Attributes.self, forKey: .attributes)
	}
}

@MainActor
final class LineupsManager: ObservableObject {
	@Published var guides: [LineupGuide] = []
	@Published var favorites: [LineupGuide] = []
	@Published var isLoading = false
	@Published var errorMessage: String?
	
	private let favoritesFilename = "LineupFavorites.v1.json"
	
	init() {
		favorites = LocalJSONStore.load([LineupGuide].self, from: favoritesFilename) ?? []
	}
	
	func isFavorite(_ guide: LineupGuide) -> Bool {
		favorites.contains { $0.id == guide.id }
	}
	
	func toggleFavorite(_ guide: LineupGuide) {
		if isFavorite(guide) {
			favorites.removeAll { $0.id == guide.id }
		} else {
			favorites.insert(guide, at: 0)
		}
		LocalJSONStore.save(favorites, to: favoritesFilename)
	}
	
	func fetchGuides(
		mapKey: String?,
		agentKey: String?,
		side: LineupSide,
		sort: LineupSort
	) async {
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }
		
		var components = URLComponents(string: "https://api.tracker.gg/api/v1/valorant/guides")!
		var items: [URLQueryItem] = [.init(name: "sort", value: sort.rawValue)]
		if let mapKey, !mapKey.isEmpty {
			items.append(.init(name: "map", value: mapKey.lowercased()))
		}
		if let agentKey, !agentKey.isEmpty {
			items.append(.init(name: "agent", value: agentKey.lowercased()))
		}
		if side != .all {
			items.append(.init(name: "side", value: side.rawValue))
		}
		components.queryItems = items
		
		var request = URLRequest(url: components.url!)
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("https://tracker.gg", forHTTPHeaderField: "Referer")
		
		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			if let http = response as? HTTPURLResponse {
				if http.statusCode == 403 {
					errorMessage = "Tracker.gg temporarily blocked the automated request (Cloudflare 403). You can still browse line-ups in Safari."
					return
				}
				if !(200..<300).contains(http.statusCode) {
					errorMessage = "Tracker.gg returned HTTP \(http.statusCode)."
					return
				}
			}
			let decoded = try JSONDecoder().decode(TrackerGuidesResponse.self, from: data)
			guides = decoded.resolvedGuides
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}

private struct TrackerGuidesResponse: Decodable {
	var data: DataWrapper?
	
	var resolvedGuides: [LineupGuide] {
		data?.guides ?? data?.items ?? []
	}
	
	struct DataWrapper: Decodable {
		var guides: [LineupGuide]?
		var items: [LineupGuide]?
		
		init(from decoder: Decoder) throws {
			if let array = try? [LineupGuide](from: decoder) {
				self.guides = array
				self.items = nil
				return
			}
			let container = try decoder.container(keyedBy: CodingKeys.self)
			guides = try container.decodeIfPresent([LineupGuide].self, forKey: .guides)
			items = try container.decodeIfPresent([LineupGuide].self, forKey: .items)
		}
		
		private enum CodingKeys: String, CodingKey {
			case guides
			case items
		}
	}
}
