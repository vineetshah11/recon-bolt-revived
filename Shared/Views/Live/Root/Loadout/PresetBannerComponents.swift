import SwiftUI
import PhotosUI
import UIKit
import ValorantAPI

enum PresetBannerChoice: Equatable {
	case none
	case card(PlayerCard.ID)
	case image(Data)
	
	init(cardID: PlayerCard.ID?, imageData: Data?) {
		if let imageData {
			self = .image(imageData)
		} else if let cardID {
			self = .card(cardID)
		} else {
			self = .none
		}
	}
}

struct PresetThumbnailView: View {
	var bannerCardID: PlayerCard.ID?
	var bannerImageData: Data?
	var fallbackIcon: String
	var size: CGFloat = 46
	var cornerRadius: CGFloat = 10
	
	var body: some View {
		Group {
			if let bannerImageData, let uiImage = UIImage(data: bannerImageData) {
				Image(uiImage: uiImage)
					.resizable()
					.aspectRatio(contentMode: .fill)
			} else if let bannerCardID {
				PlayerCardImage.small(bannerCardID)
					.aspectRatio(contentMode: .fill)
			} else {
				ZStack {
					Color.accentColor.opacity(0.18)
					Image(systemName: fallbackIcon)
						.font(.system(size: size * 0.44, weight: .semibold))
						.foregroundStyle(Color.accentColor)
				}
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
	}
}

struct PresetBannerPickerSheet: View {
	enum BannerCardSort: String, CaseIterable, Identifiable {
		case ownedFirst = "Owned First"
		case nameAsc = "Name (A–Z)"
		case nameDesc = "Name (Z–A)"
		
		var id: String { rawValue }
	}
	
	let currentSelection: PresetBannerChoice
	var equippedCardID: PlayerCard.ID?
	var inventory: Inventory
	var accountID: User.ID? = nil
	let onSelect: (PresetBannerChoice) -> Void
	
	@EnvironmentObject private var favoritesManager: FavoritesManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var search = ""
	@State private var filter: LoadoutItemFilter = .all
	@State private var sort: BannerCardSort = .ownedFirst
	@State private var pickedPhotoItem: PhotosPickerItem?
	@State private var isProcessingPhoto = false
	@State private var photoError: String?
	
	private var hasCustomControlsActive: Bool {
		filter != .all || sort != .ownedFirst
	}
	
	private var filteredCards: [PlayerCardInfo] {
		guard let assets else { return [] }
		let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
		let allCards = Array(assets.playerCards.values)
		
		let matching = allCards.filter { card in
			if !query.isEmpty && !card.displayName.localizedCaseInsensitiveContains(query) {
				return false
			}
			let isOwned = inventory.cards.contains(card.id)
			let isFavorited = favoritesManager.isFavorited(card.id.rawID, for: accountID)
			return filter.matches(isOwned: isOwned, isFavorited: isFavorited)
		}
		
		return matching.sorted { lhs, rhs in
			switch sort {
			case .ownedFirst:
				let lhsOwned = inventory.cards.contains(lhs.id)
				let rhsOwned = inventory.cards.contains(rhs.id)
				if lhsOwned != rhsOwned {
					return lhsOwned
				}
				return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
			case .nameAsc:
				return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
			case .nameDesc:
				return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedDescending
			}
		}
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 16) {
					searchAndSortBar
					
					optionsCard
					
					if assets != nil {
						VStack(alignment: .leading, spacing: 10) {
							HStack {
								Text("Player Cards")
									.font(.subheadline.weight(.medium))
									.foregroundStyle(.secondary)
								Spacer()
								Text("\(filteredCards.count) shown")
									.font(.caption.monospacedDigit())
									.foregroundStyle(.secondary)
							}
							.padding(.horizontal, 4)
							
							if filteredCards.isEmpty {
								Text("No player cards match your search or filter.")
									.font(.subheadline)
									.foregroundStyle(.secondary)
									.frame(maxWidth: .infinity, alignment: .center)
									.padding(.vertical, 24)
							} else {
								LazyVGrid(
									columns: [
										GridItem(.flexible(), spacing: 10),
										GridItem(.flexible(), spacing: 10),
										GridItem(.flexible(), spacing: 10),
									],
									spacing: 10
								) {
									ForEach(filteredCards, id: \.id) { card in
										let isSelected = (currentSelection == .card(card.id))
										let isOwned = inventory.cards.contains(card.id)
										let isFavorited = favoritesManager.isFavorited(card.id.rawID, for: accountID)
										
										Button {
											onSelect(.card(card.id))
											dismiss()
										} label: {
											VStack(spacing: 6) {
												PlayerCardImage.small(card.id)
													.aspectRatio(1, contentMode: .fill)
													.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
													.overlay {
														if isSelected {
															RoundedRectangle(cornerRadius: 10, style: .continuous)
																.stroke(Color.accentColor, lineWidth: 2.5)
														}
													}
													.overlay(alignment: .topTrailing) {
														if isFavorited || isOwned {
															HStack(spacing: 2) {
																if isFavorited {
																	Image(systemName: "star.fill")
																		.foregroundStyle(.yellow)
																}
																if isOwned {
																	Image(systemName: "checkmark.circle.fill")
																		.foregroundStyle(.green)
																}
															}
															.font(.system(size: 10, weight: .bold))
															.padding(4)
															.background(.black.opacity(0.6), in: Capsule())
															.padding(4)
														}
													}
												
												Text(card.displayName)
													.font(.caption2)
													.foregroundStyle(isSelected ? Color.accentColor : .secondary)
													.lineLimit(1)
											}
										}
										.buttonStyle(.plain)
									}
								}
							}
						}
					}
				}
				.padding(16)
			}
			.background(Color.groupedBackground.ignoresSafeArea())
			.navigationTitle("Choose Banner")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
			.onChange(of: pickedPhotoItem) { newItem in
				guard let newItem else { return }
				Task {
					await loadCustomPhoto(from: newItem)
				}
			}
			.alert(
				"Could Not Load Image",
				isPresented: Binding(
					get: { photoError != nil },
					set: { if !$0 { photoError = nil } }
				)
			) {
				Button("OK", role: .cancel) {}
			} message: {
				if let photoError {
					Text(photoError)
				}
			}
		}
	}
	
	private var searchAndSortBar: some View {
		HStack(spacing: 8) {
			LoadoutPickerSearchField(prompt: "Search player cards", text: $search)
			
			Menu {
				Section("Filter") {
					ForEach(LoadoutItemFilter.allCases) { option in
						Button {
							filter = option
						} label: {
							HStack {
								Text(option.rawValue)
								if filter == option {
									Image(systemName: "checkmark")
								}
							}
						}
					}
				}
				
				Section("Sort") {
					ForEach(BannerCardSort.allCases) { option in
						Button {
							sort = option
						} label: {
							HStack {
								Text(option.rawValue)
								if sort == option {
									Image(systemName: "checkmark")
								}
							}
						}
					}
				}
			} label: {
				ZStack {
					Circle()
						.fill(hasCustomControlsActive ? Color.accentColor : Color.secondaryGroupedBackground)
						.frame(width: 38, height: 38)
					
					Image(systemName: "line.3.horizontal.decrease")
						.font(.system(size: 14, weight: .semibold))
						.foregroundStyle(hasCustomControlsActive ? Color.black : Color.primary)
				}
			}
			.accessibilityLabel("Filter and Sort Player Cards")
		}
	}
	
	private var optionsCard: some View {
		let isNoneSelected: Bool = {
			if case .none = currentSelection { return true }
			return false
		}()
		let isImageSelected: Bool = {
			if case .image = currentSelection { return true }
			return false
		}()
		let isEquippedSelected: Bool = {
			guard let equippedCardID else { return false }
			return currentSelection == .card(equippedCardID)
		}()
		
		return VStack(spacing: 0) {
			Button {
				onSelect(.none)
				dismiss()
			} label: {
				optionRow(
					icon: "nosign",
					tint: .secondary,
					title: "No Banner (Default Icon)",
					isSelected: isNoneSelected
				)
			}
			.buttonStyle(.plain)
			
			Divider().padding(.leading, 48).opacity(0.25)
			
			PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
				HStack(spacing: 12) {
					Image(systemName: "photo.on.rectangle")
						.font(.body.weight(.semibold))
						.foregroundStyle(Color.accentColor)
						.frame(width: 24)
					Text("Choose Custom Photo")
						.font(.body)
						.foregroundStyle(.primary)
					Spacer()
					if isProcessingPhoto {
						ProgressView()
							.controlSize(.small)
					} else if isImageSelected {
						Image(systemName: "checkmark")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(Color.accentColor)
					}
				}
				.padding(.horizontal, 14)
				.padding(.vertical, 13)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			
			if let equippedCardID {
				Divider().padding(.leading, 48).opacity(0.25)
				
				Button {
					onSelect(.card(equippedCardID))
					dismiss()
				} label: {
					optionRow(
						icon: "person.crop.rectangle",
						tint: .accentColor,
						title: "Use Equipped Player Card",
						isSelected: isEquippedSelected
					)
				}
				.buttonStyle(.plain)
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func optionRow(
		icon: String,
		tint: Color,
		title: LocalizedStringKey,
		isSelected: Bool
	) -> some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.font(.body.weight(.semibold))
				.foregroundStyle(tint)
				.frame(width: 24)
			Text(title)
				.font(.body)
				.foregroundStyle(.primary)
			Spacer()
			if isSelected {
				Image(systemName: "checkmark")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(Color.accentColor)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 13)
		.contentShape(Rectangle())
	}
	
	@MainActor
	private func loadCustomPhoto(from item: PhotosPickerItem) async {
		isProcessingPhoto = true
		defer {
			isProcessingPhoto = false
			pickedPhotoItem = nil
		}
		do {
			guard let rawData = try await item.loadTransferable(type: Data.self),
				  let source = UIImage(data: rawData),
				  let compressed = Self.downscaledJPEGData(from: source) else {
				photoError = "Unsupported image format."
				return
			}
			onSelect(.image(compressed))
			dismiss()
		} catch {
			photoError = error.localizedDescription
		}
	}
	
	private static func downscaledJPEGData(from image: UIImage) -> Data? {
		let maxDimension: CGFloat = 256
		let originalSize = image.size
		guard originalSize.width > 0, originalSize.height > 0 else { return nil }
		
		let scale = min(1, maxDimension / max(originalSize.width, originalSize.height))
		let targetSize = CGSize(
			width: max(1, (originalSize.width * scale).rounded()),
			height: max(1, (originalSize.height * scale).rounded())
		)
		
		let format = UIGraphicsImageRendererFormat.default()
		format.scale = 1
		let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
		let resized = renderer.image { _ in
			image.draw(in: CGRect(origin: .zero, size: targetSize))
		}
		return resized.jpegData(compressionQuality: 0.78)
	}
}
