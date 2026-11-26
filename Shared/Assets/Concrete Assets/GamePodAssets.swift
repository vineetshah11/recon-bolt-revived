import Foundation

extension AssetClient {
	func getGamePods() async throws -> [String: String] {
		try await send(GamePodStringsRequest())
	}
}

private struct GamePodStringsRequest: AssetDataRequest {
	let path = "/v1/gamepodstrings"
	
	typealias Response = [String: String]
}
