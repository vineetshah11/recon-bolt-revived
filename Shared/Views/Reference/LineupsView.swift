import SwiftUI
import AVKit
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
							Link("Open on Tracker.gg", destination: URL(string: "https://tracker.gg/valorant/guides/clips")!)
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
						.foregroundStyle(favoritesOnly ? Color.valorantRed : .primary)
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
							if let thumb = guide.previewImageUrl, let url = URL(string: thumb) {
								AsyncImage(url: url) { phase in
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
									if let agent = guide.attributes?.agent {
										Text(agent.capitalized)
									}
									if let side = guide.attributes?.side {
										Text("• \(side.capitalized)")
									}
									if let loc = guide.attributes?.location {
										Text("• \(loc)")
									}
								}
								.font(.caption2)
								.foregroundStyle(.secondary)
								.lineLimit(1)
								
								if let views = guide.viewsDisplay ?? guide.views.map({ "\($0.formatted()) views" }) {
									Text(views)
										.font(.caption2)
										.foregroundStyle(.tertiary)
								}
							}
							
							Spacer()
							
							if lineupsManager.isFavorite(guide) {
								Image(systemName: "heart.fill")
									.font(.caption)
									.foregroundStyle(Color.valorantRed)
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
		return list.filter {
			$0.title.localizedCaseInsensitiveContains(search)
				|| ($0.attributes?.location?.localizedCaseInsensitiveContains(search) == true)
				|| ($0.attributes?.agent?.localizedCaseInsensitiveContains(search) == true)
		}
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
				if let hlsURL = guide.hlsStreamURL {
					VideoPlayer(player: player)
						.aspectRatio(16/9, contentMode: .fit)
						.cornerRadius(12)
						.onAppear {
							let avPlayer = AVPlayer(url: hlsURL)
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
						Text("Stream URL unavailable")
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
					
					if let creator = guide.creator?.platformUserHandle {
						Text("By \(creator)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
					
					HStack(spacing: 8) {
						if let map = guide.attributes?.map { badge(map.capitalized) }
						if let agent = guide.attributes?.agent { badge(agent.capitalized) }
						if let side = guide.attributes?.side { badge(side.capitalized) }
						if let ability = guide.attributes?.ability { badge(ability.capitalized) }
					}
				}
				.padding(.horizontal, 4)
				
				Link(destination: guide.trackerURL) {
					Label("Open on Tracker.gg", systemImage: "safari")
						.frame(maxWidth: .infinity)
						.padding()
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
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
						.foregroundStyle(lineupsManager.isFavorite(guide) ? Color.valorantRed : .primary)
				}
			}
		}
	}
	
	private func badge(_ text: String) -> some View {
		Text(text)
			.font(.caption.weight(.semibold))
			.padding(.horizontal, 10)
			.padding(.vertical, 4)
			.background(Color.secondaryGroupedBackground, in: Capsule())
	}
}

private extension Array where Element: Hashable {
	func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
