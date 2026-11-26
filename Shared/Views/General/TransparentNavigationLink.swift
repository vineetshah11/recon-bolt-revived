import SwiftUI
import ValorantAPI

/// A ``NavigationLink`` that passes through explicit environment values (`anonymization` and `location`)
/// without capturing the entire SwiftUI `EnvironmentValues` snapshot on every cell.
struct TransparentNavigationLink<Destination: View, Label: View>: View {
	var isActive: Binding<Bool>? = nil
	@ViewBuilder var destination: () -> Destination
	@ViewBuilder var label: () -> Label
	
	@Environment(\.anonymization) private var anonymization
	@Environment(\.location) private var location
	
	var body: some View {
		let newDestination = {
			destination()
				.environment(\.anonymization, anonymization)
				.environment(\.location, location)
		}
		
		if let isActive {
			NavigationLink(isActive: isActive, destination: newDestination, label: label)
		} else {
			NavigationLink(destination: newDestination, label: label)
		}
	}
}
