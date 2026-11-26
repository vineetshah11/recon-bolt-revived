import SwiftUI
import ValorantAPI

enum LoadoutShareCardKind: String, Identifiable {
	case profile
	case loadout
	case collection
	
	var id: String { rawValue }
}

enum SkinRarityTier: Int, CaseIterable, Identifiable {
	case exclusive = 0
	case ultra = 1
	case premium = 2
	case deluxe = 3
	case select = 4
	
	var id: Int { rawValue }
	
	var title: String {
		switch self {
		case .exclusive: return "EXCLUSIVE"
		case .ultra: return "ULTRA"
		case .premium: return "PREMIUM"
		case .deluxe: return "DELUXE"
		case .select: return "SELECT"
		}
	}
	
	var accentColor: Color {
		switch self {
		case .exclusive: return Color(red: 0.96, green: 0.56, blue: 0.24)
		case .ultra: return Color(red: 0.98, green: 0.80, blue: 0.28)
		case .premium: return Color(red: 0.80, green: 0.42, blue: 0.78)
		case .deluxe: return Color(red: 0.14, green: 0.78, blue: 0.64)
		case .select: return Color(red: 0.36, green: 0.62, blue: 0.94)
		}
	}
	
	var tileTint: Color {
		switch self {
		case .exclusive: return Color(red: 0.28, green: 0.17, blue: 0.11)
		case .ultra: return Color(red: 0.27, green: 0.22, blue: 0.10)
		case .premium: return Color(red: 0.20, green: 0.14, blue: 0.24)
		case .deluxe: return Color(red: 0.10, green: 0.22, blue: 0.20)
		case .select: return Color(red: 0.13, green: 0.18, blue: 0.26)
		}
	}
	
	init?(contentTier: ContentTier) {
		let lower = contentTier.name.lowercased()
		if lower.contains("exclusive") {
			self = .exclusive
		} else if lower.contains("ultra") {
			self = .ultra
		} else if lower.contains("premium") {
			self = .premium
		} else if lower.contains("deluxe") {
			self = .deluxe
		} else if lower.contains("select") {
			self = .select
		} else {
			switch contentTier.rank {
			case 4: self = .ultra
			case 3: self = .exclusive
			case 2: self = .premium
			case 1: self = .deluxe
			case 0: self = .select
			default: return nil
			}
		}
	}
}

// MARK: - Share Loadout Card Sheet

struct ShareLoadoutCardSheet: View {
	let loadout: UpdatableLoadout
	let user: User?
	
	@Environment(\.imageManager) private var imageManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var scope: WeaponScope = .featured
	@State private var showRiotID = true
	@State private var showBuddies = true
	@State private var preloadedImages: [AssetImage: UIImage] = [:]
	@State private var renderedImage: UIImage?
	@State private var isPreparing = true
	@State private var didCopyImage = false
	
	enum WeaponScope: String, CaseIterable, Identifiable {
		case featured = "Featured (6)"
		case all = "All Weapons"
		
		var id: String { rawValue }
	}
	
	private static let featuredWeaponIDs: [Weapon.ID] = [
		.vandal, .phantom, .melee, .operator, .frenzy, .sheriff
	]
	
	private var entries: [LoadoutShareWeaponEntry] {
		guard let assets else { return [] }
		let ids: [Weapon.ID]
		if scope == .featured {
			ids = Self.featuredWeaponIDs.filter { loadout.guns[$0] != nil }
		} else {
			let ordered = Self.featuredWeaponIDs + Weapon.ID.orderInCollection.filter { !Self.featuredWeaponIDs.contains($0) }
			ids = ordered.filter { loadout.guns[$0] != nil }
		}
		
		return ids.compactMap { gunID in
			guard let gun = loadout.guns[gunID],
			      let resolved = assets.resolveSkin(gun.skin.level)
			else { return nil }
			
			let chroma = resolved.chroma(gun.skin.chroma)
			let skinImage = chroma?.fullRender ?? chroma?.displayIcon ?? resolved.displayIcon
			let buddyImage = (showBuddies && gunID != .melee)
				? gun.buddy.flatMap { assets.buddies[$0.buddy]?.displayIcon }
				: nil
			let tier = resolved.skin.contentTierID
				.flatMap { assets.contentTiers[$0] }
				.flatMap(SkinRarityTier.init(contentTier:))
			
			return LoadoutShareWeaponEntry(
				id: gunID,
				skinName: resolved.skin.displayName,
				rarityTitle: tier?.title ?? "STANDARD",
				accentColor: tier?.accentColor ?? Color(white: 0.62),
				tileTint: tier?.tileTint ?? Color(white: 0.16),
				skinImage: skinImage,
				buddyImage: buddyImage
			)
		}
	}
	
