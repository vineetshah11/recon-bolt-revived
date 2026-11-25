import SwiftUI

enum LoadoutItemFilter: String, CaseIterable, Identifiable {
	case all = "All"
	case favoritesAndOwned = "Favorites + Owned"
	case onlyFavorites = "Only Favorites"
	case onlyOwned = "Only Owned"
	case onlyUnowned = "Only Unowned"
	
	var id: String { rawValue }
	
	func matches(isOwned: Bool, isFavorited: Bool, isAlwaysShownFree: Bool = false) -> Bool {
		switch self {
		case .all:
			return true
		case .favoritesAndOwned:
			return isOwned || isFavorited || isAlwaysShownFree
		case .onlyFavorites:
			return isFavorited || isAlwaysShownFree
		case .onlyOwned:
			return isOwned || isAlwaysShownFree
		case .onlyUnowned:
			return !isOwned
		}
	}
}

struct LoadoutPickerFilterMenu: View {
	@Binding var filter: LoadoutItemFilter
	
	private var isFiltered: Bool {
		filter != .all
	}
	
	var body: some View {
		Menu {
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
		} label: {
			ZStack {
				Circle()
					.fill(isFiltered ? Color.accentColor : Color.secondaryGroupedBackground)
					.frame(width: 30, height: 30)
				
				Image(systemName: isFiltered ? "star.fill" : "star")
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(isFiltered ? Color.black : Color.primary)
			}
		}
	}
}

struct LoadoutPickerSearchField: View {
	let prompt: String
	@Binding var text: String
	
	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.font(.subheadline)
				.foregroundStyle(.secondary)
			
			TextField(prompt, text: $text)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
			
			if !text.isEmpty {
				Button {
					text = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 9)
		.background(Color.secondaryGroupedBackground, in: Capsule())
	}
}

struct LoadoutPickerStatsPill: View {
	let total: Int
	let shown: Int
	let favorites: Int
	let owned: Int
	
	var body: some View {
		HStack(spacing: 18) {
			statColumn(value: total, label: "Total", color: .secondary)
			statColumn(value: shown, label: "Shown", color: .primary)
			statColumn(value: favorites, label: "Favorites", color: .yellow)
			statColumn(value: owned, label: "Owned", color: .green)
		}
		.padding(.horizontal, 20)
		.padding(.vertical, 10)
		.background(Color.secondaryGroupedBackground, in: Capsule())
		.frame(maxWidth: .infinity)
	}
	
	private func statColumn(value: Int, label: String, color: Color) -> some View {
		VStack(spacing: 1) {
			Text("\(value)")
				.font(.subheadline.weight(.semibold).monospacedDigit())
				.foregroundStyle(color)
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(minWidth: 44)
	}
}

struct LoadoutActionCircleButton: View {
	let icon: String
	var isActive: Bool = false
	var activeColor: Color = .accentColor
	var isLoading: Bool = false
	var isDisabled: Bool = false
	let action: () -> Void
	
	var body: some View {
		Button(action: action) {
			ZStack {
				Circle()
					.fill(Color.secondaryGroupedBackground)
					.frame(width: 34, height: 34)
				
				if isLoading {
					ProgressView()
						.controlSize(.small)
				} else {
					Image(systemName: icon)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(
							isActive
								? AnyShapeStyle(activeColor)
								: (isDisabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
						)
				}
			}
		}
		.buttonStyle(.plain)
		.disabled(isLoading || isDisabled)
	}
}
