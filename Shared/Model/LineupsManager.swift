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
		if let str = try? container.decode(String.self, forKey: .id) {
			id = str
		} else if let intID = try? container.decode(Int.self, forKey: .id) {
			id = String(intID)
		} else {
			id = UUID().uuidString
		}
		title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Line-Up"
		map = try container.decodeIfPresent(String.self, forKey: .map)
		agent = try container.decodeIfPresent(String.self, forKey: .agent)
		ability = try container.decodeIfPresent(String.self, forKey: .ability)
		side = try container.decodeIfPresent(String.self, forKey: .side)
		difficulty = try container.decodeIfPresent(String.self, forKey: .difficulty)
		videoURL = try container.decodeIfPresent(String.self, forKey: .videoUrl).flatMap(Self.absoluteURL)
		imageURL = try container.decodeIfPresent(String.self, forKey: .imageUrl).flatMap(Self.absoluteURL)
		views = try container.decodeIfPresent(Int.self, forKey: .views)
		votes = try container.decodeIfPresent(Int.self, forKey: .voteCount)
		createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt).flatMap(Self.date(from:))
	}
	
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
		try container.encodeIfPresent(createdAt?.formatted(.iso8601), forKey: .createdAt)
	}
	
	private static func absoluteURL(_ string: String) -> URL? {
		guard !string.isEmpty else { return nil }
		if string.hasPrefix("http") {
			return URL(string: string)
		}
		guard let base = URL(string: "https://tricks.gg") else { return nil }
		return URL(string: string, relativeTo: base)?.absoluteURL
	}
	
	private static func date(from string: String) -> Date? {
		(try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
			?? (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)))
	}
}

@MainActor
final class LineupsManager: ObservableObject {
	@Published var guides: [LineupGuide] = []
	@Published var favorites: [LineupGuide] = []
	@Published var isLoading = false
	@Published var errorMessage: String?
	
	private let favoritesFilename = "LineupFavorites.v2.json"
	private let endpoint = URL(string: "https://tricks.gg/api/lineups")!
	private var fetchGeneration = 0
	
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
	
	@discardableResult
	func importFavorites(_ incoming: [LineupGuide], replaceAll: Bool) async -> Int {
		var working = replaceAll ? [] : favorites
		var changedCount = 0
		
		for guide in incoming {
			if let idx = working.firstIndex(where: { $0.id == guide.id }) {
				if working[idx] != guide {
					working[idx] = guide
					changedCount += 1
				}
			} else {
				working.append(guide)
				changedCount += 1
			}
		}
		
		favorites = working
		await LocalJSONStore.saveAndWait(favorites, to: favoritesFilename)
		return replaceAll ? working.count : changedCount
	}
	
	func sortGuides(by sort: LineupSort) {
		guides = sorted(guides, by: sort)
	}
	
	func fetchGuides(
		mapKey: String?,
		agentKey: String?,
		side: LineupSide,
		sort: LineupSort
	) async {
		fetchGeneration += 1
		let gen = fetchGeneration
		isLoading = true
		errorMessage = nil
		defer {
			if gen == fetchGeneration {
				isLoading = false
			}
		}
		
		guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
			errorMessage = "Invalid endpoint URL."
			return
		}
		
		var queryItems: [URLQueryItem] = []
		if let mapKey, !mapKey.isEmpty {
			queryItems.append(.init(name: "map", value: mapKey))
		}
		if let agent = agentKey.flatMap(Self.queryAgentName) {
			queryItems.append(.init(name: "agent", value: agent))
		}
		if let sideValue = side.queryValue {
			queryItems.append(.init(name: "side", value: sideValue))
		}
		components.queryItems = queryItems.isEmpty ? nil : queryItems
		
		guard let url = components.url else {
			errorMessage = "Failed to build request URL."
			return
		}
		
		var request = URLRequest(url: url, timeoutInterval: 20)
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		
		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			guard !Task.isCancelled, gen == fetchGeneration else { return }
			if let http = response as? HTTPURLResponse {
				if http.statusCode == 403 {
					errorMessage = "Tricks.gg is blocking this network right now. You can still browse line-ups in Safari."
					return
				}
				if !(200..<300).contains(http.statusCode) {
					errorMessage = "Tricks.gg returned HTTP \(http.statusCode)."
					return
				}
			}
			let decoded = try JSONDecoder().decode(LineupResponse.self, from: data)
			guard !Task.isCancelled, gen == fetchGeneration else { return }
			guides = sorted(decoded.lineups, by: sort)
		} catch {
			guard !Task.isCancelled, gen == fetchGeneration else { return }
			if error is CancellationError || (error as? URLError)?.code == .cancelled {
				return
			}
			errorMessage = error.localizedDescription
		}
	}
	
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
	
	private static func queryAgentName(_ name: String) -> String? {
		let stripped = name.filter { $0.isLetter || $0.isNumber }
		return stripped.isEmpty ? nil : stripped
	}
}

private struct LineupResponse: Decodable {
	var lineups: [LineupGuide]
}