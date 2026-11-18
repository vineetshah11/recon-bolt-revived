import SwiftUI
import ValorantAPI
import HandyOperators

struct PlayerIdentityCell: View {
	let user: User?
	let identity: Player.Identity?
	/// The signed-in account's own ID. When set, that player's name is always shown regardless of anonymization mode.
	var ownUserID: User.ID? = nil
	
	@Environment(\.assets) private var assets
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	
	private let cornerRadius: CGFloat = 16
	
	private var isOwnUser: Bool {
		user != nil && user?.id == ownUserID
	}
	
	private var isNameHidden: Bool {
		guard let user else { return true }
		return !isOwnUser && shouldAnonymize(user.id)
	}
	
	private var titleText: String? {
		guard let identity else { return nil }
		return assets?.playerTitles[identity.titleID]?.titleText
	}
	
	var body: some View {
		PlayerCardImage.wide(identity?.cardID)
			.overlay(alignment: .bottom) {
				LinearGradient(
					colors: [.clear, .black.opacity(0.8)],
					startPoint: .top,
					endPoint: .bottom
				)
				.frame(height: 96)
				.allowsHitTesting(false)
			}
			.overlay(alignment: .bottomLeading) {
				VStack(alignment: .leading, spacing: 3) {
					HStack(spacing: 6) {
						Text(userName)
							.font(.system(.headline, design: .rounded).weight(.bold))
							.foregroundColor(.white)
							.lineLimit(1)
						
						if let user, !isNameHidden {
							Text(verbatim: "#\(user.tagLine)")
								.font(.system(.subheadline, design: .rounded).weight(.medium))
								.foregroundColor(.white.opacity(0.65))
								.lineLimit(1)
						}
					}
					.placeholder(if: user == nil)
					
					if let titleText {
						Text(titleText)
							.font(.system(.caption, design: .rounded).weight(.medium))
							.foregroundColor(.white.opacity(0.75))
							.lineLimit(1)
					}
				}
				.padding(12)
			}
			.overlay(alignment: .topTrailing) {
				if let identity, identity.accountLevel > 0 {
					Text(verbatim: "\(identity.accountLevel)")
						.font(.system(.caption, design: .rounded).weight(.bold))
						.monospacedDigit()
						.foregroundColor(.white)
						.padding(.horizontal, 8)
						.padding(.vertical, 3)
						.background(Capsule().fill(Color.black.opacity(0.55)))
						.overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
						.padding(8)
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
					.stroke(ReconTheme.border, lineWidth: 1)
			)
			.listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
			.listRowSeparator(.hidden)
			.listRowBackground(Color.clear)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(spokenLabel)
	}
	
	private var userName: String {
		guard let user, !isNameHidden else { return String(localized: "Player") }
		return user.gameName
	}
	
	private var spokenLabel: String {
		guard let user, !isNameHidden else { return String(localized: "Player") }
		return "#\(user.gameName)\(user.tagLine)"
	}
}

#if DEBUG
struct PlayerIdentityCell_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			PlayerIdentityCell(user: PreviewData.user, identity: PreviewData.userIdentity)
			PlayerIdentityCell(user: PreviewData.user, identity: PreviewData.userIdentity <- {
				$0.accountLevel = 6
				$0.cardID = .init("8d82ec0a-4c3b-8458-d0b6-e1bb900671cf")!
			})
		}
		.previewLayout(.sizeThatFits)
	}
}
#endif
