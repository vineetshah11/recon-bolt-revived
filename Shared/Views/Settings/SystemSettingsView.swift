import SwiftUI
import WidgetKit

struct SystemSettingsView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	
	@EnvironmentObject private var socialManager: SocialManager
	@State private var isRestartingSocial = false
	@State private var didRestartSocial = false
	@State private var didRefreshWidgets = false
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "gearshape.2",
					title: "System",
					subtitle: "Configure language, widgets, and social services integration."
				)
				
				VStack(alignment: .leading, spacing: 10) {
					SettingsCard {
						Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
							HStack(spacing: 14) {
								Image(systemName: "globe")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Change Language")
									.font(.body)
									.foregroundStyle(.primary)
								
								Spacer()
								
								Image(systemName: "arrow.up.right")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 14)
							.contentShape(Rectangle())
						}
					}
					
					VStack(alignment: .leading, spacing: 10) {
						Text("Takes you to the system settings to change the app's language. App language selection is only available if multiple languages are set up on your device. [Learn how to add a language to your device...](https://support.apple.com/en-us/109358)")
							.font(.footnote)
							.foregroundStyle(.secondary)
						
						Text("If you'd like to use a different language for in-game content, independent of the app's language, you can change it in asset management.")
							.font(.footnote)
							.foregroundStyle(.secondary)
						
						NavigationLink {
							AssetsInfoView.LanguagePicker(languageOverride: assetManager.languageOverride) { language in
								await assetManager.setLanguageOverride(to: language)
							}
						} label: {
							Text("Go to Asset Language Settings")
								.font(.footnote.weight(.medium))
								.foregroundStyle(.tint)
						}
					}
					.padding(.horizontal, 10)
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsCard {
						Button {
							isRestartingSocial = true
							Task {
								if let client = accountManager.activeAccount?.client {
									await socialManager.reconnect(using: client, clearExisting: false)
								} else {
									await socialManager.disconnect()
								}
								isRestartingSocial = false
								didRestartSocial = true
							}
						} label: {
							HStack {
								Text("Restart Social Services")
									.font(.body)
									.foregroundStyle(.tint)
								
								Spacer()
								
								if isRestartingSocial {
									ProgressView()
										.controlSize(.small)
								}
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.disabled(isRestartingSocial)
					}
					
					SettingsFooter("Restarting social services reloads your friends list, clears any stalled connections, and restores presence features. If issues persist, e.g. friends won't load, you're stuck on a loading screen, try quitting and reopening the app or checking your network connection.")
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsCard {
						Button {
							WidgetCenter.shared.reloadAllTimelines()
							didRefreshWidgets = true
						} label: {
							HStack {
								Text("Force Refresh Widgets")
									.font(.body)
									.foregroundStyle(.tint)
								Spacer()
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
					
					SettingsFooter("If your widgets appear to be malfunctioning, click this button to request an immediate refresh from iOS.")
					
					HStack(alignment: .top, spacing: 10) {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
							.font(.subheadline)
						Text("Widgets are not included in this build and could not be tested without a paid Apple Developer account. They will not work without one (App Groups and multiple extensions require a paid account).")
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
					.padding(12)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsCard {
						NavigationLink {
							NotificationDiagnosticsView(
								accountManager: accountManager,
								assetManager: assetManager,
								settings: settings
							)
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "bell.and.waves.left.and.right")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Notification Testing & Diagnostics")
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
					
					SettingsFooter("Preview store notification banners, trigger timed test notifications, run a live store check, or inspect scheduled iOS alerts.")
				}
				
				if let activeAccount = accountManager.activeAccount {
					SettingsCard {
						NavigationLink {
							ClientLogView(client: activeAccount.client)
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "doc.text.magnifyingglass")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Request Log")
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
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("System")
		.navigationBarTitleDisplayMode(.inline)
		.alert("Social Services Restarted", isPresented: $didRestartSocial) {
			Button("OK", role: .cancel) {}
		} message: {
			Text("Your friends list and chat connection have been refreshed.")
		}
		.alert("Widget Refresh Requested", isPresented: $didRefreshWidgets) {
			Button("OK", role: .cancel) {}
		} message: {
			Text("iOS is a bit finnicky about this, so widgets may not refresh right away—feel free to reboot your device if this doesn't help!")
		}
	}
}