	private var cardSmallImage: AssetImage? {
		assets?.playerCards[loadout.identity.card]?.smallArt
	}
	
	private var titleText: String? {
		assets?.playerTitles[loadout.identity.title]?.titleText
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 18) {
					LoadoutShareCardCanvas(
						gameName: showRiotID ? (user?.gameName ?? "Player") : nil,
						tagLine: showRiotID ? user?.tagLine : nil,
						titleText: titleText,
						cardImage: cardSmallImage.flatMap { preloadedImages[$0] },
						entries: entries,
						preloadedImages: preloadedImages,
						isCompactGrid: scope == .all
					)
					.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
					.shadow(color: .black.opacity(0.45), radius: 22, y: 10)
					
					controlsSection
					
					shareActionsSection
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Share Loadout")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.tint)
					}
				}
			}
			.task(id: renderTrigger) {
				await prepareAndRender()
			}
		}
	}
	
	private var renderTrigger: String {
		"\(scope.rawValue)-\(showRiotID)-\(showBuddies)"
	}
	
	private var controlsSection: some View {
		VStack(spacing: 12) {
			Picker("Weapons", selection: $scope) {
				ForEach(WeaponScope.allCases) { option in
					Text(option.rawValue).tag(option)
				}
			}
			.pickerStyle(.segmented)
			
			SettingsCard {
				Toggle("Show Riot ID", isOn: $showRiotID)
					.padding(.horizontal, 16)
					.padding(.vertical, 12)
				SettingsRowDivider(leadingInset: 16)
				Toggle("Show Buddies", isOn: $showBuddies)
					.padding(.horizontal, 16)
					.padding(.vertical, 12)
			}
		}
	}
	
	@ViewBuilder
	private var shareActionsSection: some View {
		VStack(spacing: 10) {
			if let renderedImage {
				let swiftUIImage = Image(uiImage: renderedImage)
				ShareLink(
					item: swiftUIImage,
					preview: SharePreview("VALORANT Loadout", image: swiftUIImage)
				) {
					Label("Share Loadout Card", systemImage: "square.and.arrow.up")
						.font(.headline)
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 15)
						.background(TintShapeStyle.tint, in: Capsule())
				}
				
				Button {
					UIPasteboard.general.image = renderedImage
					UIImpactFeedbackGenerator(style: .light).impactOccurred()
					withAnimation { didCopyImage = true }
					DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
						withAnimation { didCopyImage = false }
					}
				} label: {
					Label(didCopyImage ? "Copied to Clipboard" : "Copy Image", systemImage: didCopyImage ? "checkmark" : "doc.on.doc")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.tint)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 13)
						.background(Color.secondaryGroupedBackground, in: Capsule())
				}
				.buttonStyle(.plain)
			} else if isPreparing {
				ProgressView("Rendering card...")
					.padding(.vertical, 12)
			}
		}
	}
	
	@MainActor
	private func prepareAndRender() async {
		isPreparing = true
		var targets: [AssetImage] = []
		if let cardSmallImage {
			targets.append(cardSmallImage)
		}
		for entry in entries {
			if let skin = entry.skinImage { targets.append(skin) }
			if let buddy = entry.buddyImage { targets.append(buddy) }
		}
		
		let loaded = await SnapshotImageLoader.preload(targets, using: imageManager, existing: preloadedImages)
		preloadedImages = loaded
		
		let snapshot = LoadoutShareCardCanvas(
			gameName: showRiotID ? (user?.gameName ?? "Player") : nil,
			tagLine: showRiotID ? user?.tagLine : nil,
			titleText: titleText,
			cardImage: cardSmallImage.flatMap { loaded[$0] },
			entries: entries,
			preloadedImages: loaded,
			isCompactGrid: scope == .all,
			clipCorners: false
		)
		
		renderedImage = ShareCardRenderer.render(snapshot)
		isPreparing = false
	}
}

private struct LoadoutShareWeaponEntry: Identifiable {
	let id: Weapon.ID
	let skinName: String
	let rarityTitle: String
	let accentColor: Color
	let tileTint: Color
	let skinImage: AssetImage?
	let buddyImage: AssetImage?
}

