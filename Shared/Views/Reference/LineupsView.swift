import SwiftUI
import AVKit
import WebKit
import ValorantAPI

struct LineupsView: View {
	@EnvironmentObject private var lineupsManager: LineupsManager
	@Environment(\.assets) private var assets
	
	@State private var selectedMapName: String? = nil
	@State private var selectedAgentName: String? = nil
	@State private var side: LineupSide = .all
	@State private var sort: LineupSort = .top
	@State private var favoritesOnly = false
	@State private var search = ""
	
	var body: some View {
		List {
			filterSection
			
			if favoritesOnly {
				guidesListSection(items: filtered(lineupsManager.favorites), header: "Saved Favorites")
			} else if lineupsManager.isLoading && lineupsManager.guides.isEmpty {
				Section {
					HStack {
						Spacer()
						ProgressView("Loading line-ups...")
						Spacer()
					}
					.padding(.vertical, 16)
				}
			} else if let errorMessage = lineupsManager.errorMessage {
				Section {
					VStack(alignment: .leading, spacing: 10) {
						Text("Unable to Load Guides")
							.font(.headline)
							.foregroundStyle(.orange)
						Text(errorMessage)
							.font(.caption)
							.foregroundStyle(.secondary)
						HStack(spacing: 12) {
							Button("Retry") {
								Task { await reload() }
							}
							Link("Open on Tricks.gg", destination: LineupGuide.siteURL)
						}
					}
					.padding(.vertical, 4)
				}
			} else {
				guidesListSection(items: filtered(lineupsManager.guides), header: "Line-Ups")
			}
		}
		.searchable(text: $search, prompt: Text("Search line-ups or locations"))
		.navigationTitle("Line-Ups")
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					favoritesOnly.toggle()
				} label: {
					Image(systemName: favoritesOnly ? "heart.fill" : "heart")
						.foregroundStyle(favoritesOnly ? Color.accentColor : .primary)
				}
			}
		}
		.refreshable {
			await reload()
		}
		.task {
			if lineupsManager.guides.isEmpty && !favoritesOnly {
				await reload()
			}
		}
		.onChange(of: selectedMapName) { _ in Task { await reload() } }
		.onChange(of: selectedAgentName) { _ in Task { await reload() } }
		.onChange(of: side) { _ in Task { await reload() } }
		.onChange(of: sort) { _ in Task { await reload() } }
	}
	
	@ViewBuilder
	private var filterSection: some View {
		Section("Filters") {
			let maps = (assets?.maps.values.map(\.displayName) ?? []).uniqued().sorted()
			Picker("Map", selection: $selectedMapName) {
				Text("All Maps").tag(String?.none)
				ForEach(maps, id: \.self) { name in
					Text(name).tag(Optional(name))
				}
			}
			
			let agents = (assets?.agents.values.map(\.displayName) ?? []).uniqued().sorted()
			Picker("Agent", selection: $selectedAgentName) {
				Text("All Agents").tag(String?.none)
				ForEach(agents, id: \.self) { name in
					Text(name).tag(Optional(name))
				}
			}
			
			Picker("Side", selection: $side) {
				ForEach(LineupSide.allCases) { s in
					Text(s.displayName).tag(s)
				}
			}
			.pickerStyle(.segmented)
			
			Picker("Sort", selection: $sort) {
				ForEach(LineupSort.allCases) { s in
					Text(s.displayName).tag(s)
				}
			}
		}
	}
	
	@ViewBuilder
	private func guidesListSection(items: [LineupGuide], header: String) -> some View {
		Section("\(header) (\(items.count))") {
			if items.isEmpty {
				Text(favoritesOnly ? "No saved favorite line-ups yet." : "No line-ups matched your current filter.")
					.foregroundStyle(.secondary)
			} else {
				ForEach(items) { guide in
					NavigationLink {
						LineupPlayerView(guide: guide)
					} label: {
						HStack(spacing: 12) {
							if let thumb = guide.thumbnailURL {
								AsyncImage(url: thumb) { phase in
									switch phase {
									case .success(let image):
										image.resizable().scaledToFill()
									default:
										Color.tertiaryGroupedBackground
									}
								}
								.frame(width: 84, height: 50)
								.cornerRadius(8)
								.clipped()
							}
							
							VStack(alignment: .leading, spacing: 4) {
								Text(guide.title)
									.font(.subheadline.weight(.semibold))
									.lineLimit(2)
								
								HStack(spacing: 6) {
									if let agent = guide.agent {
										Text(agent)
									}
									if let side = guide.side {
										Text("• \(side)")
									}
									if let map = guide.map {
										Text("• \(map)")
									}
								}
								.font(.caption2)
								.foregroundStyle(.secondary)
								.lineLimit(1)
								
								if let details = details(for: guide) {
									Text(details)
										.font(.caption2)
										.foregroundStyle(.tertiary)
										.lineLimit(1)
								}
							}
							
							Spacer()
							
							if lineupsManager.isFavorite(guide) {
								Image(systemName: "heart.fill")
									.font(.caption)
									.foregroundStyle(Color.accentColor)
							}
						}
						.padding(.vertical, 3)
					}
				}
			}
		}
	}
	
	private func filtered(_ list: [LineupGuide]) -> [LineupGuide] {
		guard !search.isEmpty else { return list }
		return list.filter { guide in
			[guide.title, guide.map, guide.agent, guide.ability, guide.side]
				.compactMap { $0 }
				.contains { $0.localizedCaseInsensitiveContains(search) }
		}
	}
	
	private func details(for guide: LineupGuide) -> String? {
		var parts: [String] = []
		if let ability = guide.ability { parts.append(ability) }
		if let views = guide.views { parts.append("\(views.formatted()) views") }
		if let difficulty = guide.difficulty, difficulty != "EASY" {
			parts.append(difficulty.capitalized)
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}
	
	private func reload() async {
		await lineupsManager.fetchGuides(
			mapKey: selectedMapName,
			agentKey: selectedAgentName,
			side: side,
			sort: sort
		)
	}
}

