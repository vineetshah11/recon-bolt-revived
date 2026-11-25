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
	
	private var resolvedItems: [ResolvedWishlistItem] {
		guard let assets else { return [] }
		let allWeapons = Array(assets.weapons.values)
		return wishlistManager.entries.compactMap { entry in
			switch entry.kind {
			case .skin:
				for weapon in allWeapons {
					if let skin = weapon.skins.first(where: { $0.id == entry.skinID }) {
						return .skin(entry: entry, skin: skin, weapon: weapon)
					}
				}
				return nil
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
				
				if resolvedItems.isEmpty {
					emptyStateCard
				} else {
					LazyVGrid(columns: columns, spacing: 12) {
						ForEach(resolvedItems) { item in
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
					
					image?.view(preferFullResolution: true)
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
						image.view(preferFullResolution: true)
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
				switch selectedCategory {
				case .skin:
					skinRows(assets: assets)
				case .buddy:
					buddyRows(assets: assets)
				case .spray:
					sprayRows(assets: assets)
				case .card:
					cardRows(assets: assets)
				case .title:
					titleRows(assets: assets)
				case .flex:
					flexRows(assets: assets)
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search \(selectedCategory.displayName.lowercased())"))
		.navigationTitle("Add to Wishlist")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	@ViewBuilder
	private func skinRows(assets: AssetCollection) -> some View {
		let weapons = Weapon.ID.orderInCollection.compactMap { assets.weapons[$0] }
		Section {
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
		
		let matchingSkins: [(weapon: WeaponInfo, skin: WeaponSkin)] = weapons
			.filter { selectedWeaponID == nil || $0.id == selectedWeaponID }
			.flatMap { weapon in
				weapon.skins
					.filter { !$0.themeID.isFree }
					.map { (weapon, $0) }
			}
			.filter { search.isEmpty || $0.skin.displayName.localizedCaseInsensitiveContains(search) || $0.weapon.displayName.localizedCaseInsensitiveContains(search) }
			.sorted { $0.skin.displayName.localizedCaseInsensitiveCompare($1.skin.displayName) == .orderedAscending }
		
		Section {
			ForEach(matchingSkins, id: \.skin.id) { item in
				let wishlisted = wishlistManager.contains(item.skin.id)
				pickerToggleRow(
					title: item.skin.displayName,
					subtitle: item.weapon.displayName,
					image: item.skin.displayIcon ?? item.skin.levels.first?.displayIcon,
					isWishlisted: wishlisted
				) {
					wishlistManager.toggle(item.skin.id)
				}
			}
		}
	}
	
	private func buddyRows(assets: AssetCollection) -> some View {
		let items = Array(assets.buddies.values)
			.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		return Section {
			ForEach(items) { buddy in
				pickerToggleRow(
					title: buddy.displayName,
					subtitle: "Gun Buddy",
					image: buddy.displayIcon,
					isWishlisted: wishlistManager.contains(kind: .buddy, itemID: buddy.id.rawID)
				) {
					wishlistManager.toggle(kind: .buddy, itemID: buddy.id.rawID)
				}
			}
		}
	}
	
	private func sprayRows(assets: AssetCollection) -> some View {
		let items = Array(assets.sprays.values)
			.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		return Section {
			ForEach(items) { spray in
				pickerToggleRow(
					title: spray.displayName,
					subtitle: "Spray",
					image: spray.bestIcon,
					isWishlisted: wishlistManager.contains(kind: .spray, itemID: spray.id.rawID)
				) {
					wishlistManager.toggle(kind: .spray, itemID: spray.id.rawID)
				}
			}
		}
	}
	
	private func cardRows(assets: AssetCollection) -> some View {
		let items = Array(assets.playerCards.values)
			.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		return Section {
			ForEach(items) { card in
				pickerToggleRow(
					title: card.displayName,
					subtitle: "Player Card",
					image: card.smallArt,
					isWishlisted: wishlistManager.contains(kind: .card, itemID: card.id.rawID)
				) {
					wishlistManager.toggle(kind: .card, itemID: card.id.rawID)
				}
			}
		}
	}
	
	private func titleRows(assets: AssetCollection) -> some View {
		let items = Array(assets.playerTitles.values)
			.filter { ($0.displayName?.isEmpty == false) }
			.filter { search.isEmpty || ($0.displayName ?? "").localizedCaseInsensitiveContains(search) || ($0.titleText ?? "").localizedCaseInsensitiveContains(search) }
			.sorted { ($0.displayName ?? "").localizedCaseInsensitiveCompare($1.displayName ?? "") == .orderedAscending }
		return Section {
			ForEach(items) { title in
				pickerToggleRow(
					title: title.titleText ?? title.displayName ?? "Title",
					subtitle: title.displayName ?? "Player Title",
					image: nil,
					isWishlisted: wishlistManager.contains(kind: .title, itemID: title.id.rawID)
				) {
					wishlistManager.toggle(kind: .title, itemID: title.id.rawID)
				}
			}
		}
	}
	
	private func flexRows(assets: AssetCollection) -> some View {
		let items = Array(assets.flex.values)
			.filter { $0.id != .none }
			.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		return Section {
			ForEach(items) { flex in
				pickerToggleRow(
					title: flex.displayName,
					subtitle: "Flex",
					image: flex.displayIcon,
					isWishlisted: wishlistManager.contains(kind: .flex, itemID: flex.id.rawID)
				) {
					wishlistManager.toggle(kind: .flex, itemID: flex.id.rawID)
				}
			}
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
