import SwiftUI
import ValorantAPI

struct LookupCell: View {
	@State var gameName = ""
	@State var tagLine = ""
	@State var isLoading = false
	@ObservedObject var history: LookupHistory
	
	@FocusState private var focusedField: Field?
	
	@Environment(\.loadWithErrorAlerts) private var load
	
	@ScaledMetric(relativeTo: .body) private var maxNameFieldWidth = 150
	@ScaledMetric(relativeTo: .body) private var tagFieldWidth = 50
	
	var body: some View {
		HStack(spacing: 12) {
			TextField(String(localized: "Name", comment: "Bookmark/Player List: lookup name placeholder"), text: $gameName)
				.frame(maxWidth: maxNameFieldWidth)
				.focused($focusedField, equals: .gameName)
				.submitLabel(.next)
				.onSubmit {
					focusedField = .tagLine
				}
			
			HStack(spacing: 4) {
				Text("#", comment: "Bookmark/Player List: lookup text fields")
					.foregroundStyle(.secondary)
				
				TextField(String(localized: "Tag", comment: "Bookmark/Player List: lookup tag placeholder"), text: $tagLine)
					.frame(width: tagFieldWidth)
					.focused($focusedField, equals: .tagLine)
					.submitLabel(.search)
					.onSubmit { lookUpPlayer() }
			}
			.contentShape(Rectangle())
			.onTapGesture {
				focusedField = .tagLine
			}
			
			Spacer(minLength: 8)
			
			if isLoading {
				ProgressView()
			} else {
				Button {
					lookUpPlayer()
				} label: {
					Image(systemName: "magnifyingglass")
				}
				.buttonStyle(.borderless)
				.disabled(gameName.isEmpty || tagLine.isEmpty)
			}
		}
		.textInputAutocapitalization(.never)
		.autocorrectionDisabled()
		.disabled(isLoading)
		.frame(height: 28)
	}
	
	private func lookUpPlayer() {
		guard !gameName.isEmpty, !tagLine.isEmpty else { return }
		Task {
			isLoading = true
			let name = "\(gameName) #\(tagLine)"
			await load(errorTitle: "Could not look up \(name)") {
				let (user, location) = try await HenrikClient.shared.lookUpPlayer(name: gameName, tag: tagLine)
				LocalDataProvider.dataFetched(user)
				dispatchPrecondition(condition: .onQueue(.main))
				history.lookedUp(user.id, location: location)
			}
			isLoading = false
		}
	}
	
	enum Field: Hashable {
		case gameName
		case tagLine
	}
}

#if DEBUG
struct LookupCell_Previews: PreviewProvider {
	static var previews: some View {
		VStack(spacing: 0) {
			LookupCell(history: LookupHistory())
				.padding()
			Divider()
			LookupCell(gameName: "Example", tagLine: "EX123", history: LookupHistory())
				.padding()
			Divider()
			LookupCell(gameName: "Example", tagLine: "EX123", isLoading: true, history: LookupHistory())
				.padding()
		}
		.frame(width: 400)
		.previewLayout(.sizeThatFits)
	}
}
#endif
