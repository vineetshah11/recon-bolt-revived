import SwiftUI
import ValorantAPI

struct LookupCell: View {
	@State var gameName = ""
	@State var tagLine = ""
	@State var isLoading = false
	@ObservedObject var history: LookupHistory
	
	@FocusState private var focusedField: Field?
	
	@Environment(\.loadWithErrorAlerts) private var load
	@Environment(\.assets) private var assets
	@EnvironmentObject private var accountManager: AccountManager
	
	@ScaledMetric(relativeTo: .body) private var maxNameFieldWidth = 150
	@ScaledMetric(relativeTo: .body) private var tagFieldWidth = 50
	
	private var parsedQuery: (name: String, tag: String)? {
		let trimmedName = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
		var trimmedTag = tagLine.trimmingCharacters(in: .whitespacesAndNewlines)
		
		let resolvedName: String
		if trimmedTag.isEmpty, let separator = trimmedName.lastIndex(of: "#") {
			resolvedName = String(trimmedName[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
			trimmedTag = String(trimmedName[trimmedName.index(after: separator)...])
				.trimmingCharacters(in: .whitespacesAndNewlines)
		} else {
			resolvedName = trimmedName
			while trimmedTag.hasPrefix("#") {
				trimmedTag.removeFirst()
			}
			trimmedTag = trimmedTag.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		
		guard !resolvedName.isEmpty, !trimmedTag.isEmpty else { return nil }
		return (resolvedName, trimmedTag)
	}
	
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
				.disabled(parsedQuery == nil)
			}
		}
		.textInputAutocapitalization(.never)
		.autocorrectionDisabled()
		.disabled(isLoading)
		.frame(height: 28)
	}
	
	private func lookUpPlayer() {
		guard !isLoading, let query = parsedQuery else { return }
		Task {
			isLoading = true
			defer { isLoading = false }
			let name = "\(query.name) #\(query.tag)"
			await load(errorTitle: "Could not look up \(name)") {
				guard let account = accountManager.activeAccount else {
					throw APIError.sessionExpired(mfaRequired: false)
				}
				let result = try await account.client.lookUpPlayerInfo(gameName: query.name, tagLine: query.tag)
				let scopedClient = account.client.in(result.location)
				let identity = await scopedClient.prefetchPlayerPreview(
					for: result.user,
					latestMatchID: result.latestMatchID
				)
				if let cardID = identity?.cardID,
				   let smallArt = assets?.playerCards[cardID]?.smallArt {
					_ = await ImageManager.shared.awaitImage(for: smallArt, bucket: .icon)
				}
				dispatchPrecondition(condition: .onQueue(.main))
				history.lookedUp(result.user.id, location: result.location)
			}
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
		.environmentObject(AccountManager.mocked)
		.frame(width: 400)
		.previewLayout(.sizeThatFits)
	}
}
#endif
