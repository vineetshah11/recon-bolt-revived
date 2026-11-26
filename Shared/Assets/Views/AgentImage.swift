import SwiftUI
import ValorantAPI

typealias AgentImage = AssetImageView<_AgentImageProvider>
struct _AgentImageProvider: AssetImageProvider {
	static let assetPath = \AssetCollection.agents
}

extension AgentImage {
	static func icon(_ id: Agent.ID, outlineRadius: CGFloat? = nil) -> Self {
		Self(
			id: id,
			aspectRatio: 1,
			outlineRadius: outlineRadius,
			shouldLoadImmediately: true,
			getImage: \.displayIcon
		)
	}
	
	/// Displays the extracted in-game Gauntlet (`AbilityDraftAgent`) `"O"` / `"X"` Robo-Agent portrait for the player's team.
	@ViewBuilder
	static func icon(
		_ id: Agent.ID,
		outlineRadius: CGFloat? = nil,
		teamID: Team.ID?,
		isOVariant: Bool = true
	) -> some View {
		let assetName = teamID?.gauntletRoboAssetName(isOVariant: isOVariant, isKillfeed: false) ?? "gauntlet/robo_grey_x"
		if
			id == .abilityDraftAgent,
			let uiImage = UIImage.bundledAsset(named: assetName)
		{
			Image(uiImage: uiImage)
				.resizable()
				.scaledToFit()
		} else {
			icon(id, outlineRadius: outlineRadius)
		}
	}
	
	static func fullPortrait(_ id: Agent.ID, bucket: ImageBucket? = nil) -> Self {
		Self(id: id, aspectRatio: 2048/1860, preferFullResolution: bucket == nil, bucket: bucket, getImage: \.fullPortrait)
	}
	
	static func killfeedPortrait(_ id: Agent.ID) -> Self {
		Self(id: id, aspectRatio: 2, shouldLoadImmediately: true, getImage: \.killfeedPortrait)
	}
	
	@ViewBuilder
	static func killfeedPortrait(_ id: Agent.ID, teamID: Team.ID?, isOVariant: Bool = true) -> some View {
		if
			id == .abilityDraftAgent,
			let assetName = (teamID ?? Team.ID(rawID: "Team_1")).gauntletRoboAssetName(isOVariant: isOVariant, isKillfeed: true),
			let uiImage = UIImage.bundledAsset(named: assetName)
		{
			Image(uiImage: uiImage)
				.resizable()
				.scaledToFit()
		} else {
			killfeedPortrait(id)
		}
	}
	
	static func ability(_ id: Agent.ID, slot: AgentInfo.Ability.Slot) -> Self {
		Self(id: id, renderingMode: .template, aspectRatio: 1, shouldLoadImmediately: true) { $0.ability(slot)?.displayIcon }
	}
}

#if DEBUG
struct AgentImage_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			AgentImage.icon(.omen)
				.frame(height: 80)
			AgentImage.fullPortrait(.omen)
		}
		.previewLayout(.sizeThatFits)
	}
}
#endif