private struct LoadoutShareCardCanvas: View {
	let gameName: String?
	let tagLine: String?
	let titleText: String?
	let cardImage: UIImage?
	let entries: [LoadoutShareWeaponEntry]
	let preloadedImages: [AssetImage: UIImage]
	let isCompactGrid: Bool
	var clipCorners: Bool = true
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(alignment: .top, spacing: 12) {
				VStack(alignment: .leading, spacing: 3) {
					Text("LOADOUT")
						.font(.system(size: 11, weight: .semibold))
						.tracking(1.2)
						.foregroundStyle(.white.opacity(0.45))
					
					if let gameName {
						HStack(spacing: 3) {
							Text(gameName)
								.font(.system(size: 17, weight: .bold))
								.foregroundStyle(.white)
							
							if let tagLine, !tagLine.isEmpty {
								Text("#\(tagLine)")
									.font(.system(size: 17, weight: .medium))
									.foregroundStyle(.white.opacity(0.45))
							}
						}
						.lineLimit(1)
					} else {
						Text("VALORANT Agent Loadout")
							.font(.system(size: 16, weight: .bold))
							.foregroundStyle(.white)
					}
					
					if let titleText, !titleText.isEmpty {
						Text(titleText)
							.font(.system(size: 12, weight: .semibold))
							.foregroundStyle(Color(red: 0.90, green: 0.80, blue: 0.45))
							.lineLimit(1)
					}
				}
				
				Spacer()
				
				Group {
					if let cardImage {
						Image(uiImage: cardImage)
							.resizable()
							.scaledToFill()
					} else {
						ZStack {
							Color(red: 0.24, green: 0.26, blue: 0.27)
							Image(systemName: "person.fill")
								.font(.system(size: 22))
								.foregroundStyle(.white.opacity(0.45))
						}
					}
				}
				.frame(width: 52, height: 52)
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.stroke(.white.opacity(0.12), lineWidth: 1)
				}
			}
			
			LazyVGrid(
				columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
				spacing: 8
			) {
				ForEach(entries) { entry in
					weaponTile(entry)
				}
			}
		}
		.padding(18)
		.padding(.bottom, 10)
		.background { ShareCardBackdrop() }
		.overlay(alignment: .bottomTrailing) {
			ShareCardWatermarkBadge()
				.padding(12)
		}
		.modifier(ShareCardChromeModifier(clipCorners: clipCorners))
	}
	
	private func weaponTile(_ entry: LoadoutShareWeaponEntry) -> some View {
		let artHeight: CGFloat = isCompactGrid ? 30 : 38
		return VStack(spacing: isCompactGrid ? 5 : 7) {
			HStack(spacing: 6) {
				if let buddyAsset = entry.buddyImage, let buddyUI = preloadedImages[buddyAsset] {
					Image(uiImage: buddyUI)
						.resizable()
						.scaledToFit()
						.frame(width: isCompactGrid ? 18 : 22, height: isCompactGrid ? 18 : 22)
				}
				
				if let skinAsset = entry.skinImage, let skinUI = preloadedImages[skinAsset] {
					Image(uiImage: skinUI)
						.resizable()
						.scaledToFit()
						.frame(maxWidth: .infinity, maxHeight: artHeight)
				} else {
					Image(systemName: "scope")
						.font(.system(size: isCompactGrid ? 16 : 20))
						.foregroundStyle(.white.opacity(0.35))
						.frame(maxWidth: .infinity, maxHeight: artHeight)
				}
			}
			.frame(height: artHeight)
			
			VStack(spacing: 1) {
				Text(entry.skinName)
					.font(.system(size: isCompactGrid ? 10.5 : 11.5, weight: .bold))
					.foregroundStyle(.white)
					.lineLimit(1)
					.minimumScaleFactor(0.75)
				
				Text(entry.rarityTitle)
					.font(.system(size: 8.5, weight: .bold))
					.tracking(0.8)
					.foregroundStyle(entry.accentColor)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, isCompactGrid ? 9 : 12)
		.frame(maxWidth: .infinity)
		.background(entry.tileTint.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.stroke(entry.accentColor.opacity(0.38), lineWidth: 1)
		}
	}
}

// MARK: - Share Collection Card Sheet

struct ShareCollectionCardSheet: View {
	let inventory: Inventory
	let user: User?
	
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var showRiotID = false
	@State private var renderedImage: UIImage?
	@State private var isPreparing = true
	@State private var didCopyImage = false
	
