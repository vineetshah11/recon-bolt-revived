import SwiftUI
import ValorantAPI

/// Shows what currently occupies one of the four expression slots: a spray, or one of the newer totems.
/// Riot puts both kinds in the same slots, so they share one icon view.
struct ExpressionIcon: View {
	var expression: Loadout.Expression?
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		if let spray = expression?.spray {
			if let info = assets?.sprays[spray] {
				info.bestIcon.view()
			} else {
				unknown
			}
		} else if let totem = expression?.totem {
			if let info = assets?.totems?[totem] {
				info.displayIcon.view()
			} else {
				unknown
			}
		}
	}

	private var unknown: some View {
		// set in-game, but not in the assets we have (e.g. brand-new content before the next asset refresh)
		Image(systemName: "questionmark.circle")
			.foregroundColor(.secondary)
	}
}
