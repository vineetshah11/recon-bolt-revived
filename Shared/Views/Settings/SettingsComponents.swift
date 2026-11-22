import SwiftUI

struct SettingsHeroCard: View {
	let icon: String
	let title: LocalizedStringKey
	let subtitle: LocalizedStringKey
	
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Image(systemName: icon)
				.font(.system(size: 30, weight: .regular))
				.foregroundStyle(.tint)
			
			Text(title)
				.font(.title3.bold())
				.foregroundStyle(.primary)
			
			Text(subtitle)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(18)
		.background(
			Color.secondaryGroupedBackground,
			in: RoundedRectangle(cornerRadius: 20, style: .continuous)
		)
	}
}

struct SettingsCard<Content: View>: View {
	@ViewBuilder var content: Content
	
	var body: some View {
		VStack(spacing: 0) {
			content
		}
		.background(
			Color.secondaryGroupedBackground,
			in: RoundedRectangle(cornerRadius: 18, style: .continuous)
		)
	}
}

struct SettingsSectionHeader: View {
	let title: LocalizedStringKey
	
	init(_ title: LocalizedStringKey) {
		self.title = title
	}
	
	var body: some View {
		Text(title)
			.font(.body.weight(.medium))
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 8)
			.padding(.top, 8)
	}
}

struct SettingsFooter: View {
	let text: LocalizedStringKey
	
	init(_ text: LocalizedStringKey) {
		self.text = text
	}
	
	var body: some View {
		Text(text)
			.font(.footnote)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 10)
	}
}

struct SettingsRowDivider: View {
	var leadingInset: CGFloat = 52
	
	var body: some View {
		Divider()
			.opacity(0.25)
			.padding(.leading, leadingInset)
	}
}

struct SettingsToggleCard: View {
	let icon: String
	let title: LocalizedStringKey
	@Binding var isOn: Bool
	let footer: LocalizedStringKey
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			SettingsCard {
				Toggle(isOn: $isOn) {
					HStack(spacing: 14) {
						Image(systemName: icon)
							.font(.system(size: 18))
							.foregroundStyle(.tint)
							.frame(width: 24)
						
						Text(title)
							.font(.body)
							.foregroundStyle(.primary)
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
			}
			
			SettingsFooter(footer)
		}
	}
}

struct SettingsIconLabel: View {
	let icon: String
	let title: LocalizedStringKey
	var isDestructiveStyle: Bool = false
	var isDisabledAppearance: Bool = false
	
	var body: some View {
		HStack(spacing: 14) {
			Image(systemName: icon)
				.font(.system(size: 18))
				.foregroundStyle(isDisabledAppearance ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
				.frame(width: 24)
			
			Text(title)
				.font(.body)
				.foregroundStyle(isDisabledAppearance ? AnyShapeStyle(.tertiary) : (isDestructiveStyle ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)))
		}
	}
}
