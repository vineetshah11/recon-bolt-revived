import Foundation
import Combine

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
	
	/// the API spells its sides out with a leading capital
	var queryValue: String? {
		switch self {
		case .all: return nil
		case .attack: return "Attack"
		case .defense: return "Defense"
		}
	}
}

enum LineupSort: String, CaseIterable, Identifiable {
	case top
	case trending
	case views
	
	var id: String { rawValue }
	
	var displayName: String {
		switch self {
		case .top: return "Top Rated"
		case .trending: return "Newest"
		case .views: return "Most Viewed"
		}
	}
}

/// A line-up from tricks.gg, which is the only line-up source we've found that serves
/// an open JSON API instead of hiding behind Cloudflare (as Tracker.gg does).
struct LineupGuide: Identifiable, Codable, Equatable {
	var id: String
	var title: String
	var map: String?
	var agent: String?
	var ability: String?
	var side: String?
	var difficulty: String?
	var videoURL: URL?
		var imageURL: URL?
	var views: Int?

	var votes: Int?
	var createdAt: Date?
	
	static let siteURL = URL(string: "https://tricks.gg/lineups")!
	
	/// Most line-ups link to YouTube, which AVPlayer can't play directly, so those are
	/// handed to the embed player instead.
	var youtubeVideoID: String? {
		guard let url = videoURL, let host = url.host?.lowercased() else { return nil }
		let components = url.pathComponents.filter { $0 != "/" }
		
		if host.hasSuffix("youtu.be") {
			return components.first.flatMap(Self.validVideoID)
		}
		guard host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") else { return nil }
		if components.count >= 2, ["embed", "shorts", "live", "v"].contains(components[0]) {
			return Self.validVideoID(components[1])
		}
		return URLComponents(url: url, resolvingAgainstBaseURL: false)?
			.queryItems?.first { $0.name == "v" }?.value
			.flatMap(Self.validVideoID)
	}
	
	/// YouTube line-ups only ship a video link, so fall back to YouTube's own thumbnail.
	var thumbnailURL: URL? {
		if let imageURL { return imageURL }
		guard let id = youtubeVideoID else { return nil }
		return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
	}
	
	private static func validVideoID(_ raw: String) -> String? {
		let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
		guard !raw.isEmpty, raw.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
		return raw
	}
	
	private enum CodingKeys: String, CodingKey {
		case id
		case title
		case map
		case agent
		case ability
		case side
		case difficulty
		case videoUrl
		case imageUrl
		case views
		case voteCount
		case createdAt
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(String.self, forKey: .id)
		title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Line-Up"
		map = try container.decodeIfPresent(String.self, forKey: .map)
		agent = try container.decodeIfPresent(String.self, forKey: .agent)
		ability = try container.decodeIfPresent(String.self, forKey: .ability)
		side = try container.decodeIfPresent(String.self, forKey: .side)
		difficulty = try container.decodeIfPresent(String.self, forKey: .difficulty)
		videoURL = try container.decodeIfPresent(String.self, forKey: .videoUrl)
			.flatMap(Self.absoluteURL)
		imageURL = try container.decodeIfPresent(String.self, forKey: .imageUrl)
			.flatMap(Self.absoluteURL)
		views = try container.decodeIfPresent(Int.self, forKey: .views)
		votes = try container.decodeIfPresent(Int.self, forKey: .voteCount)
		createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
			.flatMap(Self.date(from:))
	}
	
	/// favorites are persisted in this same shape, so keep dates and URLs as strings
	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(id, forKey: .id)
		try container.encode(title, forKey: .title)
		try container.encodeIfPresent(map, forKey: .map)
		try container.encodeIfPresent(agent, forKey: .agent)
		try container.encodeIfPresent(ability, forKey: .ability)
		try container.encodeIfPresent(side, forKey: .side)
		try container.encodeIfPresent(difficulty, forKey: .difficulty)
		try container.encodeIfPresent(videoURL?.absoluteString, forKey: .videoUrl)
		try container.encodeIfPresent(imageURL?.absoluteString, forKey: .imageUrl)
		try container.encodeIfPresent(views, forKey: .views)
		try container.encodeIfPresent(votes, forKey: .voteCount)
		try container.encodeIfPresent(createdAt.map(Self.isoFormatter.string(from:)), forKey: .createdAt)
	}
	
	/// media paths come back relative to the site
	private static func absoluteURL(_ string: String) -> URL? {
		guard !string.isEmpty else { return nil }
		guard !string.hasPrefix("http") else { return URL(string: string) }
		guard let base = URL(string: "https://tricks.gg") else { return nil }
		return URL(string: string, relativeTo: base)?.absoluteURL
	}
	
	private static let isoFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()
	
	private static let isoFormatterWithoutFraction: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter
	}()
	
	private static func date(from string: String) -> Date? {
		isoFormatter.date(from: string) ?? isoFormatterWithoutFraction.date(from: string)
	}
}

@MainActor
final class LineupsManager: ObservableObject {
	@Published var guides: [LineupGuide] = []
	@Published var favorites: [LineupGuide] = []
	@Published var isLoading = false
	@Published var errorMessage: String?
	
	private let favoritesFilename = "LineupFavorites.v1.json"
	private let endpoint = URL(string: "https://tricks.gg/api/lineups")!
	
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
		
		var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
		var queryItems: [URLQueryItem] = []
		if let mapKey, !mapKey.isEmpty {
			queryItems.append(.init(name: "map", value: mapKey))
		}
		if let agent = agentKey.flatMap(Self.queryAgentName) {
			queryItems.append(.init(name: "agent", value: agent))
		}
		if let side = side.queryValue {
			queryItems.append(.init(name: "side", value: side))
		}
		components.queryItems = queryItems.isEmpty ? nil : queryItems
		
		var request = URLRequest(url: components.url!)
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		
		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			let status = (response as? HTTPURLResponse)?.statusCode ?? 0
			guard (200..<300).contains(status) else {
				errorMessage = status == 403
					? "Tricks.gg is blocking this network right now. You can still browse line-ups in Safari."
					: "Tricks.gg returned HTTP \(status)."
				return
			}
			let decoded = try JSONDecoder().decode(LineupResponse.self, from: data)
			guides = sorted(decoded.lineups, by: sort)
		} catch {
			errorMessage = error.localizedDescription
		}
	}
	
	/// the API ignores sort parameters, so ordering happens here
	private func sorted(_ lineups: [LineupGuide], by sort: LineupSort) -> [LineupGuide] {
		switch sort {
		case .top:
			return lineups.sorted {
				if ($0.votes ?? 0) != ($1.votes ?? 0) {
					return ($0.votes ?? 0) > ($1.votes ?? 0)
				}
				return ($0.views ?? 0) > ($1.views ?? 0)
			}
		case .trending:
			return lineups.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
		case .views:
			return lineups.sorted { ($0.views ?? 0) > ($1.views ?? 0) }
		}
	}
	
	/// the API keys agents by bare capitalized name, so "KAY/O" has to become "KAYO"
	private static func queryAgentName(_ name: String) -> String? {
		let stripped = name.filter { $0.isLetter || $0.isNumber }
		return stripped.isEmpty ? nil : stripped
	}
	
	private struct LineupResponse: Decodable {
		var lineups: [LineupGuide]
	}
}
