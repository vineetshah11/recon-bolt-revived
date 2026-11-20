import Foundation
import ValorantAPI

extension AssetClient {
	func getTotemInfo() async throws -> [TotemInfo] {
		try await send(TotemInfoRequest())
	}
}

private struct TotemInfoRequest: AssetDataRequest {
	// valorant-api.com serves totems (the game calls their asset path "Equippables/Totems") under /v1/flex
	let path = "/v1/flex"
	
	typealias Response = [TotemInfo]
}

struct TotemInfo: AssetItem, Codable, Identifiable {
	/// Riot returns totems in the regular spray slots of the loadout, so they're keyed by the same ID type.
	var id: Spray.ID
	var displayName: String
	var displayIcon: AssetImage
	
	var bestIcon: AssetImage { displayIcon }
	
	private enum CodingKeys: String, CodingKey {
		case id = "uuid"
		case displayName
		case displayIcon
	}
}
