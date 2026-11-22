import SwiftUI
import ValorantAPI
import WidgetKit

struct SettingsView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	@ObservedObject var store: InAppStore
	
	@StateObject var iconManager = AppIconManager()
	/// Lives outside the `Form` so re-renders of the list (e.g. on scene activation) can never recreate the login sheet.
	@State private var loginTarget: AccountSettingsView.LoginTarget?
	@StateObject private var loginWebViewModel = RiotLoginWebViewModel()
	
	@Namespace private var storefrontID
	
	var body: some View {
		ScrollViewReader { scrollView in
			Form {
				AccountSettingsView(accountManager: accountManager, loginTarget: $loginTarget)
				
				Section(header: Text("Settings", comment: "Settings: section")) {
					mainSettings()
					
					NavigationLink {
						AdvancedSettingsView(accountManager: accountManager, assetManager: assetManager)
					} label: {
						Label("Advanced Settings", systemImage: "gearshape.2")
					}
				}
				
				Section {
					Toggle(isOn: Binding(
						get: { settings.instalockEnabled },
						set: { settings.instalockEnabled = $0 }
					)) {
						Label {
							Text("Instalock Agent", comment: "Settings: toggle that automatically locks a chosen agent during agent select")
						} icon: {
							Image(systemName: "bolt.fill")
						}
					}

					NavigationLink {
						InstalockAgentPicker(settings: settings, accountManager: accountManager)
					} label: {
						Label {
							HStack {
								Text("Agent to Instalock", comment: "Settings: picker for the agent that gets locked in")
								Spacer()
								Text(instalockAgentName)
									.foregroundStyle(.secondary)
							}
						} icon: {
							Image(systemName: "person.fill.viewfinder")
						}
					}
					.disabled(!settings.instalockEnabled)
				} header: {
					Text("Agent Select", comment: "Settings: section for agent select features")
				} footer: {
					Text("When enabled, Vantage locks in the chosen agent as soon as Agent Select starts. This only works while the Agent Select screen is open (turn on auto-show for live matches to make it automatic), and only for agents you own.", comment: "Settings: instalock explanation")
				}

				Section(String(localized: "In-App Store", defaultValue: "Store", comment: "Settings: section")) {
					InAppStorefront(store: store)
						.id(storefrontID)
				}
				
				Section(header: Text("About", comment: "Settings: section")) {
					NavigationLink {
						AboutScreen()
					} label: {
						Label("About Vantage", systemImage: "questionmark")
					}
				}
			}
			.deepLinkHandler { deepLink in
				guard case .inApp(.storefront) = deepLink else { return }
				withAnimation {
					scrollView.scrollTo(storefrontID, anchor: .center)
				}
			}
		}
		.sheet(item: $loginTarget) { _ in
			LoginForm(accountManager: accountManager, webViewModel: loginWebViewModel)
				.withLoadErrorAlerts()
		}
		.onChange(of: loginTarget) { target in
			// fresh Riot login page only when a new sign-in starts, never on app/scene re-activation
			if target != nil { loginWebViewModel.startNewSession() }
		}
		.navigationTitle("Settings")
	}
	
	@ViewBuilder
	func mainSettings() -> some View {
		Picker(selection: $settings.theme) {
			ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
				theme.name
					.tag(theme)
			}
		} label: {
			Label {
				Text("Theme", comment: "Settings: picker")
			} icon: {
				Image(systemName: "sun.max")
			}
		}
		
		NavigationLink {
			AppIconPicker(manager: iconManager)
		} label: {
			Label {
				HStack {
					Text("App Icon", comment: "Settings: button")
					Spacer()
					iconManager.currentIcon.name
						.foregroundStyle(.secondary)
				}
			} icon: {
				Image(systemName: "square.dashed")
			}
		}
		
		Toggle(isOn: $settings.vibrateOnMatchFound) {
			Label {
				Text("Vibrate when Match Found", comment: "Settings: toggle")
			} icon: {
				Image(systemName: "bell")
			}
		}
		
		Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
			NavigationLink {} label: { // i just want the chevron lol
				Label {
					HStack {
						Text("Change Language", comment: "Settings: button")
						Spacer()
						Image(systemName: "link")
							.foregroundStyle(.secondary)
					}
				} icon: {
					Image(systemName: "globe")
				}
			}
			.tint(.primary)
		}
	}

	var instalockAgentName: String {
		guard let id = settings.instalockAgent else {
			return String(localized: "Not Selected", comment: "Instalock Agent: no agent chosen")
		}
		return assetManager.assets?.agents[id]?.displayName
			?? String(localized: "Unknown Agent", comment: "placeholder")
	}
}

