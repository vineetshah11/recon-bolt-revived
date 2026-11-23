import Foundation
import Combine
import ValorantAPI
import WebKit

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
	
	/// Tracker.gg only serves its site to real browsers, so a plain app request is
	/// answered with a Cloudflare block page.
	static let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
	
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
		
		let url = components.url!
		
		var request = URLRequest(url: url)
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
		request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
		request.setValue("https://tracker.gg", forHTTPHeaderField: "Origin")
		request.setValue("https://tracker.gg/valorant/guides/clips", forHTTPHeaderField: "Referer")
		
		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			let status = (response as? HTTPURLResponse)?.statusCode ?? 0
			
			if (200..<300).contains(status) {
				try applyGuides(from: data)
				return
			}
			
			if status == 403 {
				// retry through a real browser context, which is allowed past the block
				if let data = try? await TrackerWebFetcher.shared.fetchJSON(from: url) {
					do {
						try applyGuides(from: data)
						return
					} catch {
						// fall through to the message below
					}
				}
				errorMessage = "Tracker.gg is blocking this network right now (Cloudflare 403). You can still browse line-ups in Safari."
				return
			}
			
			errorMessage = "Tracker.gg returned HTTP \(status)."
		} catch {
			errorMessage = error.localizedDescription
		}
	}
	
	private func applyGuides(from data: Data) throws {
		let decoded = try JSONDecoder().decode(TrackerGuidesResponse.self, from: data)
		guides = decoded.resolvedGuides
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

/// Tracker.gg sits behind Cloudflare, which answers app requests with a block page no
/// matter how the headers look. Loading the site in a `WKWebView` gets a real browser
/// through the check (solving any interstitial itself), so the JSON request is then run
/// from inside that page, sharing its cookies and origin, instead of from the app.
@MainActor
final class TrackerWebFetcher {
	static let shared = TrackerWebFetcher()
	
	enum Failure: LocalizedError {
		case unreachable
		case blocked(Int)
		
		var errorDescription: String? {
			switch self {
			case .unreachable:
				return "Couldn't reach Tracker.gg in the browser."
			case .blocked(let status):
				return "Tracker.gg blocked the browser request (HTTP \(status))."
			}
		}
	}
	
	private var webView: WKWebView?
	
	private init() {}
	
	func fetchJSON(from url: URL) async throws -> Data {
		let webView = await loadedPage()
		var lastStatus = 0
		
		for attempt in 0..<3 {
			if attempt > 0 {
				// Cloudflare's interstitial needs a moment before its cookie is usable
				try? await Task.sleep(nanoseconds: 1_500_000_000)
			}
			
			let script = """
			const response = await fetch(url, {
				credentials: 'include',
				headers: { 'Accept': 'application/json' },
			});
			const body = await response.text();
			return JSON.stringify({ status: response.status, body: body });
			"""
			let raw = (try? await webView.callAsyncJavaScript(
				script,
				arguments: ["url": url.absoluteString],
				contentWorld: .page
			)) as? String
			guard
				let raw,
				let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(raw.utf8))
			else {
				lastStatus = 0
				continue
			}
			
			lastStatus = envelope.status
			if (200..<300).contains(envelope.status), !envelope.body.isEmpty {
				return Data(envelope.body.utf8)
			}
		}
		
		throw Failure.blocked(lastStatus)
	}
	
	private func loadedPage() async -> WKWebView {
		if let webView {
			return webView
		}
		
		let configuration = WKWebViewConfiguration()
		// a persistent store keeps any clearance cookie for the next refresh
		configuration.websiteDataStore = .default()
		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.customUserAgent = LineupsManager.browserUserAgent
		self.webView = webView
		
		webView.load(URLRequest(url: URL(string: "https://tracker.gg/valorant/guides/clips")!))
		
		// bounded wait: the interstitial normally resolves itself in a few seconds
		for _ in 0..<40 {
			if !webView.isLoading, webView.url != nil {
				break
			}
			try? await Task.sleep(nanoseconds: 500_000_000)
		}
		
		return webView
	}
	
	private struct Envelope: Decodable {
		var status: Int
		var body: String
	}
}
