import SwiftUI
import ValorantAPI

extension AssetClient {
	func getFlexInfo() async throws -> [FlexInfo] {
		try await send(FlexInfoRequest())
	}
}

private struct FlexInfoRequest: AssetDataRequest {
	let path = "/v1/flex"
	
	typealias Response = [FlexInfo]
}

struct FlexInfo: AssetItem, Codable, Identifiable {
	typealias ID = Totem.ID
	
	var id: ID
	var displayName: String
	var displayIcon: AssetImage?
	
	private enum CodingKeys: String, CodingKey {
		case id = "uuid"
		case displayName
		case displayIcon
	}
}

extension FlexInfo: SimpleSearchableAsset {
	static let assetPath = \AssetCollection.flex
	static let inventoryPath = \Inventory.totems
	static let defaultItems: [Totem.ID] = [.statComFlex]
	
	var searchableText: String { displayName }
}

extension FlexInfo? {
	func label() -> some View {
		UnwrappingView(
			value: self?.displayName,
			placeholder: Text("Unknown Flex", comment: "placeholder")
		)
	}
}
