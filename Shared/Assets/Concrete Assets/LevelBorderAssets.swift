import Foundation
import ValorantAPI

extension AssetClient {
	func getLevelBorders() async throws -> [LevelBorderInfo] {
		try await send(LevelBorderInfoRequest())
	}
}

private struct LevelBorderInfoRequest: AssetDataRequest {
	let path = "/v1/levelborders"
	
	typealias Response = [LevelBorderInfo]
}

struct LevelBorderInfo: AssetItem, Codable, Identifiable, Hashable {
	private var uuid: LevelBorder.ID
	var id: LevelBorder.ID { uuid }
	var displayName: String
	var startingLevel: Int
	var levelNumberAppearance: AssetImage
	var smallPlayerCardAppearance: AssetImage
}