	private var summary: CollectionCardSummary {
		CollectionCardSummary.build(inventory: inventory, assets: assets)
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 18) {
					CollectionShareCardCanvas(
						summary: summary,
						riotID: showRiotID ? user.map { "\($0.gameName) #\($0.tagLine)" } : nil
					)
					.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
					.shadow(color: .black.opacity(0.45), radius: 22, y: 10)
					
					SettingsCard {
						Toggle("Show Riot ID", isOn: $showRiotID)
							.padding(.horizontal, 16)
							.padding(.vertical, 12)
					}
					
					if let renderedImage {
						let swiftUIImage = Image(uiImage: renderedImage)
						VStack(spacing: 10) {
							ShareLink(
								item: swiftUIImage,
								preview: SharePreview("VALORANT Collection", image: swiftUIImage)
							) {
								Label("Share Collection Card", systemImage: "square.and.arrow.up")
									.font(.headline)
									.foregroundStyle(.white)
									.frame(maxWidth: .infinity)
									.padding(.vertical, 15)
									.background(TintShapeStyle.tint, in: Capsule())
							}
							
							Button {
								UIPasteboard.general.image = renderedImage
								UIImpactFeedbackGenerator(style: .light).impactOccurred()
								withAnimation { didCopyImage = true }
								DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
									withAnimation { didCopyImage = false }
								}
							} label: {
								Label(didCopyImage ? "Copied to Clipboard" : "Copy Image", systemImage: didCopyImage ? "checkmark" : "doc.on.doc")
									.font(.subheadline.weight(.semibold))
									.foregroundStyle(.tint)
									.frame(maxWidth: .infinity)
									.padding(.vertical, 13)
									.background(Color.secondaryGroupedBackground, in: Capsule())
							}
							.buttonStyle(.plain)
						}
					} else if isPreparing {
						ProgressView("Rendering card...")
							.padding(.vertical, 12)
					}
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Share Collection")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.tint)
					}
				}
			}
			.task(id: showRiotID) {
				renderSnapshot()
			}
		}
	}
	
	@MainActor
	private func renderSnapshot() {
		isPreparing = true
		let snapshot = CollectionShareCardCanvas(
			summary: summary,
			riotID: showRiotID ? user.map { "\($0.gameName) #\($0.tagLine)" } : nil,
			clipCorners: false
		)
		
		renderedImage = ShareCardRenderer.render(snapshot)
		isPreparing = false
	}
}

private struct CollectionCardSummary {
	var totalSkins: Int
	var countsByTier: [SkinRarityTier: Int]
	var agentsCount: Int
	var cardsCount: Int
	var spraysCount: Int
	var buddiesCount: Int
	
	var highlightTier: (tier: SkinRarityTier, count: Int)? {
		for tier in SkinRarityTier.allCases {
			let count = countsByTier[tier, default: 0]
			if count > 0 {
				return (tier, count)
			}
		}
		return nil
	}
	
	var maxTierCount: Int {
		max(1, countsByTier.values.max() ?? 1)
	}
	
	static func build(inventory: Inventory, assets: AssetCollection?) -> CollectionCardSummary {
		var counts: [SkinRarityTier: Int] = [:]
		if let assets {
			for weapon in assets.weapons.values {
				for skin in weapon.skins {
					guard skin.id != weapon.defaultSkinID, !skin.themeID.isFree else { continue }
					let ownsSkin = skin.levels.contains { inventory.owns($0.id) }
					guard ownsSkin else { continue }
					if let tierID = skin.contentTierID,
					   let contentTier = assets.contentTiers[tierID],
					   let rarity = SkinRarityTier(contentTier: contentTier) {
						counts[rarity, default: 0] += 1
					}
				}
			}
		}
		
		let total = counts.values.reduce(0, +)
		return CollectionCardSummary(
			totalSkins: total,
			countsByTier: counts,
			agentsCount: inventory.agents.count,
			cardsCount: inventory.cards.count,
			spraysCount: inventory.sprays.count,
			buddiesCount: inventory.buddies.count
		)
	}
}