private struct InstalockAgentPicker: View {
	@ObservedObject var settings: AppSettings
	@ObservedObject var accountManager: AccountManager

	@State private var inventory: Inventory?
	@State private var selection: Agent.ID?

	var body: some View {
		AssetsUnwrappingView { assets in
			let agents = assets.agents.filter { $0.value.isPlayableCharacter }
			let owned = inventory?.agents ?? Set(agents.keys)

			SearchableAssetPicker(
				allItems: agents,
				ownedItems: owned
			) { agent in
				SelectableRow(selection: $selection, item: agent.id) {
					agent.displayIcon.view()
						.frame(width: 48, height: 48)
					Text(agent.displayName)
				}
			} deselector: {
				SelectableRow(selection: $selection, item: nil) {
					Label("No Instalock Agent", systemImage: "xmark")
				}
			}
		}
		.navigationTitle("Agent to Instalock")
		.onAppear {
			selection = settings.instalockAgent
		}
		.onChange(of: selection) { newValue in
			settings.instalockAgent = newValue
		}
		.task {
			guard inventory == nil, let client = accountManager.activeAccount?.client else { return }
			inventory = try? await client.getInventory()
		}
	}
}

extension AgentInfo: SearchableAsset {
	var searchableText: String { displayName }
}

struct AdvancedSettingsView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@StateObject var storageManager = StorageManager()
	@State var hasRefreshedWidgets = false
	
	var body: some View {
		Form {
			Section {
				NavigationLink("Manage Assets") {
					AssetsInfoView(assetManager: assetManager)
				}
				
				if let activeAccount = accountManager.activeAccount {
					NavigationLink {
						ClientLogView(client: activeAccount.client)
					} label: {
						Text("Request Log", comment: "Advanced Settings: button to open request log")
					}
				}
				
				NavigationLink {
					StorageManagementView(manager: storageManager, accountManager: accountManager)
						.withLoadErrorAlerts()
				} label: {
					HStack {
						Text("Manage Local Storage")
						Spacer()
						if let total = try? storageManager.totalBytes?.get() {
							Text(total, format: .byteCount(style: .file))
								.foregroundStyle(.secondary)
						}
					}
				}
			}
			
			Section {
				Button("Force Refresh Widgets") {
					WidgetCenter.shared.reloadAllTimelines()
					hasRefreshedWidgets = true
				}
			} footer: {
				Text("If your widgets seem broken, use this button to request an immediate refresh from iOS.")
			}
			.alert("Widget Refresh Requested", isPresented: $hasRefreshedWidgets) {
				Button("OK") {}
			} message: {
				Text("iOS is a bit finnicky about this, so widgets may not refresh right away—feel free to reboot your device if this doesn't help!")
			}

		}
		.navigationTitle("Advanced Settings")
	}
}

private extension AppSettings.Theme {
	var name: Text {
		switch self {
		case .system:
			return Text("Match System", comment: "App Theme: automatically match the system theme")
		case .light:
			return Text("Light Mode", comment: "App Theme")
		case .dark:
			return Text("Dark Mode", comment: "App Theme")
		}
	}
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		SettingsView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init())
			.withToolbar()
		
		AdvancedSettingsView(accountManager: .mocked, assetManager: .forPreviews)
			.withToolbar()
			.previewDisplayName("Advanced Settings")
		
		SettingsView(accountManager: .mockEmpty, assetManager: .mockEmpty, settings: .init(), store: .init())
			.withToolbar()
			.previewDisplayName("Empty Managers")
		
		AppIconPicker(manager: .init())
			.withToolbar()
			.previewDisplayName("App Icon Picker")
	}
}
#endif
