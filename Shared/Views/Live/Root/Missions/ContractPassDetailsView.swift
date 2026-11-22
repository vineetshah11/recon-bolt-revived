import SwiftUI
import ValorantAPI

struct ContractPassDetailsView: View {
	var contractInfo: ContractInfo
	var progress: Contract?
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		List {
			let chapters = contractInfo.content.chapters
			let flatBeforeChapter = chapters.indices.map { idx in
				chapters.prefix(idx).reduce(0) { $0 + $1.levels.count }
			}
			
			if let cost = contractInfo.content.premiumVPCost {
				Section {
					HStack {
						Text("Upgrade Cost")
						Spacer()
						CurrencyLabel(amount: cost, currencyID: .valorantPoints)
					}
				}
			}
			
			ForEach(Array(chapters.enumerated()), id: \.offset) { chapterIndex, chapter in
				Section {
					let startTier = flatBeforeChapter[chapterIndex]
					ForEach(Array(chapter.levels.enumerated()), id: \.offset) { levelOffset, level in
						let tierNumber = startTier + levelOffset + 1
						let reached = (progress?.levelReached ?? 0) >= tierNumber
						rewardRow(
							tierNumber: tierNumber,
							reward: level.reward,
							xp: level.xp,
							vpCost: level.isPurchasableWithVP ? level.vpCost : nil,
							doughCost: level.isPurchasableWithDough == true ? level.doughCost : nil,
							isUnlocked: reached
						)
					}
					
					if let freeRewards = chapter.freeRewards, !freeRewards.isEmpty {
						ForEach(Array(freeRewards.enumerated()), id: \.offset) { _, reward in
							rewardRow(
								tierNumber: nil,
								reward: reward,
								xp: nil,
								vpCost: nil,
								doughCost: nil,
								isUnlocked: false,
								badgeText: "FREE"
							)
						}
					}
				} header: {
					Text(chapter.isEpilogue ? "Epilogue" : "Chapter \(chapterIndex + 1)")
				}
			}
		}
		.navigationTitle(contractInfo.displayName)
	}
	
	@ViewBuilder
	private func rewardRow(
		tierNumber: Int?,
		reward: ContractInfo.Reward,
		xp: Int?,
		vpCost: Int?,
		doughCost: Int?,
		isUnlocked: Bool,
		badgeText: String? = nil
	) -> some View {
		HStack(spacing: 12) {
			rewardIcon(for: reward)
				.frame(width: 44, height: 44)
			
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					if let tierNumber {
						Text("Tier \(tierNumber)")
							.font(.caption.bold())
							.foregroundStyle(isUnlocked ? Color.green : Color.accentColor)
					}
					if let badgeText {
						Text(badgeText)
							.font(.caption2.bold())
							.padding(.horizontal, 6)
							.padding(.vertical, 2)
							.background(Color.green.opacity(0.2), in: Capsule())
							.foregroundStyle(.green)
					}
					if reward.isHighlighted {
						Image(systemName: "sparkle")
							.font(.caption2)
							.foregroundStyle(.yellow)
					}
				}
				
				Text(rewardTitle(for: reward))
					.font(.subheadline.weight(.medium))
				
				if let xp, xp > 0 {
					Text("\(xp.formatted()) XP")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			
			Spacer()
			
			if isUnlocked {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.green)
			} else if let doughCost, doughCost > 0 {
				CurrencyLabel(amount: doughCost, currencyID: .kingdomCredits)
			} else if let vpCost, vpCost > 0 {
				CurrencyLabel(amount: vpCost, currencyID: .valorantPoints)
			}
		}
		.padding(.vertical, 2)
	}
	
	@ViewBuilder
	private func rewardIcon(for reward: ContractInfo.Reward) -> some View {
		switch reward.type {
		case .skin:
			if let id = Weapon.Skin.Level.ID(reward.id), let resolved = assets?.resolveSkin(id) {
				resolved.displayIcon?.view()
			} else {
				fallbackIcon("paintpalette")
			}
		case .spray:
			if let id = Spray.ID(reward.id) {
				(assets?.sprays[id]?.bestIcon).view()
			} else {
				fallbackIcon("sparkles")
			}
		case .flex:
			if let id = Totem.ID(reward.id) {
				(assets?.flex[id]?.displayIcon).view()
			} else {
				fallbackIcon("hand.raised.fingers.spread")
			}
		case .playerCard:
			if let id = PlayerCard.ID(reward.id) {
				(assets?.playerCards[id]?.smallArt).view()
					.cornerRadius(6)
			} else {
				fallbackIcon("person.crop.rectangle")
			}
		case .gunBuddy:
			if let id = Weapon.Buddy.Level.ID(reward.id) {
				(assets?.resolveBuddy(id)?.displayIcon).view()
			} else {
				fallbackIcon("tag")
			}
		case .currency:
			if let id = Currency.ID(reward.id) {
				(assets?.currencies[id]?.displayIcon).view()
					.frame(width: 28, height: 28)
			} else {
				fallbackIcon("dollarsign.circle")
			}
		case .agent:
			if let id = Agent.ID(reward.id) {
				AgentImage.icon(id)
					.cornerRadius(6)
			} else {
				fallbackIcon("person.fill")
			}
		case .title:
			Image.bundledAsset("Player Title", renderingMode: .template)
				.resizable()
				.scaledToFit()
				.foregroundStyle(.secondary)
				.padding(6)
		default:
			fallbackIcon("gift")
		}
	}
	
	private func fallbackIcon(_ systemName: String) -> some View {
		Image(systemName: systemName)
			.foregroundStyle(.secondary)
	}
	
	private func rewardTitle(for reward: ContractInfo.Reward) -> String {
		switch reward.type {
		case .skin:
			if let id = Weapon.Skin.Level.ID(reward.id), let resolved = assets?.resolveSkin(id) {
				return resolved.skin.displayName
			}
			return "Weapon Skin"
		case .spray:
			if let id = Spray.ID(reward.id), let spray = assets?.sprays[id] {
				return spray.displayName
			}
			return "Spray"
		case .flex:
			if let id = Totem.ID(reward.id), let flex = assets?.flex[id] {
				return flex.displayName
			}
			return "Flex"
		case .playerCard:
			if let id = PlayerCard.ID(reward.id), let card = assets?.playerCards[id] {
				return card.displayName
			}
			return "Player Card"
		case .gunBuddy:
			if let id = Weapon.Buddy.Level.ID(reward.id), let buddy = assets?.resolveBuddy(id) {
				return buddy.displayName
			}
			return "Gun Buddy"
		case .currency:
			let name = Currency.ID(reward.id).flatMap { assets?.currencies[$0]?.displayNamePlural } ?? "Currency"
			return reward.amount > 1 ? "\(reward.amount) \(name)" : name
		case .agent:
			if let id = Agent.ID(reward.id), let agent = assets?.agents[id] {
				return agent.displayName
			}
			return "Agent"
		case .title:
			if let id = PlayerTitle.ID(reward.id), let title = assets?.playerTitles[id] {
				return title.titleText ?? title.displayName ?? "Player Title"
			}
			return "Player Title"
		default:
			return reward.type.rawValue
		}
	}
}
