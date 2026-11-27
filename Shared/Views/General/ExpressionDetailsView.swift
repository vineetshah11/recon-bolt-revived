import SwiftUI
import ValorantAPI

struct ExpressionDetailsView: View {
	enum Subject {
		case spray(SprayInfo)
		case totem(FlexInfo)
		
		var id: LowercaseUUID {
			switch self {
			case .spray(let info): return info.id.rawID
			case .totem(let info): return info.id.rawID
			}
		}
		
		var displayName: String {
			switch self {
			case .spray(let info): return info.displayName
			case .totem(let info): return info.displayName
			}
		}
		
		var sectionTitle: String {
			switch self {
			case .spray: return "Spray"
			case .totem: return "Totem"
			}
		}
		
		var wishlistKind: WishlistItemKind {
			switch self {
			case .spray: return .spray
			case .totem: return .flex
			}
		}
		
		var primaryImage: AssetImage? {
			switch self {
			case .spray(let info): return info.bestIcon
			case .totem(let info): return info.displayIcon
			}
		}
		
		var lightboxImages: AssetImageCollection? {
			switch self {
			case .spray(let info):
				return AssetImageCollection(images: [info.fullIcon, info.displayIcon])
			case .totem(let info):
				return info.displayIcon.map { AssetImageCollection(images: [$0]) }
			}
		}
		
		var isContextualSpray: Bool {
			if case .spray(let info) = self {
				return info.category == .contextual
			}
			return false
		}
		
		var supportsFavorites: Bool {
			switch self {
			case .spray: return true
			case .totem: return false
			}
		}
	}
	
	let subject: Subject
	var inventory: Inventory? = nil
	
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var favoritesManager: FavoritesManager
	@EnvironmentObject private var wishlistManager: WishlistManager
	@Environment(\.valorantLoad) private var load
	
	@State private var fullscreenImages: AssetImageCollection?
	
	private var activeAccountID: User.ID? {
		accountManager.activeAccount?.id
	}
	
	private var effectiveInventory: Inventory? {
		inventory ?? favoritesManager.inventory(for: activeAccountID)
	}
	
	private var isOwned: Bool {
		guard activeAccountID != nil, let effectiveInventory else { return false }
		switch subject {
		case .spray(let info):
			return effectiveInventory.sprays.contains(info.id)
		case .totem(let info):
			return effectiveInventory.totems.contains(info.id) || FlexInfo.defaultItems.contains(info.id)
		}
	}
	
	private var isFavorited: Bool {
		favoritesManager.isFavorited(subject.id, for: activeAccountID)
	}
	
	private var isWishlisted: Bool {
		wishlistManager.contains(kind: subject.wishlistKind, itemID: subject.id)
	}
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				Text(subject.sectionTitle)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 6)
				
				ZStack {
					RoundedRectangle(cornerRadius: 20, style: .continuous)
						.fill(Color.secondaryGroupedBackground)
					
					subject.primaryImage?.view(preferFullResolution: true)
						.frame(maxWidth: 165, maxHeight: 165)
						.padding(.vertical, 36)
				}
				.frame(maxWidth: .infinity, minHeight: 220)
				.overlay(alignment: .bottomTrailing) {
					if let images = subject.lightboxImages, !images.images.isEmpty {
						Button {
							fullscreenImages = images
						} label: {
							ZStack {
								Circle()
									.fill(Color.accentColor.opacity(0.18))
									.frame(width: 30, height: 30)
								Image(systemName: "arrow.up.left.and.arrow.down.right")
									.font(.system(size: 12, weight: .semibold))
									.foregroundStyle(Color.accentColor)
							}
						}
						.buttonStyle(.plain)
						.padding(14)
					}
				}
				
				if subject.isContextualSpray {
					Label(
						"Contextual spray — can only be used before or after a round.",
						systemImage: "exclamationmark.triangle"
					)
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.horizontal, 6)
				}
			}
			.padding(16)
		}
		.background(Color.groupedBackground)
		.navigationTitle(subject.displayName)
		.navigationBarTitleDisplayMode(.inline)
		.lightbox(for: $fullscreenImages)
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				if subject.supportsFavorites && isOwned {
					LoadoutActionCircleButton(
						icon: isFavorited ? "star.fill" : "star",
						isActive: isFavorited,
						activeColor: .accentColor,
						isLoading: favoritesManager.isLoading(subject.id),
						isDisabled: activeAccountID == nil
					) {
						Task {
							await load { client in
								try await favoritesManager.toggleFavorite(itemID: subject.id, using: client)
							}
						}
					}
				}
				
				LoadoutActionCircleButton(
					icon: isWishlisted ? "heart.fill" : "heart",
					isActive: isWishlisted,
					activeColor: .accentColor
				) {
					wishlistManager.toggle(kind: subject.wishlistKind, itemID: subject.id)
				}
			}
		}
		.valorantLoadTask(id: activeAccountID) { client in
			if let inventory {
				favoritesManager.cacheInventory(inventory, for: client.userID)
				await favoritesManager.refreshIfNeeded(using: client)
			} else {
				async let favsTask: Void = favoritesManager.refreshIfNeeded(using: client)
				async let invTask: Void = favoritesManager.refreshInventoryIfNeeded(using: client)
				_ = await (favsTask, invTask)
			}
		}
	}
}
