import SwiftUI
import ValorantAPI

struct WishlistView: View {
	@EnvironmentObject private var wishlistManager: WishlistManager
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var shopHistoryStore: ShopHistoryStore
	@Environment(\.assets) private var assets
	@Environment(\.colorScheme) private var colorScheme
	
	@State private var showingPicker = false
	@State private var isCheckingShop = false
	@State private var checkFeedback: String?
	@State private var fullscreenImages: AssetImageCollection?
	@State private var selectedSkin: WeaponSkin?
	@State private var selectedExpression: ExpressionDetailsView.Subject?
	@State private var cachedResolvedItems: [ResolvedWishlistItem] = []
	
	private struct ResolveKey: Equatable {
		var entries: [WishlistEntry]
		var assetVersion: AssetVersion?
	}
	
	private enum ResolvedWishlistItem: Identifiable {
		case skin(entry: WishlistEntry, skin: WeaponSkin, weapon: WeaponInfo)
		case buddy(entry: WishlistEntry, buddy: BuddyInfo)
		case spray(entry: WishlistEntry, spray: SprayInfo)
		case card(entry: WishlistEntry, card: PlayerCardInfo)
		case title(entry: WishlistEntry, title: PlayerTitleInfo)
		case flex(entry: WishlistEntry, flex: FlexInfo)
		
		var id: String { "\(entry.kind.rawValue)-\(entry.itemID)" }
		
		var entry: WishlistEntry {
			switch self {
			case .skin(let e, _, _),
				 .buddy(let e, _),
				 .spray(let e, _),
				 .card(let e, _),
				 .title(let e, _),
				 .flex(let e, _):
				return e
			}
		}
	}
	
	private func buildResolvedItems() -> [ResolvedWishlistItem] {
		guard let assets else { return [] }
		let needsSkin = wishlistManager.entries.contains { $0.kind == .skin }
		let skinByID: [WeaponSkin.ID: (WeaponSkin, WeaponInfo)]
		if needsSkin {
			var map: [WeaponSkin.ID: (WeaponSkin, WeaponInfo)] = [:]
			for weapon in assets.weapons.values {
				for skin in weapon.skins {
					map[skin.id] = (skin, weapon)
				}
			}
			skinByID = map
		} else {
			skinByID = [:]
		}
		return wishlistManager.entries.compactMap { entry in
			switch entry.kind {
			case .skin:
				guard let (skin, weapon) = skinByID[entry.skinID] else { return nil }
				return .skin(entry: entry, skin: skin, weapon: weapon)
			case .buddy:
				guard let buddy = assets.buddies[Weapon.Buddy.ID(rawID: entry.itemID)] else { return nil }
				return .buddy(entry: entry, buddy: buddy)
			case .spray:
				guard let spray = assets.sprays[Spray.ID(rawID: entry.itemID)] else { return nil }
				return .spray(entry: entry, spray: spray)
			case .card:
				guard let card = assets.playerCards[PlayerCard.ID(rawID: entry.itemID)] else { return nil }
				return .card(entry: entry, card: card)
			case .title:
				guard let title = assets.playerTitles[PlayerTitle.ID(rawID: entry.itemID)] else { return nil }
				return .title(entry: entry, title: title)
			case .flex:
				guard let flex = assets.flex[Totem.ID(rawID: entry.itemID)] else { return nil }
				return .flex(entry: entry, flex: flex)
			}
		}
	}
	
