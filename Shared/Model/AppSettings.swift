import SwiftUI
import ValorantAPI

final class AppSettings: ObservableObject {
	@AppStorage("AppSettings.theme")
	var theme = Theme.system
	
	@AppStorage("vibrateOnMatchFound")
	var vibrateOnMatchFound = true
	
	@AppStorage("instalock.enabled")
	private var storedInstalockEnabled = false

	/// Locks in ``instalockAgent`` as soon as Agent Select starts. Off by default.
	var instalockEnabled: Bool {
		get { storedInstalockEnabled }
		set {
			objectWillChange.send()
			storedInstalockEnabled = newValue
		}
	}

	@AppStorage("instalock.agentID")
	private var storedInstalockAgentID = ""

	var instalockAgent: Agent.ID? {
		get {
			guard let uuid = LowercaseUUID(storedInstalockAgentID) else { return nil }
			return Agent.ID(rawID: uuid)
		}
		set {
			objectWillChange.send()
			storedInstalockAgentID = newValue.map { $0.rawID.description } ?? ""
		}
	}

	enum Theme: String, Hashable, Codable, CaseIterable {
		case system
		case light
		case dark
	}
}

extension AppSettings.Theme {
	var colorScheme: ColorScheme? {
		switch self {
		case .system:
			return nil
		case .light:
			return .light
		case .dark:
			return .dark
		}
	}
}
