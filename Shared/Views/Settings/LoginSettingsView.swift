import SwiftUI

struct LoginSettingsView: View {
	@ObservedObject var settings: AppSettings
	@State private var isClearingNow = false
	@State private var didClearNow = false
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "person.badge.key",
					title: "Web Sign-In Data",
					subtitle: "Website data from sign-in pages is saved to streamline authentication with services like PlayStation Network. Clear this data to switch accounts or resolve sign-in issues."
				)
				
				SettingsToggleCard(
					icon: "arrow.3.trianglepath",
					title: "Clear Web Sign-In Data on Open",
					isOn: $settings.clearWebSignInDataOnOpen,
					footer: "When enabled, Recon Bolt clears cookies and other website data (like local and session storage) each time you open the sign-in screen. This helps when switching third-party accounts or fixing sign-in issues. It doesn't remove your Recon Bolt accounts and doesn't sign you out."
				)
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsCard {
						Button {
							isClearingNow = true
							Task {
								await RiotLoginWebViewModel.clearAllWebsiteData()
								isClearingNow = false
								didClearNow = true
							}
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "trash")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Clear Web Sign-In Data Now")
									.font(.body)
									.foregroundStyle(.tint)
								
								Spacer()
								
								if isClearingNow {
									ProgressView()
										.controlSize(.small)
								}
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.disabled(isClearingNow)
					}
					
					SettingsFooter("Removes saved website data immediately. Use this if a sign-in page can't connect or if you want to switch to a different third-party account. Recon Bolt accounts are unaffected.")
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Web Sign-In Data")
		.navigationBarTitleDisplayMode(.inline)
		.alert("Web Sign-In Data Cleared", isPresented: $didClearNow) {
			Button("OK", role: .cancel) {}
		} message: {
			Text("Saved cookies and website data for Riot sign-in pages have been removed. Your Recon Bolt accounts are unaffected.")
		}
	}
}
