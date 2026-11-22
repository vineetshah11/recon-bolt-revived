import SwiftUI
import ValorantAPI

struct LevelBorderPicker: View {
	@Binding var selection: LevelBorder.ID
	var cardID: PlayerCard.ID
	var accountLevel: Int
	
	var body: some View {
		AssetsUnwrappingView { assets in
			let sortedBorders = assets.levelBorders.values.sorted { $0.startingLevel < $1.startingLevel }
			let unlockedBorders = accountLevel > 0
				? sortedBorders.filter { $0.startingLevel <= accountLevel }
				: sortedBorders
			let lockedBorders = accountLevel > 0
				? sortedBorders.filter { $0.startingLevel > accountLevel }
				: []
			let activeBorder = resolvedBorder(for: selection, sortedBorders: sortedBorders)
			
			List {
				Section {
					previewHeader(activeBorder: activeBorder)
				}
				
				Section {
					SelectableRow(
						isSelected: selection.isPseudoNull,
						select: { selection = LevelBorder.ID(rawID: .stupidNullID) }
					) {
						HStack(spacing: 12) {
							Image(systemName: "wand.and.stars")
								.font(.title3)
								.foregroundStyle(Color.accentColor)
								.frame(width: 44, height: 44)
								.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8))
							
							VStack(alignment: .leading, spacing: 2) {
								Text("Automatic")
									.font(.body.weight(.medium))
								if let autoBorder = resolvedBorder(for: LevelBorder.ID(rawID: .stupidNullID), sortedBorders: sortedBorders) {
									Text("Matches your account level (\(autoBorder.displayName))")
										.font(.caption)
										.foregroundStyle(.secondary)
								} else {
									Text("Matches your current account level")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
				} header: {
					Text("Default")
				}
				
				if sortedBorders.isEmpty {
					Section {
						Text("Level border assets are still loading. Pull down in Assets Settings to refresh if needed.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				} else {
					Section {
						ForEach(unlockedBorders) { border in
							SelectableRow(selection: $selection, item: border.id) {
								borderRowContent(border, isLocked: false)
							}
						}
					} header: {
						Text("Unlocked Borders (\(unlockedBorders.count))")
					} footer: {
						if accountLevel > 0 {
							Text("Current Account Level: \(accountLevel)")
						}
					}
					
					if !lockedBorders.isEmpty {
						Section {
							ForEach(lockedBorders) { border in
								HStack {
									borderRowContent(border, isLocked: true)
									Spacer()
									Image(systemName: "lock.fill")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
						} header: {
							Text("Locked Borders (\(lockedBorders.count))")
						}
					}
				}
			}
		}
		.navigationTitle("Level Border")
	}
	
	private func previewHeader(activeBorder: LevelBorderInfo?) -> some View {
		let displayLevel = max(1, accountLevel)
		return HStack(spacing: 16) {
			ZStack(alignment: .bottom) {
				ZStack {
					PlayerCardImage.small(cardID)
						.frame(width: 82, height: 82)
						.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
					
					if let activeBorder {
						activeBorder.smallPlayerCardAppearance.view()
							.frame(width: 90, height: 90)
					}
				}
				
				if let activeBorder {
					ZStack {
						activeBorder.levelNumberAppearance.view()
							.frame(width: 68, height: 22)
						Text("\(displayLevel)")
							.font(.caption2.weight(.bold).monospacedDigit())
							.foregroundStyle(.white)
							.shadow(color: .black.opacity(0.85), radius: 2, y: 1)
					}
					.offset(y: 9)
				}
			}
			.padding(.vertical, 6)
			
			VStack(alignment: .leading, spacing: 4) {
				Text(selection.isPseudoNull ? "Automatic" : (activeBorder?.displayName ?? "Custom Border"))
					.font(.headline)
				if let activeBorder {
					Text(selection.isPseudoNull
						? "Using \(activeBorder.displayName) at Level \(displayLevel)"
						: "Requires Level \(activeBorder.startingLevel)+"
					)
					.font(.subheadline)
					.foregroundStyle(.secondary)
				}
			}
		}
	}
	
	private func borderRowContent(_ border: LevelBorderInfo, isLocked: Bool) -> some View {
		HStack(spacing: 12) {
			ZStack(alignment: .bottom) {
				ZStack {
					PlayerCardImage.small(cardID)
						.opacity(0.45)
						.frame(width: 40, height: 40)
						.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
					
					border.smallPlayerCardAppearance.view()
						.frame(width: 44, height: 44)
				}
				
				border.levelNumberAppearance.view()
					.frame(width: 36, height: 12)
					.offset(y: 4)
			}
			.padding(.vertical, 2)
			.opacity(isLocked ? 0.45 : 1)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(border.displayName)
					.font(.body.weight(.medium))
					.foregroundStyle(isLocked ? .secondary : .primary)
				Text(isLocked ? "Unlocks at Level \(border.startingLevel)" : "Level \(border.startingLevel)+")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}
	
	private func resolvedBorder(for id: LevelBorder.ID, sortedBorders: [LevelBorderInfo]) -> LevelBorderInfo? {
		if id.isPseudoNull {
			let level = max(1, accountLevel)
			return sortedBorders.last(where: { $0.startingLevel <= level }) ?? sortedBorders.first
		}
		return sortedBorders.first(where: { $0.id == id })
	}
}
