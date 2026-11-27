import SwiftUI
import ValorantAPI
import HandyOperators
import AudioToolbox

struct LiveGameBox: View {
	var userID: User.ID
	var isTabActive: Bool = true
	@State var party: Party?
	@State var partyPlayer: PartyPlayer?
	@State var activeMatch: ActiveMatch?
	@State var shownMatch: ActiveMatch?
	
	@Binding var isExpanded: Bool
	
	@AppStorage("LiveGameBox.shouldAutoShow")
	var shouldAutoShow = false
	@AppStorage("vibrateOnMatchFound")
	private var vibrateOnMatchFound = true
	
	@State private var isRefreshing = false
	@Environment(\.valorantLoad) private var load
	
	var body: some View {
		VStack(spacing: 0) {
			HStack {
				ExpandButton(isExpanded: $isExpanded) {
					HStack {
						Text("Party")
						Spacer()
					}
				}
				.padding()
				
				Spacer()
				
				if isExpanded {
					AutoRefresher(isPaused: shownMatch != nil || !isTabActive) {
						await load(refresh)
					}
					.padding()
					.contentShape(Rectangle())
					.onTapGesture {
						Task { await load(refresh) }
					}
				} else {
					AsyncButton {
						await load(refresh)
					} label: {
						Image(systemName: "arrow.clockwise")
							.padding()
					}
				}
			}
			.font(.title2.weight(.semibold))
			
			if isExpanded {
				VStack(spacing: 14) {
					content
				}
				.padding(.horizontal, 14)
				.padding(.bottom, 14)
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
		.background {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(Color.secondaryGroupedBackground)
				.shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
		}
		.onChange(of: activeMatch) { [activeMatch] newMatch in
			if shouldAutoShow, activeMatch?.id != newMatch?.id {
				shownMatch = newMatch
			}
			if vibrateOnMatchFound, activeMatch == nil, newMatch != nil {
				AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
				UINotificationFeedbackGenerator().notificationOccurred(.success)
			}
		}
	}
	
	@ViewBuilder
	private var content: some View {
		if let activeMatch {
			VStack(spacing: 12) {
				Group {
					if activeMatch.inPregame {
						Text("Currently in agent select")
					} else {
						Text("Currently in-game")
					}
				}
				.font(.subheadline)
				.foregroundStyle(.secondary)

				NavigationLink(tag: activeMatch, selection: $shownMatch) {
					LiveGameContainer(
						userID: userID,
						activeMatch: activeMatch
					)
				} label: {
					HStack(spacing: 8) {
						if activeMatch.inPregame {
							Image(systemName: "person.fill.viewfinder")
							Text("Agent Select")
						} else {
							Image(systemName: "list.bullet.below.rectangle")
							Text("Match Details")
						}
					}
					.font(.headline)
					.foregroundStyle(Color.accentColor)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 12)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				.buttonStyle(.plain)
			}
			.frame(maxWidth: .infinity)
			.padding(14)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		} else if let currentParty = party {
			PartyInfoBox(
				userID: userID,
				party: Binding(
					get: { self.party ?? currentParty },
					set: { self.party = $0 }
				),
				partyPlayer: partyPlayer,
				shouldAutoShow: $shouldAutoShow,
				onPartyChanged: {
					await load(loadParty)
				},
				onStartPracticeRange: startPracticeRange
			)
		} else {
			VStack(spacing: 12) {
				Text("Game is not running!")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 16)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
		}
	}
	
	@Sendable
	func refresh(using client: ValorantClient) async throws {
		guard !isRefreshing else { return }
		isRefreshing = true
		defer { isRefreshing = false }
		try await loadActiveMatch(using: client)
		guard activeMatch == nil else { return }
		try await loadParty(using: client)
	}
	
	func loadActiveMatch(using client: ValorantClient) async throws {
		let fetched = try await client.getActiveMatch()
		if activeMatch != fetched {
			activeMatch = fetched
		}
	}
	
	func loadParty(using client: ValorantClient) async throws {
		let fetchedPlayer = try await client.getPartyPlayer()
		if partyPlayer != fetchedPlayer {
			partyPlayer = fetchedPlayer
		}
		let loadedParty: Party?
		if let partyID = fetchedPlayer?.currentPartyID {
			loadedParty = try await client.getPartyInfo(for: partyID)
		} else {
			loadedParty = nil
		}
		let identitiesChanged = loadedParty?.members.map(\.identity) != party?.members.map(\.identity)
		if party != loadedParty {
			party = loadedParty
		}
		if let loadedParty {
			if identitiesChanged {
				LocalDataProvider.dataFetched(loadedParty)
			}
			var ids = Set(loadedParty.members.map(\.id))
			ids.formUnion(loadedParty.requests.map(\.requestedBy))
			if let fetchedPlayer {
				ids.formUnion(fetchedPlayer.requests.map(\.requestedBy))
			}
			let missingIDs = ids.filter { LocalDataProvider.shared.userManager.loadedObject(for: $0) == nil }
			if !missingIDs.isEmpty {
				try await client.fetchUsers(for: Array(missingIDs))
			}
		}
	}
	
	func startPracticeRange() async {
		await load { client in
			let currentParty: Party?
			if let existing = party {
				currentParty = existing
			} else {
				currentParty = try? await client.getPartyInfo()
			}
			if let partyID = currentParty?.id {
				let preferredPod = currentParty?.matchmakingData.preferredGamePods.first
				try await client.startPracticeRange(in: partyID, preferredGamePod: preferredPod)
			} else {
				try await client.startSoloExperience()
			}
			try await refresh(using: client)
		}
	}
}

#if DEBUG
struct LiveGameBox_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			LiveGameBox(
				userID: PreviewData.userID,
				isExpanded: .constant(true)
			)
			LiveGameBox(
				userID: PreviewData.userID,
				party: PreviewData.party,
				isExpanded: .constant(true)
			)
		}
		.padding()
		.background(Color.groupedBackground)
		.previewLayout(.sizeThatFits)
		
		VStack(spacing: 16) {
			LiveGameBox(
				userID: PreviewData.userID,
				activeMatch: .init(id: Match.ID(), inPregame: true),
				isExpanded: .constant(true)
			)
			LiveGameBox(
				userID: PreviewData.userID,
				activeMatch: .init(id: Match.ID(), inPregame: false),
				isExpanded: .constant(true)
			)
			Spacer()
		}
		.padding()
		.background(Color.groupedBackground)
		.withToolbar()
	}
}
#endif
