import Foundation
import ValorantAPI
import Protoquest

extension AssetClient {
	func getAgentInfo() async throws -> [AgentInfo] {
		try await send(AgentInfoRequest())
	}
}

private struct AgentInfoRequest: AssetDataRequest {
	let path = "/v1/agents"
	
	typealias Response = [AgentInfo]
}

struct AgentInfo: AssetItem, Codable, Identifiable {
	typealias ID = Agent.ID
	
	private var uuid: ID
	var id: ID { uuid } // lazy rename
	var displayName: String
	var developerName: String
	
	var description: String?
	var characterTags: [String]?
	var role: Role?
	var abilities: [Ability]?
	var recruitmentData: RecruitmentData?
	
	struct RecruitmentData: Codable, Hashable {
		var counterID: LowercaseUUID?
		var milestoneID: LowercaseUUID?
		var milestoneThreshold: Int
		var useLevelVpCostOverride: Bool?
		var levelVpCostOverride: Int?
		var startDate: Date
		var endDate: Date
		
		private enum CodingKeys: String, CodingKey {
			case counterID = "counterId"
			case milestoneID = "milestoneId"
			case milestoneThreshold
			case useLevelVpCostOverride
			case levelVpCostOverride
			case startDate
			case endDate
		}
	}
	
	var displayIcon: AssetImage
	var fullPortrait: AssetImage?
	var killfeedPortrait: AssetImage
	var background: AssetImage?
	var isFullPortraitRightFacing: Bool
	var isPlayableCharacter: Bool
	var assetPath: String
	var backgroundGradientColors: [HexEncodedColor]?
	
	/// abilities are given in the wrong order; this reorders them appropriately
	func ability(_ slot: Ability.Slot) -> Ability? {
		abilities?.first { $0.slot == slot }
	}
	/// abilities are given in the wrong order; this reorders them appropriately
	var abilitiesInOrder: [Ability] {
		Ability.Slot.allCases.compactMap(ability)
	}
	
	struct Role: Codable, Hashable {
		typealias ID = ObjectID<Self, LowercaseUUID>
		
		private var uuid: ID
		var id: ID { uuid } // lazy rename
		var displayName: String
		var description: String
		var displayIcon: AssetImage
		var assetPath: String
	}
	
	struct Ability: Codable {
		var displayName: String
		var description: String
		var slot: Slot
		var displayIcon: AssetImage?
		
		enum Slot: String, Codable, CaseIterable {
			case passive = "Passive"
			case grenade = "Grenade"
			case ability1 = "Ability1"
			case ability2 = "Ability2"
			case ultimate = "Ultimate"
		}
	}
}
