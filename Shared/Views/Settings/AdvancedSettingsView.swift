import SwiftUI

struct AdvancedSettingsView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "slider.horizontal.3",
					title: "Advanced Settings",
					subtitle: "Customize interface behavior, sign-in preferences, and system integration."
				)
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("Categories")
					
					SettingsCard {
						categoryRow(icon: "rectangle.on.rectangle", title: "Interface Settings") {
							InterfaceSettingsView(settings: settings)
						}
						
						SettingsRowDivider()
						
						categoryRow(icon: "person.badge.key", title: "Sign-In Settings") {
							LoginSettingsView(settings: settings)
						}
						
						SettingsRowDivider()
						
						categoryRow(icon: "gearshape.2", title: "System Settings") {
							SystemSettingsView(accountManager: accountManager, assetManager: assetManager)
						}
					}
					
					SettingsFooter("Tap any category to access its specific settings and options.")
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Advanced Settings")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private func categoryRow<Destination: View>(
		icon: String,
		title: LocalizedStringKey,
		@ViewBuilder destination: () -> Destination
	) -> some View {
		NavigationLink {
			destination()
		} label: {
			HStack(spacing: 14) {
				Image(systemName: icon)
					.font(.system(size: 18))
					.foregroundStyle(.tint)
					.frame(width: 24)
				
				Text(title)
					.font(.body)
					.foregroundStyle(.primary)
				
				Spacer()
				
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}
