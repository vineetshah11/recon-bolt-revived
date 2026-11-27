import SwiftUI
import ValorantAPI

struct ExpressionImageView: View {
	var expression: Loadout.Expression
	var emptyPlaceholderSize: CGFloat = 18
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		if let sprayID = expression.spray {
			(assets?.sprays[sprayID]?.bestIcon).view(bucket: .icon)
		} else if let totemID = expression.totem {
			(assets?.flex[totemID]?.displayIcon).view(bucket: .icon)
		} else {
			Image(systemName: "plus")
				.font(.system(size: emptyPlaceholderSize, weight: .semibold))
				.foregroundStyle(.secondary.opacity(0.6))
		}
	}
	
	var displayName: String? {
		if let sprayID = expression.spray {
			return assets?.sprays[sprayID]?.displayName
		} else if let totemID = expression.totem {
			return assets?.flex[totemID]?.displayName
		}
		return nil
	}
}