private struct CollectionShareCardCanvas: View {
	let summary: CollectionCardSummary
	let riotID: String?
	var clipCorners: Bool = true
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 4) {
					HStack(spacing: 6) {
						Text("MY COLLECTION")
							.font(.system(size: 11, weight: .semibold))
							.tracking(1.2)
							.foregroundStyle(.white.opacity(0.45))
						
						if let riotID, !riotID.isEmpty {
							Text("· \(riotID)")
								.font(.system(size: 11, weight: .semibold))
								.foregroundStyle(.white.opacity(0.65))
								.lineLimit(1)
						}
					}
					
					Text("\(summary.totalSkins)")
						.font(.system(size: 48, weight: .heavy, design: .rounded))
						.monospacedDigit()
						.foregroundStyle(.white)
					
					Text("WEAPON SKINS")
						.font(.system(size: 11, weight: .bold))
						.tracking(1.0)
						.foregroundStyle(.white.opacity(0.5))
				}
				
				Spacer()
				
				if let highlight = summary.highlightTier {
					VStack(alignment: .trailing, spacing: 2) {
						Text("\(highlight.count)")
							.font(.system(size: 20, weight: .bold, design: .rounded))
							.monospacedDigit()
							.foregroundStyle(.white)
						
						Text(highlight.tier.title)
							.font(.system(size: 9.5, weight: .bold))
							.tracking(0.8)
							.foregroundStyle(highlight.tier.accentColor)
					}
				}
			}
			
			VStack(alignment: .leading, spacing: 12) {
				Text("SKINS BY RARITY")
					.font(.system(size: 10.5, weight: .bold))
					.tracking(1.1)
					.foregroundStyle(.white.opacity(0.45))
				
				VStack(spacing: 11) {
					ForEach(SkinRarityTier.allCases) { tier in
						let count = summary.countsByTier[tier, default: 0]
						let fraction = CGFloat(count) / CGFloat(summary.maxTierCount)
						
						HStack(spacing: 10) {
							Circle()
								.fill(tier.accentColor)
								.frame(width: 7, height: 7)
							
							Text(tier.title)
								.font(.system(size: 11.5, weight: .semibold))
								.foregroundStyle(.white.opacity(0.88))
								.frame(width: 82, alignment: .leading)
							
							GeometryReader { geo in
								ZStack(alignment: .leading) {
									Capsule()
										.fill(.white.opacity(0.08))
									
									if count > 0 {
										Capsule()
											.fill(tier.accentColor)
											.frame(width: max(8, geo.size.width * fraction))
									}
								}
							}
							.frame(height: 6)
							
							Text("\(count)")
								.font(.system(size: 12, weight: .semibold, design: .rounded))
								.monospacedDigit()
								.foregroundStyle(.white.opacity(0.78))
								.frame(minWidth: 26, alignment: .trailing)
						}
					}
				}
			}
			.padding(16)
			.background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.stroke(.white.opacity(0.08), lineWidth: 1)
			}
			
			HStack(spacing: 0) {
				summaryStatColumn(value: summary.agentsCount, label: "AGENTS")
				Divider().frame(height: 30).overlay(.white.opacity(0.10))
				summaryStatColumn(value: summary.cardsCount, label: "CARDS")
				Divider().frame(height: 30).overlay(.white.opacity(0.10))
				summaryStatColumn(value: summary.spraysCount, label: "SPRAYS")
				Divider().frame(height: 30).overlay(.white.opacity(0.10))
				summaryStatColumn(value: summary.buddiesCount, label: "BUDDIES")
			}
			.padding(.vertical, 13)
			.background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.stroke(.white.opacity(0.08), lineWidth: 1)
			}
		}
		.padding(18)
		.padding(.bottom, 10)
		.background { ShareCardBackdrop() }
		.overlay(alignment: .bottomTrailing) {
			ShareCardWatermarkBadge()
				.padding(12)
		}
		.modifier(ShareCardChromeModifier(clipCorners: clipCorners))
	}
	
	private func summaryStatColumn(value: Int, label: String) -> some View {
		VStack(spacing: 3) {
			Text("\(value)")
				.font(.system(size: 20, weight: .bold, design: .rounded))
				.monospacedDigit()
				.foregroundStyle(.white)
			
			Text(label)
				.font(.system(size: 9.5, weight: .semibold))
				.tracking(0.6)
				.foregroundStyle(.white.opacity(0.45))
		}
		.frame(maxWidth: .infinity)
	}
}

// MARK: - Shared Card Chrome & Image Preloader

struct ShareCardBackdrop: View {
	static let baseColor = Color(red: 0.06, green: 0.06, blue: 0.08)
	
	var body: some View {
		ZStack {
			Self.baseColor
			
			LinearGradient(
				colors: [
					Color(red: 0.08, green: 0.08, blue: 0.10),
					Self.baseColor,
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
			
			RadialGradient(
				colors: [
					Color(red: 0.42, green: 0.12, blue: 0.18).opacity(0.42),
					Color.clear,
				],
				center: .topTrailing,
				startRadius: 10,
				endRadius: 260
			)
		}
	}
}

struct ShareCardWatermarkBadge: View {
	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.fill(Color.white.opacity(0.06))
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.stroke(Color.white.opacity(0.09), lineWidth: 1)
			Image(systemName: "bolt.shield.fill")
				.font(.system(size: 13, weight: .bold))
				.foregroundStyle(Color(red: 0.94, green: 0.25, blue: 0.36).opacity(0.55))
		}
		.frame(width: 28, height: 28)
	}
}

struct ShareCardChromeModifier: ViewModifier {
	let clipCorners: Bool
	
	func body(content: Content) -> some View {
		if clipCorners {
			content
				.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 24, style: .continuous)
						.stroke(.white.opacity(0.08), lineWidth: 1)
				}
		} else {
			content
		}
	}
}

enum ShareCardRenderer {
	@MainActor
	static func render<Content: View>(
		_ content: Content,
		width: CGFloat = 370,
		scale: CGFloat = 3.0
	) -> UIImage? {
		let wrapped = content
			.frame(width: width)
			.background(ShareCardBackdrop.baseColor)
			.preferredColorScheme(.dark)
		let renderer = ImageRenderer(content: wrapped)
		renderer.scale = scale
		renderer.isOpaque = true
		return renderer.uiImage
	}
}

struct ShareCardActionButtons: View {
	let renderedImage: UIImage?
	let isPreparing: Bool
	let shareTitle: String
	let previewTitle: String
	@Binding var didCopyImage: Bool
	
