import SwiftUI
import ValorantAPI

struct BookmarkListView: View {
	let userID: User.ID
	@State var selection: SelectedBookmark? = .ownUser
	@AppStorage("BookmarkListView.shouldAutoUpdateRanks")
	var shouldAutoUpdateRanks = true
	
	@EnvironmentObject private var bookmarkList: BookmarkList
	@StateObject var history = LookupHistory()
	
	var body: some View {
		ScrollViewReader { scrollView in
			List {
				content()
			}
			.deepLinkHandler { link in
				guard
					case .widget(let link) = link,
					case .career(let id) = link.destination
				else { return }
				
				selection = id == userID ? .ownUser : .init(userID: id)
				scrollView.scrollTo(selection)
			}
		}
		.navigationTitle(Text("Players", comment: "Bookmark/Player List: title"))
	}
	
	@ViewBuilder
	func content() -> some View {
		Section {
			userCell(id: nil)
		}
		
		Section(header: Text("Bookmarks", comment: "Bookmark/Player List: section")) {
			ForEach(bookmarkList.bookmarks, id: \.self) { entry in
				userCell(id: entry.user, shouldAutoUpdate: shouldAutoUpdateRanks && selection == nil)
					.environment(\.location, entry.location)
			}
			.onDelete { bookmarkList.bookmarks.remove(atOffsets: $0) }
			.onMove { bookmarkList.bookmarks.move(fromOffsets: $0, toOffset: $1) }
			
			if !bookmarkList.bookmarks.isEmpty {
				Toggle(isOn: $shouldAutoUpdateRanks) {
					VStack(alignment: .leading, spacing: 4) {
						Text("Automatically Update Ranks", comment: "Bookmark/Player List: toggle")
						Text("This can cause a lot of requests. If you have many bookmarks or are often hitting the rate limit, you might prefer to turn this off.", comment: "Bookmark/Player List: toggle description")
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.vertical, 8)
			}
		}
		.headerProminence(.increased)
		.valorantLoadTask(id: selection == nil ? bookmarkList.bookmarks : []) {
			guard selection == nil, !bookmarkList.bookmarks.isEmpty else { return }
			try await $0.fetchUsers(for: bookmarkList.bookmarks.map(\.id))
		}
		
		Section(header: Text("Search", comment: "Bookmark/Player List: section")) {
			LookupCell(history: history)
			
			let unbookmarkedEntries = history.entries.filter { !bookmarkList.hasBookmark(for: $0.user) }
			ForEach(unbookmarkedEntries) { entry in
				userCell(id: entry.user, shouldAutoUpdate: shouldAutoUpdateRanks && selection == nil)
					.environment(\.location, entry.location)
			}
			.onDelete { offsets in
				let idsToRemove = Set(offsets.map { unbookmarkedEntries[$0].id })
				history.entries.removeAll { idsToRemove.contains($0.id) }
			}
		}
		.headerProminence(.increased)
		.valorantLoadTask(id: selection == nil ? history.entries : []) {
			guard selection == nil, !history.entries.isEmpty else { return }
			let unbookmarked = history.entries
				.filter { !bookmarkList.hasBookmark(for: $0.user) }
				.map { (userID: $0.user, location: $0.location) }
			guard !unbookmarked.isEmpty else { return }
			await $0.backfillMissingIdentities(for: unbookmarked)
		}
	}
	
	@ViewBuilder
	func userCell(id: User.ID?, shouldAutoUpdate: Bool = false) -> some View {
		let tag = SelectedBookmark(userID: id)
		UserCell(userID: id ?? userID, isSelected: $selection.equals(tag), shouldAutoUpdate: shouldAutoUpdate)
			.id(tag)
	}
}

enum SelectedBookmark: Hashable {
	case ownUser
	case other(User.ID)
	
	init(userID: User.ID?) {
		self = userID.map(Self.other) ?? .ownUser
	}
	
	var userID: User.ID? {
		switch self {
		case .ownUser:
			return nil
		case .other(let user):
			return user
		}
	}
}

#if DEBUG
struct BookmarksList_Previews: PreviewProvider {
	static var previews: some View {
		BookmarkListView(
			userID: PreviewData.userID,
			history: LookupHistory(
				entries: PreviewData.liveGameInfo.players.prefix(3)
					.map { .init(user: $0.id, location: .europe) }
			)
		)
		.withToolbar(allowLargeTitles: false)
		.environmentObject(BookmarkList(
			bookmarks: (PreviewData.pregameInfo.team.players.map(\.id) + [.init()])
				.map { .init(user: $0, location: .europe) }
		))
	}
}
#endif
