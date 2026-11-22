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
	@State private var showingAccentColorPicker = false
	
	@Namespace private var storefrontID
	
	var body: some View {
		ScrollViewReader { scrollView in
			Form {
				AccountSettingsView(
					accountManager: accountManager,
					loginTarget: $loginTarget,
					showSignOutButton: false
				)
				
				Section(header: Text("Settings", comment: "Settings: section")) {
					mainSettings()
				}
				
				Section {
					NavigationLink {
						StorageView(accountManager: accountManager, assetManager: assetManager, settings: settings)
					} label: {
						Label {
							Text("Storage and Data")
						} icon: {
							Image(systemName: "arrow.up.arrow.down")
								.foregroundStyle(.tint)
						}
					}
					
					NavigationLink {
						AdvancedSettingsView(accountManager: accountManager, assetManager: assetManager, settings: settings)
					} label: {
						Label {
							Text("Advanced Settings")
						} icon: {
							Image(systemName: "slider.horizontal.3")
								.foregroundStyle(.tint)
						}
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
								Text(settings.instalockAgent.flatMap { assetManager.assets?.agents[$0]?.displayName } ?? String(localized: "Not Selected", comment: "Instalock Agent: no agent chosen"))
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

				Section(header: Text("About", comment: "Settings: section")) {
					NavigationLink {
						AboutScreen()
					} label: {
						Label {
							Text("About Vantage")
						} icon: {
							Image(systemName: "questionmark")
								.foregroundStyle(.tint)
						}
					}
				}
				.id(storefrontID)
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
			if target != nil {
				loginWebViewModel.startNewSession(clearWebData: settings.clearWebSignInDataOnOpen)
			}
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
					.foregroundStyle(.tint)
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
					.foregroundStyle(.tint)
			}
		}
		
		Button {
			showingAccentColorPicker = true
		} label: {
			Label {
				HStack {
					Text("Custom Accent Color")
					Spacer()
					Circle()
						.fill(settings.effectiveAccentColor)
						.frame(width: 24, height: 24)
						.overlay {
							Circle()
								.strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
						}
				}
			} icon: {
				Image(systemName: "paintpalette")
					.foregroundStyle(.tint)
			}
		}
		.buttonStyle(.plain)
		.background(
			AccentColorPickerPresenter(isPresented: $showingAccentColorPicker, settings: settings)
				.frame(width: 0, height: 0)
		)
		
		Button {
			settings.resetAccentColor()
		} label: {
			Label {
				HStack {
					Text("Reset to Default Color")
						.foregroundStyle(settings.hasCustomAccentColor ? Color.accentColor : Color.secondary)
					Spacer()
					if !settings.hasCustomAccentColor {
						Text("Default")
							.foregroundStyle(.secondary)
					}
				}
			} icon: {
				Image(systemName: "arrow.counterclockwise")
					.foregroundStyle(settings.hasCustomAccentColor ? Color.accentColor : Color.secondary)
			}
		}
		.disabled(!settings.hasCustomAccentColor)
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

private struct AccentColorPickerPresenter: UIViewControllerRepresentable {
	@Binding var isPresented: Bool
	@ObservedObject var settings: AppSettings
	
	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}
	
	func makeUIViewController(context: Context) -> UIViewController {
		UIViewController()
	}
	
	func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
		context.coordinator.parent = self
		guard isPresented, context.coordinator.presentedPicker == nil else { return }
		
		let picker = UIColorPickerViewController()
		picker.title = "Accent Color"
		picker.supportsAlpha = false
		picker.selectedColor = settings.pickerSelectedUIColor
		picker.delegate = context.coordinator
		picker.presentationController?.delegate = context.coordinator
		
		context.coordinator.initialComponents = settings.customAccentColorComponents
		context.coordinator.didFinish = false
		context.coordinator.presentedPicker = picker
		
		DispatchQueue.main.async {
			let host: UIViewController?
			if uiViewController.viewIfLoaded?.window != nil, uiViewController.presentedViewController == nil {
				host = uiViewController
			} else {
				host = Self.topViewController()
			}
			guard let host, host.presentedViewController == nil else {
				context.coordinator.presentedPicker = nil
				isPresented = false
				return
			}
			host.present(picker, animated: true)
		}
	}
	
	private static func topViewController() -> UIViewController? {
		let keyWindow = UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first(where: \.isKeyWindow)
			?? UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first
		var current = keyWindow?.rootViewController
		while let presented = current?.presentedViewController {
			current = presented
		}
		return current
	}
	
	final class Coordinator: NSObject, UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
		var parent: AccentColorPickerPresenter
		weak var presentedPicker: UIColorPickerViewController?
		var initialComponents = ""
		var didFinish = false
		
		init(parent: AccentColorPickerPresenter) {
			self.parent = parent
		}
		
		func colorPickerViewController(
			_ viewController: UIColorPickerViewController,
			didSelect color: UIColor,
			continuously: Bool
		) {
			Task { @MainActor [settings = parent.settings] in
				settings.setCustomAccentColor(color)
			}
		}
		
		func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
			finishIfNeeded()
		}
		
		func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
			finishIfNeeded()
		}
		
		private func finishIfNeeded() {
			guard !didFinish else { return }
			didFinish = true
			presentedPicker = nil
			let settings = parent.settings
			let initial = initialComponents
			Task { @MainActor [weak self] in
				self?.parent.isPresented = false
				try? await Task.sleep(for: .milliseconds(180))
				if settings.customAccentColorComponents != initial {
					settings.reloadAppForAccentChange()
				}
			}
		}
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
				SelectableRow(isSelected: selection == agent.id, select: { selection = agent.id }) {
					agent.displayIcon.view()
						.frame(width: 48, height: 48)
					Text(agent.displayName)
				}
			} deselector: {
				SelectableRow(isSelected: selection == nil, select: { selection = nil }) {
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

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		SettingsView(accountManager: .mocked, assetManager: .forPreviews, settings: .init(), store: .init())
			.withToolbar()
		
		AdvancedSettingsView(accountManager: .mocked, assetManager: .forPreviews, settings: .init())
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