	var body: some View {
		if let renderedImage {
			let swiftUIImage = Image(uiImage: renderedImage)
			VStack(spacing: 10) {
				ShareLink(
					item: swiftUIImage,
					preview: SharePreview(previewTitle, image: swiftUIImage)
				) {
					Label(shareTitle, systemImage: "square.and.arrow.up")
						.font(.headline)
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 15)
						.background(TintShapeStyle.tint, in: Capsule())
				}
				
				Button {
					UIPasteboard.general.image = renderedImage
					UIImpactFeedbackGenerator(style: .light).impactOccurred()
					withAnimation { didCopyImage = true }
					DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
						withAnimation { didCopyImage = false }
					}
				} label: {
					Label(
						didCopyImage ? "Copied to Clipboard" : "Copy Image",
						systemImage: didCopyImage ? "checkmark" : "doc.on.doc"
					)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.tint)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 13)
					.background(Color.secondaryGroupedBackground, in: Capsule())
				}
				.buttonStyle(.plain)
			}
		} else if isPreparing {
			ProgressView("Rendering card...")
				.padding(.vertical, 12)
		}
	}
}

struct ShareProfileCardSheet: View {
	let user: User?
	let cardID: PlayerCard.ID?
	let titleID: PlayerTitle.ID?
	let accountLevel: Int
	let summary: CareerSummary?
	
	@Environment(\.imageManager) private var imageManager
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@Environment(\.dismiss) private var dismiss
	
	@State private var showRiotID = true
	@State private var preloadedImages: [AssetImage: UIImage] = [:]
	@State private var renderedImage: UIImage?
	@State private var isPreparing = true
	@State private var didCopyImage = false
	
	private var cardSmallImage: AssetImage? {
		cardID.flatMap { assets?.playerCards[$0]?.smallArt }
	}
	
	private var titleText: String? {
		titleID.flatMap { assets?.playerTitles[$0]?.titleText }
	}
	
	private var profileData: ProfileCardData {
		ProfileCardData.build(
			user: user,
			titleText: titleText,
			accountLevel: accountLevel,
			summary: summary,
			seasons: seasons,
			showRiotID: showRiotID
		)
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 18) {
					ProfileShareCardCanvas(
						data: profileData,
						cardImage: cardSmallImage.flatMap { preloadedImages[$0] }
					)
					.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
					.shadow(color: .black.opacity(0.45), radius: 22, y: 10)
					
					SettingsCard {
						Toggle("Show Riot ID", isOn: $showRiotID)
							.padding(.horizontal, 16)
							.padding(.vertical, 12)
					}
					
					ShareCardActionButtons(
						renderedImage: renderedImage,
						isPreparing: isPreparing,
						shareTitle: "Share Profile Card",
						previewTitle: "VALORANT Profile",
						didCopyImage: $didCopyImage
					)
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Share Profile")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.tint)
					}
				}
			}
			.task(id: showRiotID) {
				await prepareAndRender()
			}
		}
	}
	
	@MainActor
	private func prepareAndRender() async {
		isPreparing = true
		let targets = cardSmallImage.map { [$0] } ?? []
		let loaded = await SnapshotImageLoader.preload(targets, using: imageManager, existing: preloadedImages)
		preloadedImages = loaded
		
		let snapshot = ProfileShareCardCanvas(
			data: profileData,
			cardImage: cardSmallImage.flatMap { loaded[$0] },
			clipCorners: false
		)
		
		renderedImage = ShareCardRenderer.render(snapshot)
		isPreparing = false
	}
}

private struct ProfileCardData {
	let gameName: String?
	let tagLine: String?
	let titleText: String?
	let accountLevel: Int
	let currentRankName: String
	let currentRankColor: Color
	let currentRR: Int?
	let currentActLabel: String?
	let peakRankName: String
	let peakRankColor: Color
	let peakActLabel: String?
	let games: Int
	let wins: Int
	
	var winRatePercent: Int {
		guard games > 0 else { return 0 }
		return Int((Double(wins) * 100.0 / Double(games)).rounded())
	}
	
