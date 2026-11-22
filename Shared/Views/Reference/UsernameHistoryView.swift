import SwiftUI
import ValorantAPI

struct UsernameHistoryView: View {
	@EnvironmentObject private var historyStore: UsernameHistoryStore
	
	@State private var search = ""
	@State private var onlyRenamed = false
	
	var body: some View {
		let timelines = historyStore.allTimelines()
			.filter { !onlyRenamed || $0.records.count > 1 }
			.filter { timeline in
				guard !search.isEmpty else { return true }
				return timeline.records.contains {
					$0.displayName.localizedCaseInsensitiveContains(search)
				} || timeline.id.description.localizedCaseInsensitiveContains(search)
			}
		
		List {
			Section {
				Toggle("Only Players With Name Changes", isOn: $onlyRenamed)
					.tint(Color.accentColor)
			}
			
			if timelines.isEmpty {
				Section {
					Text(onlyRenamed
						? "No tracked Riot ID renames observed yet. Open player profiles and matches to record name changes over time."
						: "No tracked players recorded yet.")
						.foregroundStyle(.secondary)
				}
			} else {
				ForEach(timelines) { timeline in
					Section {
						NavigationLink {
							MatchListView(userID: timeline.id)
						} label: {
							VStack(alignment: .leading, spacing: 6) {
								HStack {
									Text(timeline.latest?.displayName ?? timeline.id.description)
										.font(.headline)
									Spacer()
									if timeline.records.count > 1 {
										Text("\(timeline.records.count) names")
											.font(.caption.bold())
											.padding(.horizontal, 8)
											.padding(.vertical, 2)
											.background(Color.accentColor.opacity(0.18), in: Capsule())
											.foregroundStyle(Color.accentColor)
									}
								}
								
								ForEach(timeline.records) { record in
									HStack {
										Text(record.displayName)
											.font(.subheadline)
										Spacer()
										Text(record.lastSeen.formatted(date: .abbreviated, time: .shortened))
											.font(.caption2)
											.foregroundStyle(.secondary)
									}
								}
							}
							.padding(.vertical, 4)
						}
						.swipeActions(edge: .trailing) {
							Button(role: .destructive) {
								historyStore.clearHistory(for: timeline.id)
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search Riot IDs"))
		.navigationTitle("Name History")
	}
}
