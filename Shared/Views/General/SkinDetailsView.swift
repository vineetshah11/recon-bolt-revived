import SwiftUI
import AVKit
import ValorantAPI

struct SkinDetailsView: View {
	var skin: WeaponSkin
	var inventory: Inventory? = nil
	
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var favoritesManager: FavoritesManager
	@EnvironmentObject private var wishlistManager: WishlistManager
	@Environment(\.valorantLoad) private var load
	
	@State var videoPlayer: AVPlayer?
	@State private var selectedChromaIndex = 0
	
	private var activeAccountID: User.ID? {
		accountManager.activeAccount?.id
	}
	
	private var isOwned: Bool {
		if skin.themeID.isFree { return true }
		guard let inventory else { return true }
		return skin.levels.contains { inventory.owns($0.id) }
	}
	
	private var isFavorited: Bool {
		favoritesManager.isSkinFavorited(skin, for: activeAccountID)
	}
	
	private var isWishlisted: Bool {
		wishlistManager.contains(skin.id)
	}
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				colorVariantsSection
				
				if !skin.levels.isEmpty {
					skinLevelsSection
				}
			}
			.padding(16)
		}
		.background(Color.groupedBackground)
		.navigationTitle(skin.displayName)
		.navigationBarTitleDisplayMode(.inline)
		.fullScreenVideoPlayer(player: $videoPlayer)
		.toolbar {
			if !skin.themeID.isFree {
				ToolbarItemGroup(placement: .navigationBarTrailing) {
					if isOwned || isFavorited {
						LoadoutActionCircleButton(
							icon: isFavorited ? "star.fill" : "star",
							isActive: isFavorited,
							activeColor: .accentColor,
							isLoading: favoritesManager.isLoading(skin: skin),
							isDisabled: activeAccountID == nil
						) {
							Task {
								await load { client in
									try await favoritesManager.toggleSkinFavorite(skin, using: client)
								}
							}
						}
					}
					
					LoadoutActionCircleButton(
						icon: isWishlisted ? "heart.fill" : "heart",
						isActive: isWishlisted,
						activeColor: .accentColor
					) {
						wishlistManager.toggle(skin.id)
					}
				}
			}
		}
		.valorantLoadTask(id: activeAccountID) { client in
			await favoritesManager.refreshIfNeeded(using: client)
		}
	}
	
	@ViewBuilder
	private var colorVariantsSection: some View {
		let chromas = skin.chromas
		let currentChroma = chromas.elementIfValid(at: selectedChromaIndex) ?? chromas.first
		
		VStack(alignment: .leading, spacing: 8) {
			Text("Color Variants", comment: "Skin Details: section")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 6)
			
			VStack(spacing: 14) {
				Group {
					if let currentChroma {
						currentChroma.fullRender.view(preferFullResolution: true)
					} else {
						(skin.displayIcon ?? skin.levels.first?.displayIcon)?.view(preferFullResolution: true)
					}
				}
				.frame(maxHeight: 110)
				.frame(maxWidth: .infinity)
				.padding(.horizontal, 16)
				.padding(.top, 20)
				.padding(.bottom, chromas.count > 1 ? 4 : 20)
				.overlay(alignment: .bottomTrailing) {
					if let url = currentChroma?.streamedVideo {
						videoButton(for: url)
							.padding(14)
					}
				}
				
				if chromas.count > 1 {
					HStack(spacing: 10) {
						ForEach(Array(chromas.enumerated()), id: \.element.id) { index, chroma in
							let isSelected = index == selectedChromaIndex
							Button {
								withAnimation(.easeInOut(duration: 0.15)) {
									selectedChromaIndex = index
								}
							} label: {
								chroma.swatch.view()
									.frame(width: 28, height: 28)
									.padding(3)
									.background(
										RoundedRectangle(cornerRadius: 8, style: .continuous)
											.fill(Color.tertiaryGroupedBackground)
									)
									.overlay {
										if isSelected {
											RoundedRectangle(cornerRadius: 8, style: .continuous)
												.stroke(Color.accentColor, lineWidth: 2)
										}
									}
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.bottom, 16)
				}
			}
			.frame(maxWidth: .infinity)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private var skinLevelsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Skin Levels", comment: "Skin Details: section")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 6)
			
			VStack(spacing: 0) {
				ForEach(Array(skin.levels.enumerated()), id: \.element.id) { index, level in
					HStack(spacing: 12) {
						Text(String(localized: "Skin Level %lld", defaultValue: "Level \(index + 1)", comment: "Skin Details: level name"))
							.font(.body)
							.foregroundStyle(.primary)
						
						Spacer()
						
						if let item = level.levelItem {
							item.description
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
						
						if let url = level.streamedVideo {
							videoButton(for: url)
						}
					}
					.padding(.horizontal, 16)
					.padding(.vertical, 14)
					
					if index < skin.levels.count - 1 {
						Divider()
							.opacity(0.25)
							.padding(.leading, 16)
					}
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func videoButton(for url: URL) -> some View {
		Button {
			videoPlayer = .init(url: url, autoplay: true)
		} label: {
			Image(systemName: "play.circle.fill")
				.font(.title3)
				.foregroundStyle(Color.accentColor)
		}
		.buttonStyle(.plain)
	}
}

#if DEBUG
struct SkinDetailsView_Previews: PreviewProvider, PreviewProviderWithAssets {
	static func previews(assets: AssetCollection) -> some View {
		SkinDetailsView(skin: assets.weapons[.phantom]!.skins[1])
			.withToolbar()
			.environmentObject(AccountManager.mocked)
			.environmentObject(FavoritesManager())
			.environmentObject(WishlistManager())
	}
}
#endif
