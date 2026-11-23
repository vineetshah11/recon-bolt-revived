import SwiftUI
import ValorantAPI

struct RankChangesEntryProvider: FetchingIntentTimelineProvider {
	typealias Value = RankChangesInfo
	typealias Intent = ViewRankChangesIntent
	
	func fetchValue(in context: inout FetchingContext) async throws -> Value {
		let target = try context.configuration.account?.userID()
		context.link.destination = .career(target)
		let userID = target ?? context.client.userID
		
		try await context.client.autoUpdateMatchList(for: userID)
		guard let list = await LocalDataProvider.shared.matchListManager.cachedObject(for: userID) else {
			throw FetchError.noMatchList
		}
		
		return .init(matches: list)
	}
}

extension ViewRankChangesIntent: FetchingIntent {}

struct RankChangesInfo: FetchedTimelineValue {
	let matches: MatchList
	
	var nextRefresh: Date {
		.init(timeIntervalSinceNow: 60 * 60)
	}
}