	private var columns: [GridItem] {
		[
			GridItem(.flexible(), spacing: 12),
			GridItem(.flexible(), spacing: 12),
		]
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				dailyCheckCard
				
				if let checkFeedback {
					HStack(spacing: 10) {
						Image(systemName: "sparkles")
							.foregroundStyle(Color.accentColor)
						Text(checkFeedback)
							.font(.subheadline)
							.foregroundStyle(.primary)
						Spacer()
					}
					.padding(14)
					.background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				}
				
				if cachedResolvedItems.isEmpty {
					emptyStateCard
				} else {
					LazyVGrid(columns: columns, spacing: 12) {
						ForEach(cachedResolvedItems) { item in
							wishlistCard(for: item)
						}
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Wishlist")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: ResolveKey(entries: wishlistManager.entries, assetVersion: assets?.version)) {
			cachedResolvedItems = buildResolvedItems()
		}
		.lightbox(for: $fullscreenImages)
		.navigationDestination(isPresented: Binding(
			get: { selectedSkin != nil },
			set: { if !$0 { selectedSkin = nil } }
		)) {
			if let selectedSkin {
				SkinDetailsView(skin: selectedSkin)
			}
		}
		.navigationDestination(isPresented: Binding(
			get: { selectedExpression != nil },
			set: { if !$0 { selectedExpression = nil } }
		)) {
			if let selectedExpression {
				ExpressionDetailsView(subject: selectedExpression)
			}
		}
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					showingPicker = true
				} label: {
					Image(systemName: "plus")
				}
			}
		}
		.sheet(isPresented: $showingPicker) {
			NavigationStack {
				WishlistItemPicker()
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button("Done") { showingPicker = false }
						}
					}
			}
		}
	}
	
	private var dailyCheckCard: some View {
		let lastCheck = shopHistoryStore.lastDailyCheckAt
		let checkAccounts = max(1, shopHistoryStore.lastDailyCheckAccountCount)
		let storedCount = accountManager.storedAccounts.count
		
		return HStack(spacing: 12) {
			Image(systemName: lastCheck != nil ? "checkmark.circle.fill" : "clock.fill")
				.font(.system(size: 22))
				.foregroundStyle(lastCheck != nil ? Color.green : Color.secondary)
			
			VStack(alignment: .leading, spacing: 2) {
				Text("Daily Check")
					.font(.headline)
				
				if let lastCheck {
					let dayLabel = Calendar.current.isDateInToday(lastCheck)
						? "today at \(lastCheck.formatted(date: .omitted, time: .shortened))"
						: lastCheck.formatted(date: .abbreviated, time: .shortened)
					Text("Checked \(dayLabel) · \(checkAccounts) account\(checkAccounts == 1 ? "" : "s")")
						.font(.caption)
						.foregroundStyle(.secondary)
				} else {
					Text(storedCount > 0 ? "Tap Check Now to scan your shop" : "Sign in to check your daily shop")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			
			Spacer(minLength: 8)
			
			Button {
				Task { await checkNow() }
			} label: {
				HStack(spacing: 6) {
					if isCheckingShop {
						ProgressView()
							.controlSize(.small)
					} else {
						Text("Check Now")
							.font(.subheadline.weight(.semibold))
					}
				}
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 14)
				.padding(.vertical, 8)
				.background(Color.accentColor.opacity(0.18), in: Capsule())
			}
			.buttonStyle(.plain)
			.disabled(isCheckingShop || storedCount == 0)
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var emptyStateCard: some View {
		VStack(spacing: 10) {
			Image(systemName: "heart.text.square")
				.font(.system(size: 36))
				.foregroundStyle(Color.accentColor)
			Text("No Wishlisted Items")
				.font(.headline)
			Text("Tap + to add weapon skins, buddies, sprays, cards, or titles to your wishlist and track when they appear in your shop.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(24)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	@ViewBuilder
	private func wishlistCard(for item: ResolvedWishlistItem) -> some View {
		let stats = shopHistoryStore.appearanceStats(
			for: item.entry,
			accountID: accountManager.activeAccount?.id,
			assets: assets
		)
		let statsText = formattedAppearanceText(stats)
		
		switch item {
		case .skin(let entry, let skin, let weapon):
			let tier = skin.contentTierID.flatMap { assets?.contentTiers[$0] }
			let tierColor = tier?.color?.opaque() ?? .accentColor
			let image = skin.chromas.first?.fullRender ?? skin.displayIcon ?? skin.levels.first?.displayIcon
			
			Button {
				selectedSkin = skin
			} label: {
				VStack(alignment: .leading, spacing: 8) {
					HStack {
						tier?.displayIcon.view()
							.frame(width: 20, height: 20)
						Spacer()
						Button {
							wishlistManager.remove(kind: .skin, itemID: entry.itemID)
						} label: {
							Image(systemName: "heart.fill")
								.font(.subheadline.weight(.semibold))
								.foregroundColor(tierColor, adjustedFor: colorScheme)
						}
						.buttonStyle(.plain)
					}
					
					Spacer(minLength: 4)
					
					image?.view()
						.frame(height: 64)
						.frame(maxWidth: .infinity)
					
					Spacer(minLength: 4)
					
					VStack(alignment: .leading, spacing: 2) {
						Text(skin.displayName)
							.font(.subheadline.weight(.semibold))
							.foregroundColor(tierColor, adjustedFor: colorScheme)
							.lineLimit(2)
							.multilineTextAlignment(.leading)
						
						Text(weapon.displayName)
							.font(.caption)
							.foregroundColor(tierColor, adjustedFor: colorScheme)
							.opacity(0.8)
							.lineLimit(1)
						
						Text(statsText)
							.font(.caption2)
							.foregroundStyle(.secondary)
							.lineLimit(2)
							.padding(.top, 2)
					}
				}
				.padding(14)
				.frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
				.background(
					tierColor.opacity(0.22),
					in: RoundedRectangle(cornerRadius: 18, style: .continuous)
				)
				.overlay {
					RoundedRectangle(cornerRadius: 18, style: .continuous)
						.stroke(tierColor.opacity(0.28), lineWidth: 0.75)
				}
			}
			.buttonStyle(.plain)
			.contextMenu {
				Button {
					selectedSkin = skin
				} label: {
					Label("View Details", systemImage: "info.circle")
				}
				Button(role: .destructive) {
					wishlistManager.remove(kind: .skin, itemID: entry.itemID)
				} label: {
					Label("Remove from Wishlist", systemImage: "heart.slash")
				}
			}
			
		case .buddy(let entry, let buddy):
			accessoryCard(
				entry: entry,
				title: buddy.displayName,
				subtitle: "Gun Buddy",
				statsText: statsText,
				image: buddy.displayIcon
			) {
				fullscreenImages = AssetImageCollection(images: [buddy.displayIcon])
			}
			
		case .spray(let entry, let spray):
			accessoryCard(
				entry: entry,
				title: spray.displayName,
				subtitle: "Spray",
				statsText: statsText,
				image: spray.bestIcon
			) {
				selectedExpression = .spray(spray)
			}
			
		case .card(let entry, let card):
			accessoryCard(
				entry: entry,
				title: card.displayName,
				subtitle: "Player Card",
				statsText: statsText,
				image: card.smallArt
			) {
				fullscreenImages = AssetImageCollection(images: [card.largeArt, card.wideArt, card.smallArt])
			}
			
		case .title(let entry, let title):
			accessoryCard(
				entry: entry,
				title: title.titleText ?? title.displayName ?? "Title",
				subtitle: "Player Title",
				statsText: statsText,
				image: nil
			) {}
			
		case .flex(let entry, let flex):
			accessoryCard(
				entry: entry,
				title: flex.displayName,
				subtitle: "Flex",
				statsText: statsText,
				image: flex.displayIcon
			) {
				selectedExpression = .totem(flex)
			}
		}
	}
	
	private func accessoryCard(
		entry: WishlistEntry,
		title: String,
		subtitle: String,
		statsText: String,
		image: AssetImage?,
		onTap: @escaping () -> Void
	) -> some View {
		Button(action: onTap) {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Spacer()
					Button {
						wishlistManager.remove(kind: entry.kind, itemID: entry.itemID)
					} label: {
						Image(systemName: "heart.fill")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(Color.accentColor)
					}
					.buttonStyle(.plain)
				}
				
				Spacer(minLength: 4)
				
				Group {
					if let image {
						image.view()
							.cornerRadius(8)
					} else {
						Image.bundledAsset("Player Title", renderingMode: .template)
							.resizable()
							.scaledToFit()
							.foregroundStyle(.secondary)
					}
				}
				.frame(height: 64)
				.frame(maxWidth: .infinity)
				
				Spacer(minLength: 4)
				
				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)
						.lineLimit(2)
						.multilineTextAlignment(.leading)
					
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
					
					Text(statsText)
						.font(.caption2)
						.foregroundStyle(.secondary)
						.lineLimit(2)
						.padding(.top, 2)
				}
			}
			.padding(14)
			.frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
			.background(
				Color.secondaryGroupedBackground,
				in: RoundedRectangle(cornerRadius: 18, style: .continuous)
			)
		}
		.buttonStyle(.plain)
		.contextMenu {
			Button(role: .destructive) {
				wishlistManager.remove(kind: entry.kind, itemID: entry.itemID)
			} label: {
				Label("Remove from Wishlist", systemImage: "heart.slash")
			}
		}
	}
	
	private func formattedAppearanceText(_ stats: WishlistAppearanceStats) -> String {
		guard stats.count > 0, let lastSeen = stats.lastSeenDate else {
			return "Not in your shop yet"
		}
		let daysAgo = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastSeen), to: Calendar.current.startOfDay(for: Date())).day ?? 0)
		let agoString: String
		if daysAgo == 0 {
			agoString = "today"
		} else if daysAgo == 1 {
			agoString = "1 day ago"
		} else {
			agoString = "\(daysAgo) days ago"
		}
		if stats.count == 1 {
			return "In your shop once · \(agoString)"
		}
		return "In your shop \(stats.count) times · last seen \(agoString)"
	}
	
	@MainActor
	private func checkNow() async {
		guard !isCheckingShop else { return }
		isCheckingShop = true
		checkFeedback = nil
		defer { isCheckingShop = false }
		
		let accounts = accountManager.storedAccounts
		var checkedCount = 0
		var matchedNames: [String] = []
		
		for accountID in accounts {
			guard let client = accountManager.makeReadOnlyClient(for: accountID) else { continue }
			do {
				let storefront = try await client.getStorefront()
				checkedCount += 1
				shopHistoryStore.record(storefront: storefront, for: accountID)
				await StoreNotificationManager.shared.processObservedStorefront(
					storefront,
					for: accountID,
					fetchDate: Date(),
					assets: assets,
					wishlistEntries: wishlistManager.entries,
					isBackground: false
				)
				
				let matches = wishlistManager.matchingDailyOffers(in: storefront, assets: assets)
				for match in matches {
					if !matchedNames.contains(match.skin.displayName) {
						matchedNames.append(match.skin.displayName)
					}
				}
				if let accessoryOffers = storefront.accessoryStore.offers {
					for accOffer in accessoryOffers where wishlistManager.isOfferWishlisted(accOffer.offer, assets: assets) {
						if let name = accessoryTitle(for: accOffer.offer.rewards.first) {
							if !matchedNames.contains(name) {
								matchedNames.append(name)
							}
						}
					}
				}
			} catch {
				print("Wishlist daily check failed for \(accountID):", error)
			}
		}
		
		if checkedCount > 0 {
			shopHistoryStore.recordDailyCheck(accountCount: checkedCount)
			if matchedNames.isEmpty {
				checkFeedback = "Checked \(checkedCount) account\(checkedCount == 1 ? "" : "s") — no wishlist matches in today's shop."
			} else {
				checkFeedback = "Found in today's shop: \(matchedNames.joined(separator: ", "))"
			}
		} else {
			checkFeedback = "Could not connect to Riot Store. Try refreshing your session in Settings."
		}
	}
	
	private func accessoryTitle(for reward: StoreOffer.Reward?) -> String? {
		guard let reward, let assets else { return nil }
		if let buddy = reward.buddy { return assets.resolveBuddy(buddy)?.displayName }
		if let spray = reward.spray { return assets.sprays[spray]?.displayName }
		if let card = reward.card { return assets.playerCards[card]?.displayName }
		if let title = reward.title { return assets.playerTitles[title]?.displayName }
		if let totem = reward.totem { return assets.flex[totem]?.displayName }
		return nil
	}
}

