import SwiftUI
import ValorantAPI

struct ShopHistoryView: View {
	@EnvironmentObject private var shopHistoryStore: ShopHistoryStore
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var wishlistManager: WishlistManager
	@Environment(\.assets) private var assets
	@Environment(\.colorScheme) private var colorScheme
	
	@State private var search = ""
	@State private var showAllFrequencies = false
	@State private var selectedSkin: WeaponSkin?
	
	private var gridColumns: [GridItem] {
		[
			GridItem(.flexible(), spacing: 10),
			GridItem(.flexible(), spacing: 10),
		]
	}
	
	var body: some View {
		let history = shopHistoryStore.days(for: accountManager.activeAccount?.id)
		let filtered = history.filter { day in
			guard !search.isEmpty else { return true }
			return day.offerSkinLevelIDs.contains { level in
				guard let resolved = assets?.resolveSkin(level) else { return false }
				return resolved.skin.displayName.localizedCaseInsensitiveContains(search)
					|| resolved.weapon.displayName.localizedCaseInsensitiveContains(search)
			}
		}
		let frequencies = shopHistoryStore.skinFrequencies(for: accountManager.activeAccount?.id, assets: assets)
			.filter { stat in
				search.isEmpty
					|| stat.skin.displayName.localizedCaseInsensitiveContains(search)
					|| stat.weapon.displayName.localizedCaseInsensitiveContains(search)
			}
		
		ScrollView {
			VStack(spacing: 16) {
				if history.isEmpty {
					emptyStateCard
				} else {
					summaryCard(history: history)
					
					if search.isEmpty, let latest = history.first {
						currentShopCard(day: latest)
					}
					
					if !frequencies.isEmpty {
						frequencyCard(frequencies: frequencies)
					}
					
					let olderDays = search.isEmpty ? Array(filtered.dropFirst()) : filtered
					if !olderDays.isEmpty {
						pastRotationsSection(days: olderDays)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.searchable(text: $search, prompt: Text("Search past offers"))
		.navigationTitle("Shop History")
		.navigationBarTitleDisplayMode(.inline)
		.navigationDestination(isPresented: Binding(
			get: { selectedSkin != nil },
			set: { if !$0 { selectedSkin = nil } }
		)) {
			if let selectedSkin {
				SkinDetailsView(skin: selectedSkin)
			}
		}
	}
	
	private var emptyStateCard: some View {
		VStack(spacing: 10) {
			Image(systemName: "clock.arrow.circlepath")
				.font(.system(size: 36))
				.foregroundStyle(Color.accentColor)
			Text("No Shop History Yet")
				.font(.headline)
			Text("Each time you check your Daily Store in Recon Bolt, today's 4 offers are archived here automatically.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(24)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func summaryCard(history: [ShopHistoryDay]) -> some View {
		let nightMarketCount = history.count { !($0.nightMarketLevelIDs ?? []).isEmpty }
		let firstDate = history.last?.date
		
		return VStack(alignment: .leading, spacing: 4) {
			Text("\(history.count) shop\(history.count == 1 ? "" : "s") recorded")
				.font(.title2.bold())
				.foregroundStyle(.primary)
			
			if let firstDate {
				let sinceText = "Since \(firstDate.formatted(.dateTime.day().month(.wide))) · \(history.count) daily"
				Text(nightMarketCount > 0 ? "\(sinceText) · \(nightMarketCount) night market" : sinceText)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func currentShopCard(day: ShopHistoryDay) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Current Shop")
						.font(.headline)
					Text("Daily Offers")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				if let remaining = day.dailyRemainingDuration {
					let expiry = day.date.addingTimeInterval(remaining)
					if expiry > Date() {
						let hoursLeft = max(1, Int(ceil(expiry.timeIntervalSinceNow / Double(3600))))
						Label("Ends in \(hoursLeft) hr\(hoursLeft == 1 ? "" : "s")", systemImage: "clock")
							.font(.caption.weight(.medium))
							.foregroundStyle(.secondary)
					} else {
						Text(day.date.formatted(date: .abbreviated, time: .omitted))
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
			
			LazyVGrid(columns: gridColumns, spacing: 10) {
				ForEach(day.offerSkinLevelIDs, id: \.self) { levelID in
					if let resolved = assets?.resolveSkin(levelID) {
						shopTile(resolved: resolved)
					}
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func shopTile(resolved: ResolvedLevel) -> some View {
		let tier = resolved.skin.contentTierID.flatMap { assets?.contentTiers[$0] }
		let tierColor = tier?.color?.opaque() ?? .accentColor
		let isWishlisted = wishlistManager.contains(resolved.skin.id)
		let image = resolved.skin.chromas.first?.fullRender ?? resolved.displayIcon
		
		return Button {
			selectedSkin = resolved.skin
		} label: {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					tier?.displayIcon.view()
						.frame(width: 16, height: 16)
					Spacer()
					if isWishlisted {
						Image(systemName: "heart.fill")
							.font(.caption.bold())
							.foregroundColor(tierColor, adjustedFor: colorScheme)
					}
				}
				
				image?.view(preferFullResolution: true)
					.frame(height: 52)
					.frame(maxWidth: .infinity)
				
				Text(resolved.skin.displayName)
					.font(.caption.weight(.semibold))
					.foregroundColor(tierColor, adjustedFor: colorScheme)
					.lineLimit(2)
					.multilineTextAlignment(.leading)
			}
			.padding(12)
			.frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
			.background(
				tierColor.opacity(0.22),
				in: RoundedRectangle(cornerRadius: 14, style: .continuous)
			)
		}
		.buttonStyle(.plain)
	}
	
	private func frequencyCard(frequencies: [SkinFrequencyStat]) -> some View {
		let displayed = showAllFrequencies ? frequencies : Array(frequencies.prefix(6))
		
		return VStack(spacing: 0) {
			ForEach(Array(displayed.enumerated()), id: \.element.id) { index, stat in
				Button {
					selectedSkin = stat.skin
				} label: {
					HStack(spacing: 12) {
						(stat.skin.chromas.first?.fullRender ?? stat.skin.displayIcon ?? stat.skin.levels.first?.displayIcon)?
							.view()
							.frame(width: 54, height: 28)
						
						VStack(alignment: .leading, spacing: 2) {
							HStack(spacing: 5) {
								if wishlistManager.contains(stat.skin.id) {
									Image(systemName: "heart.fill")
										.font(.caption2)
										.foregroundStyle(.yellow)
								}
								Text(stat.skin.displayName)
									.font(.subheadline.weight(.medium))
									.foregroundStyle(.primary)
									.lineLimit(1)
							}
							
							if let avgDays = stat.averageIntervalDays {
								Text("Usually every \(avgDays) day\(avgDays == 1 ? "" : "s")")
									.font(.caption)
									.foregroundStyle(.secondary)
							} else {
								Text(stat.weapon.displayName)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						
						Spacer(minLength: 8)
						
						VStack(alignment: .trailing, spacing: 2) {
							Text("\(stat.count)×")
								.font(.subheadline.weight(.semibold).monospacedDigit())
								.foregroundStyle(.primary)
							
							Text(relativeDayLabel(for: stat.lastSeenDate))
								.font(.caption2)
								.foregroundStyle(.secondary)
						}
					}
					.padding(.horizontal, 16)
					.padding(.vertical, 12)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				
				if index < displayed.count - 1 {
					Divider()
						.opacity(0.25)
						.padding(.leading, 82)
				}
			}
			
			if frequencies.count > 6 {
				Divider()
					.opacity(0.25)
				Button {
					withAnimation(.easeInOut(duration: 0.2)) {
						showAllFrequencies.toggle()
					}
				} label: {
					Text(showAllFrequencies ? "Show Fewer" : "Show All \(frequencies.count) Seen Skins")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.tint)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 12)
				}
				.buttonStyle(.plain)
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func pastRotationsSection(days: [ShopHistoryDay]) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Past Rotations")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 6)
			
			ForEach(days) { day in
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Text(day.date.formatted(date: .complete, time: .omitted))
							.font(.subheadline.weight(.semibold))
						Spacer()
						if let nm = day.nightMarketLevelIDs, !nm.isEmpty {
							Text("Night Market")
								.font(.caption2.weight(.semibold))
								.foregroundStyle(Color.accentColor)
								.padding(.horizontal, 8)
								.padding(.vertical, 3)
								.background(Color.accentColor.opacity(0.15), in: Capsule())
						}
					}
					
					LazyVGrid(columns: gridColumns, spacing: 10) {
						ForEach(day.offerSkinLevelIDs, id: \.self) { levelID in
							if let resolved = assets?.resolveSkin(levelID) {
								shopTile(resolved: resolved)
							}
						}
					}
				}
				.padding(14)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	private func relativeDayLabel(for date: Date) -> String {
		let cal = Calendar.current
		if cal.isDateInToday(date) { return "Today" }
		if cal.isDateInYesterday(date) { return "Yesterday" }
		let days = max(2, cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 2)
		return "\(days) days ago"
	}
}