	static func build(
		user: User?,
		titleText: String?,
		accountLevel: Int,
		summary: CareerSummary?,
		seasons: SeasonCollection.Accessor?,
		showRiotID: Bool
	) -> ProfileCardData {
		let currentAct = seasons?.currentAct()
		let currentInfo = summary?.competitiveInfo?.inSeason(currentAct?.id)
		let currentTier = seasons?.tierInfo(number: currentInfo?.competitiveTier, in: currentAct)
		
		let peakRank = summary?.peakRank(seasons: seasons)
		let peakTier = peakRank.flatMap { seasons?.tierInfo($0) }
		let peakAct = peakRank.flatMap { seasons?.act($0.season) }
		
		let bySeason = summary?.competitiveInfo?.bySeason ?? [:]
		let actGames = currentInfo?.gameCount ?? 0
		let actWins = currentInfo?.winCountIncludingPlacements ?? 0
		
		let resolvedGames: Int
		let resolvedWins: Int
		if actGames > 0 {
			resolvedGames = actGames
			resolvedWins = actWins
		} else {
			let totals = bySeason.values.reduce((wins: 0, games: 0)) { acc, item in
				(acc.wins + item.winCountIncludingPlacements, acc.games + item.gameCount)
			}
			resolvedGames = totals.games
			resolvedWins = totals.wins
		}
		
		return ProfileCardData(
			gameName: showRiotID ? (user?.gameName ?? "Player") : nil,
			tagLine: showRiotID ? user?.tagLine : nil,
			titleText: titleText,
			accountLevel: accountLevel,
			currentRankName: currentTier?.name ?? "Unranked",
			currentRankColor: rankAccentColor(for: currentTier),
			currentRR: (currentInfo?.competitiveTier ?? 0) > 0 ? currentInfo?.adjustedRankedRating : nil,
			currentActLabel: currentAct.map(formattedActLabel),
			peakRankName: peakTier?.name ?? "Unranked",
			peakRankColor: rankAccentColor(for: peakTier),
			peakActLabel: peakAct.map(formattedActLabel),
			games: resolvedGames,
			wins: resolvedWins
		)
	}
	
	private static func formattedActLabel(_ act: Act) -> String {
		if let episode = act.episode {
			return "\(episode.name) – \(act.name)".uppercased()
		}
		return act.name.uppercased()
	}
	
	private static func rankAccentColor(for tier: CompetitiveTier?) -> Color {
		guard let name = tier?.name.lowercased() else {
			return Color.white.opacity(0.65)
		}
		if name.contains("radiant") { return Color(red: 1.00, green: 0.90, blue: 0.45) }
		if name.contains("immortal") { return Color(red: 0.92, green: 0.30, blue: 0.45) }
		if name.contains("ascendant") { return Color(red: 0.16, green: 0.84, blue: 0.56) }
		if name.contains("diamond") { return Color(red: 0.78, green: 0.54, blue: 0.96) }
		if name.contains("platinum") { return Color(red: 0.28, green: 0.76, blue: 0.84) }
		if name.contains("gold") { return Color(red: 0.95, green: 0.76, blue: 0.28) }
		if name.contains("silver") { return Color(red: 0.78, green: 0.82, blue: 0.86) }
		if name.contains("bronze") { return Color(red: 0.76, green: 0.54, blue: 0.34) }
		if name.contains("iron") { return Color(red: 0.58, green: 0.58, blue: 0.60) }
		return Color.white.opacity(0.65)
	}
}

private struct ProfileShareCardCanvas: View {
	let data: ProfileCardData
	let cardImage: UIImage?
	var clipCorners: Bool = true
	