struct WishlistItemPicker: View {
	@EnvironmentObject private var wishlistManager: WishlistManager
	@Environment(\.assets) private var assets
	
	@State private var selectedCategory: WishlistItemKind = .skin
	@State private var search = ""
	@State private var selectedWeaponID: Weapon.ID?
	@State private var cachedBaseKey: BaseKey?
	@State private var cachedBaseItems: [PickerRowItem] = []
	@State private var cachedVisibleItems: [PickerRowItem] = []
	
	private struct BaseKey: Equatable {
		var category: WishlistItemKind
		var assetVersion: AssetVersion?
	}
	
	private struct FilterKey: Equatable {
		var category: WishlistItemKind
		var weaponID: Weapon.ID?
		var search: String
		var assetVersion: AssetVersion?
	}
	
	private struct PickerRowItem: Identifiable {
		enum Target {
			case skin(WeaponSkin.ID, weaponID: Weapon.ID)
			case other(kind: WishlistItemKind, itemID: LowercaseUUID)
		}
		
		let id: String
		let target: Target
		let title: String
		let subtitle: String
		let extraSearchText: String?
		let image: AssetImage?
	}
	
	var body: some View {
		List {
			Section {
				Picker("Category", selection: $selectedCategory) {
					ForEach(WishlistItemKind.allCases, id: \.self) { kind in
						Text(kind.displayName).tag(kind)
					}
				}
				.pickerStyle(.segmented)
				.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
			}
			
			if let assets {
				if selectedCategory == .skin {
					skinFilterSection(assets: assets)
				}
				
				Section {
					ForEach(cachedVisibleItems) { item in
						let wishlisted: Bool = switch item.target {
						case .skin(let skinID, _):
							wishlistManager.contains(skinID)
						case .other(let kind, let itemID):
							wishlistManager.contains(kind: kind, itemID: itemID)
						}
						pickerToggleRow(
							title: item.title,
							subtitle: item.subtitle,
							image: item.image,
							isWishlisted: wishlisted
						) {
							switch item.target {
							case .skin(let skinID, _):
								wishlistManager.toggle(skinID)
							case .other(let kind, let itemID):
								wishlistManager.toggle(kind: kind, itemID: itemID)
							}
						}
					}
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search \(selectedCategory.displayName.lowercased())"))
		.navigationTitle("Add to Wishlist")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: FilterKey(
			category: selectedCategory,
			weaponID: selectedWeaponID,
			search: search,
			assetVersion: assets?.version
		)) {
			rebuildVisibleItems()
		}
	}
	
	private func rebuildVisibleItems() {
		guard let assets else {
			cachedBaseKey = nil
			cachedBaseItems = []
			cachedVisibleItems = []
			return
		}
		
		let baseKey = BaseKey(category: selectedCategory, assetVersion: assets.version)
		let baseItems: [PickerRowItem]
		if cachedBaseKey == baseKey {
			baseItems = cachedBaseItems
		} else {
			baseItems = Self.buildBaseItems(for: selectedCategory, assets: assets)
			cachedBaseKey = baseKey
			cachedBaseItems = baseItems
		}
		
		let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
		let filterWeaponID = (selectedCategory == .skin) ? selectedWeaponID : nil
		if filterWeaponID == nil, query.isEmpty {
			cachedVisibleItems = baseItems
			return
		}
		
		cachedVisibleItems = baseItems.filter { item in
			if let filterWeaponID {
				guard case .skin(_, let weaponID) = item.target, weaponID == filterWeaponID else {
					return false
				}
			}
			guard !query.isEmpty else { return true }
			return item.title.localizedCaseInsensitiveContains(query)
				|| item.subtitle.localizedCaseInsensitiveContains(query)
				|| (item.extraSearchText?.localizedCaseInsensitiveContains(query) == true)
		}
	}
	
	private static func buildBaseItems(for category: WishlistItemKind, assets: AssetCollection) -> [PickerRowItem] {
		switch category {
		case .skin:
			let weapons = Weapon.ID.orderInCollection.compactMap { assets.weapons[$0] }
			return weapons.flatMap { weapon in
				weapon.skins
					.filter { !$0.themeID.isFree }
					.map { skin in
						PickerRowItem(
							id: skin.id.rawID.description,
							target: .skin(skin.id, weaponID: weapon.id),
							title: skin.displayName,
							subtitle: weapon.displayName,
							extraSearchText: nil,
							image: skin.displayIcon ?? skin.levels.first?.displayIcon
						)
					}
			}
			.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
		case .buddy:
			return assets.buddies.values.map { buddy in
				PickerRowItem(
					id: buddy.id.rawID.description,
					target: .other(kind: .buddy, itemID: buddy.id.rawID),
					title: buddy.displayName,
					subtitle: "Gun Buddy",
					extraSearchText: nil,
					image: buddy.displayIcon
				)
			}
			.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
		case .spray:
			return assets.sprays.values.map { spray in
				PickerRowItem(
					id: spray.id.rawID.description,
					target: .other(kind: .spray, itemID: spray.id.rawID),
					title: spray.displayName,
					subtitle: "Spray",
					extraSearchText: nil,
					image: spray.bestIcon
				)
			}
			.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
		case .card:
			return assets.playerCards.values.map { card in
				PickerRowItem(
					id: card.id.rawID.description,
					target: .other(kind: .card, itemID: card.id.rawID),
					title: card.displayName,
					subtitle: "Player Card",
					extraSearchText: nil,
					image: card.smallArt
				)
			}
			.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
		case .title:
			return assets.playerTitles.values
				.filter { $0.displayName?.isEmpty == false }
				.map { title in
					PickerRowItem(
						id: title.id.rawID.description,
						target: .other(kind: .title, itemID: title.id.rawID),
						title: title.titleText ?? title.displayName ?? "Title",
						subtitle: title.displayName ?? "Player Title",
						extraSearchText: title.displayName,
						image: nil
					)
				}
				.sorted { $0.subtitle.localizedCaseInsensitiveCompare($1.subtitle) == .orderedAscending }
		case .flex:
			return assets.flex.values
				.filter { $0.id != .none }
				.map { flex in
					PickerRowItem(
						id: flex.id.rawID.description,
						target: .other(kind: .flex, itemID: flex.id.rawID),
						title: flex.displayName,
						subtitle: "Flex",
						extraSearchText: nil,
						image: flex.displayIcon
					)
				}
				.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
		}
	}
	
	private func skinFilterSection(assets: AssetCollection) -> some View {
		let weapons = Weapon.ID.orderInCollection.compactMap { assets.weapons[$0] }
		return Section {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					filterChip(title: "All", isSelected: selectedWeaponID == nil) {
						selectedWeaponID = nil
					}
					ForEach(weapons) { weapon in
						filterChip(title: weapon.displayName, isSelected: selectedWeaponID == weapon.id) {
							selectedWeaponID = weapon.id
						}
					}
				}
				.padding(.vertical, 4)
			}
			.listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
		}
	}
	
	private func pickerToggleRow(
		title: String,
		subtitle: String,
		image: AssetImage?,
		isWishlisted: Bool,
		toggle: @escaping () -> Void
	) -> some View {
		Button(action: toggle) {
			HStack(spacing: 12) {
				if let image {
					image.view()
						.frame(width: 56, height: 34)
				} else {
					Image.bundledAsset("Player Title", renderingMode: .template)
						.resizable()
						.scaledToFit()
						.foregroundStyle(.secondary)
						.frame(width: 34, height: 34)
				}
				
				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.foregroundStyle(.primary)
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				Image(systemName: isWishlisted ? "heart.fill" : "heart")
					.foregroundStyle(isWishlisted ? Color.accentColor : .secondary)
			}
			.padding(.vertical, 2)
		}
	}
	
	private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.caption.weight(.semibold))
				.padding(.horizontal, 12)
				.padding(.vertical, 6)
				.background(isSelected ? Color.accentColor : Color.secondaryGroupedBackground, in: Capsule())
				.foregroundStyle(isSelected ? .white : .primary)
		}
		.buttonStyle(.plain)
	}
}