struct LineupPlayerView: View {
	var guide: LineupGuide
	
	@EnvironmentObject private var lineupsManager: LineupsManager
	@State private var player: AVPlayer?
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				if let videoID = guide.youtubeVideoID {
					YouTubePlayerView(videoID: videoID)
						.aspectRatio(16/9, contentMode: .fit)
						.cornerRadius(12)
						.clipped()
				} else if let videoURL = guide.videoURL {
					VideoPlayer(player: player)
						.aspectRatio(16/9, contentMode: .fit)
						.cornerRadius(12)
						.onAppear {
							let avPlayer = AVPlayer(url: videoURL)
							self.player = avPlayer
							avPlayer.play()
						}
						.onDisappear {
							player?.pause()
							player = nil
						}
				} else {
					VStack(spacing: 8) {
						Image(systemName: "video.slash")
							.font(.largeTitle)
							.foregroundStyle(.secondary)
						Text("Video unavailable")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
					.frame(maxWidth: .infinity)
					.frame(height: 200)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
				}
				
				VStack(alignment: .leading, spacing: 6) {
					Text(guide.title)
						.font(.title3.bold())
					
					if let metrics = metrics {
						Text(metrics)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
					
					HStack(spacing: 8) {
						if let map = guide.map { badge(map) }
						if let agent = guide.agent { badge(agent) }
						if let side = guide.side { badge(side) }
						if let ability = guide.ability { badge(ability) }
						if let difficulty = guide.difficulty, difficulty != "EASY" { badge(difficulty.capitalized) }
					}
				}
				.padding(.horizontal, 4)
				
				VStack(spacing: 8) {
					if guide.youtubeVideoID != nil, let videoURL = guide.videoURL {
						Link(destination: videoURL) {
							Label("Open on YouTube", systemImage: "play.rectangle")
								.frame(maxWidth: .infinity)
								.padding()
								.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
						}
					}
					
					Link(destination: LineupGuide.siteURL) {
						Label("Open on Tricks.gg", systemImage: "safari")
							.frame(maxWidth: .infinity)
							.padding()
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
					}
				}
			}
			.padding()
		}
		.navigationTitle("Line-Up")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					lineupsManager.toggleFavorite(guide)
				} label: {
					Image(systemName: lineupsManager.isFavorite(guide) ? "heart.fill" : "heart")
						.foregroundStyle(lineupsManager.isFavorite(guide) ? Color.accentColor : .primary)
				}
			}
		}
	}
	
	private var metrics: String? {
		var parts: [String] = []
		if let views = guide.views { parts.append("\(views.formatted()) views") }
		if let votes = guide.votes, votes > 0 { parts.append("\(votes) votes") }
		if let createdAt = guide.createdAt {
			parts.append("added \(createdAt.formatted(date: .abbreviated, time: .omitted))")
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}
	
	private func badge(_ text: String) -> some View {
		Text(text)
			.font(.caption.weight(.semibold))
			.padding(.horizontal, 10)
			.padding(.vertical, 4)
			.background(Color.secondaryGroupedBackground, in: Capsule())
	}
}

	/// YouTube line-ups can't be played by AVPlayer, so they go through the standard embed
	/// page in a web view with inline playback enabled.
	private struct YouTubePlayerView: UIViewRepresentable {
		let videoID: String
		
		func makeUIView(context: Context) -> WKWebView {
			let configuration = WKWebViewConfiguration()
			configuration.allowsInlineMediaPlayback = true
			configuration.mediaTypesRequiringUserActionForPlayback = []
			
			let webView = WKWebView(frame: .zero, configuration: configuration)
			webView.isOpaque = false
			webView.backgroundColor = .black
			webView.scrollView.backgroundColor = .black
			webView.scrollView.isScrollEnabled = false
			webView.scrollView.contentInsetAdjustmentBehavior = .never
			webView.loadHTMLString(Self.html(for: videoID), baseURL: URL(string: "https://www.youtube.com"))
			return webView
		}
		
		func updateUIView(_ webView: WKWebView, context: Context) {}
		
		private static func html(for videoID: String) -> String {
			let id = videoID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? videoID
			return """
		<!DOCTYPE html>
		<html>
		<head>
		<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
		<style>
		html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
		iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
		</style>
		</head>
		<body>
		<iframe src="https://www.youtube.com/embed/\(id)?playsinline=1&autoplay=1&rel=0&modestbranding=1"
				allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
		</body>
		</html>
		"""
		}
	}

private extension Array where Element: Hashable {
	func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
