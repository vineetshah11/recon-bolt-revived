import SwiftUI

struct InterfaceSettingsView: View {
	@ObservedObject var settings: AppSettings
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "rectangle.on.rectangle",
					title: "Interface",
					subtitle: "Control how the app responds to your interactions and displays content."
				)
				
				SettingsToggleCard(
					icon: "arrow.up.right.square",
					title: "Auto-open match details",
					isOn: $settings.autoOpenMatchDetails,
					footer: "Automatically opens the match details screen when a match is found, without requiring you to tap on it."
				)
				
				SettingsToggleCard(
					icon: "bell",
					title: "Vibrate when Match Found",
					isOn: $settings.vibrateOnMatchFound,
					footer: "Play a subtle haptic vibration when a match is found."
				)
				
				SettingsToggleCard(
					icon: "rectangle.compress.vertical",
					title: "Compact List Style",
					isOn: $settings.isCompactListStyle,
					footer: "Show list items without spacing to fit more on screen, or with spacing for easier reading."
				)
				
				SettingsToggleCard(
					icon: "arrow.down.circle",
					title: "Auto-Download Matches",
					isOn: $settings.autoDownloadMatches,
					footer: "Automatically download match details while scrolling through your match list. Disable to reduce excessive requests."
				)
				
				SettingsToggleCard(
					icon: "doc.on.doc",
					title: "Copy Player Names",
					isOn: $settings.copyPlayerNames,
					footer: "Allow tapping on player names to copy them to the clipboard. Some player names are always copyable regardless of this setting."
				)
				
				SettingsToggleCard(
					icon: "person.crop.circle",
					title: "Open Profile Directly",
					isOn: $settings.openProfileDirectly,
					footer: "When enabled, tapping a friend opens their profile instead of the chat. This is ignored for friends with unread messages."
				)
				
				SettingsToggleCard(
					icon: "clock.arrow.circlepath",
					title: "Sort Offline by Last Seen",
					isOn: $settings.sortOfflineByLastSeen,
					footer: "Sort offline friends by when they were last online, with most recent at the top. When disabled, offline friends are sorted alphabetically."
				)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Interface")
		.navigationBarTitleDisplayMode(.inline)
	}
}
