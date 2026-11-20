import SwiftUI
import ValorantAPI

/// Shows what currently occupies one of the four expression slots: a spray, or one of the newer totems.
/// Riot puts both kinds in the same slots, so a totem used to come out blank here (it's not in the spray assets).
struct ExpressionIcon: View {
	var id: Spray.ID?
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		if let id {
			if let spray = assets?.sprays[id] {
				spray.bestIcon.view()
			} else if let totem = assets?.totems?[id] {
				totem.displayIcon.view()
			} else {
				// set in-game, but not in the assets we have (e.g. brand-new content before the next asset refresh)
				Image(systemName: "questionmark.circle")
					.foregroundColor(.secondary)
			}
		}
	}
}