	private let badgeIconColor = Color(red: 0.98, green: 0.95, blue: 0.80)
	
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .top, spacing: 12) {
				VStack(alignment: .leading, spacing: 3) {
					Text("PLAYER PROFILE")
						.font(.system(size: 11, weight: .semibold))
						.tracking(1.2)
						.foregroundStyle(.white.opacity(0.45))
					
					if let gameName = data.gameName {
						HStack(spacing: 4) {
							Text(gameName)
								.font(.system(size: 21, weight: .heavy))
								.foregroundStyle(.white)
							
							if let tagLine = data.tagLine, !tagLine.isEmpty {
								Text("#\(tagLine)")
									.font(.system(size: 21, weight: .medium))
									.foregroundStyle(.white.opacity(0.45))
							}
						}
						.lineLimit(1)
						.minimumScaleFactor(0.75)
					} else {
						Text("VALORANT Player")
							.font(.system(size: 20, weight: .heavy))
							.foregroundStyle(.white)
					}
					
					if let titleText = data.titleText, !titleText.isEmpty {
						Text(titleText)
							.font(.system(size: 12.5, weight: .medium))
							.foregroundStyle(.white.opacity(0.62))
							.lineLimit(1)
					}
				}
				
				Spacer(minLength: 8)
				
				if data.accountLevel > 0 {
					VStack(alignment: .trailing, spacing: 1) {
						Text("\(data.accountLevel)")
							.font(.system(size: 20, weight: .heavy, design: .rounded))
							.monospacedDigit()
							.foregroundStyle(.white)
						
						Text("LEVEL")
							.font(.system(size: 9.5, weight: .semibold))
							.tracking(0.8)
							.foregroundStyle(.white.opacity(0.45))
					}
				}
			}
			
			HStack(spacing: 12) {
				Group {
					if let cardImage {
						Image(uiImage: cardImage)
							.resizable()
							.scaledToFill()
					} else {
						ZStack {
							Color(red: 0.21, green: 0.29, blue: 0.28)
							Image(systemName: "person.fill")
								.font(.system(size: 46))
								.foregroundStyle(.white.opacity(0.55))
						}
					}
				}
				.frame(width: 112, height: 112)
				.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 14, style: .continuous)
						.stroke(.white.opacity(0.10), lineWidth: 1)
				}
				
				VStack(spacing: 10) {
					rankTile(
						icon: "chart.xyaxis.line",
						header: "CURRENT RANK",
						rankName: data.currentRankName,
						rankColor: data.currentRankColor,
						rr: data.currentRR,
						actLabel: data.currentActLabel
					)
					
					rankTile(
						icon: "medal.fill",
						header: "LIFETIME PEAK",
						rankName: data.peakRankName,
						rankColor: data.peakRankColor,
						rr: nil,
						actLabel: data.peakActLabel
					)
				}
			}
			
			HStack(spacing: 0) {
				statColumn(value: "\(data.games)", label: "GAMES")
				statColumn(value: "\(data.wins)", label: "WINS")
				statColumn(value: "\(data.winRatePercent) %", label: "WIN RATE")
			}
			.padding(.vertical, 14)
			.background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.stroke(.white.opacity(0.08), lineWidth: 1)
			}
		}
		.padding(18)
		.padding(.bottom, 10)
		.background { ShareCardBackdrop() }
		.overlay(alignment: .bottomTrailing) {
			ShareCardWatermarkBadge()
				.padding(12)
		}
		.modifier(ShareCardChromeModifier(clipCorners: clipCorners))
	}
	
	private func rankTile(
		icon: String,
		header: String,
		rankName: String,
		rankColor: Color,
		rr: Int?,
		actLabel: String?
	) -> some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.font(.system(size: 19, weight: .semibold))
				.foregroundStyle(badgeIconColor)
				.frame(width: 28)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(header)
					.font(.system(size: 9, weight: .bold))
					.tracking(0.9)
					.foregroundStyle(.white.opacity(0.45))
				
				Text(rankName)
					.font(.system(size: 16, weight: .bold))
					.foregroundStyle(rankColor)
					.lineLimit(1)
					.minimumScaleFactor(0.8)
				
				if let rr {
					Text("\(rr) RR")
						.font(.system(size: 11, weight: .semibold))
						.monospacedDigit()
						.foregroundStyle(.white.opacity(0.65))
				}
				
				if let actLabel, !actLabel.isEmpty {
					Text(actLabel)
						.font(.system(size: 9, weight: .semibold))
						.tracking(0.4)
						.foregroundStyle(.white.opacity(0.42))
						.lineLimit(1)
						.minimumScaleFactor(0.8)
				}
			}
			
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.stroke(.white.opacity(0.08), lineWidth: 1)
		}
	}
	
	private func statColumn(value: String, label: String) -> some View {
		VStack(spacing: 3) {
			Text(value)
				.font(.system(size: 19, weight: .bold, design: .rounded))
				.monospacedDigit()
				.foregroundStyle(.white)
			
			Text(label)
				.font(.system(size: 9.5, weight: .semibold))
				.tracking(0.6)
				.foregroundStyle(.white.opacity(0.45))
		}
		.frame(maxWidth: .infinity)
	}
}

private enum SnapshotImageLoader {
	@MainActor
	static func preload(
		_ targets: [AssetImage],
		using imageManager: ImageManager,
		existing: [AssetImage: UIImage]
	) async -> [AssetImage: UIImage] {
		var result = existing
		var missing: [AssetImage] = []
		var seen: Set<AssetImage> = []
		for asset in targets where result[asset] == nil && seen.insert(asset).inserted {
			if let cached = imageManager.cachedImage(for: asset, bucket: .full) {
				result[asset] = cached
			} else {
				missing.append(asset)
			}
		}
		guard !missing.isEmpty else { return result }
		
		await withTaskGroup(of: (AssetImage, UIImage?).self) { group in
			var nextIndex = 0
			let maxConcurrent = 4
			for _ in 0..<min(maxConcurrent, missing.count) {
				let asset = missing[nextIndex]
				nextIndex += 1
				group.addTask {
					let loaded = await imageManager.awaitImage(for: asset, bucket: .full)
					return (asset, loaded)
				}
			}
			for await (asset, loaded) in group {
				if let loaded {
					result[asset] = loaded
				}
				if nextIndex < missing.count {
					let nextAsset = missing[nextIndex]
					nextIndex += 1
					group.addTask {
						let loaded = await imageManager.awaitImage(for: nextAsset, bucket: .full)
						return (nextAsset, loaded)
					}
				}
			}
		}
		return result
	}
}
