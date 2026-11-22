import SwiftUI
import ValorantAPI

struct UserLabel: View {
	var userID: User.ID
	var shouldAutoUpdate = true
	var allowTapToCopy = false
	
	@LocalData var user: User?
	@AppStorage("UserLabel.canCopy") private var canCopy = true
	@State private var didCopy = false
	
	var body: some View {
		HStack(spacing: 4) {
			if let user {
				let tagLine = Text("#\(user.tagLine)")
					.fontWeight(.regular)
					.foregroundColor(.secondary)
				
				Text("\(user.gameName) \(tagLine)")
					.fontWeight(.semibold)
				
				if didCopy {
					Image(systemName: "checkmark.circle.fill")
						.font(.caption)
						.foregroundStyle(.green)
				}
			} else {
				Text("Unknown Player")
					.fontWeight(.semibold)
					.foregroundStyle(.secondary)
					.placeholder(if: user == nil)
			}
		}
		.if(allowTapToCopy && canCopy && user != nil) { view in
			view
				.contentShape(Rectangle())
				.onTapGesture {
					copyUserName()
				}
		}
		.if(canCopy && user != nil) { view in
			view.contextMenu {
				Button {
					copyUserName()
				} label: {
					Label("Copy Player Name", systemImage: "doc.on.doc")
				}
			}
		}
		.withLocalData($user, id: userID, shouldAutoUpdate: shouldAutoUpdate)
	}
	
	private func copyUserName() {
		guard let user else { return }
		UIPasteboard.general.string = "\(user.gameName)#\(user.tagLine)"
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		withAnimation {
			didCopy = true
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
			withAnimation {
				didCopy = false
			}
		}
	}
}

extension UserLabel {
	init(userID: User.ID, shouldAutoUpdate: Bool = true, allowTapToCopy: Bool = false) {
		self.init(
			userID: userID,
			shouldAutoUpdate: shouldAutoUpdate,
			allowTapToCopy: allowTapToCopy,
			user: .init(id: userID)
		)
	}
}

#if DEBUG
struct UserLabel_Previews: PreviewProvider {
    static var previews: some View {
		VStack {
			UserLabel(userID: PreviewData.userID)
			UserLabel(userID: .init()) // randomized
		}
    }
}
#endif
