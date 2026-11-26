import SwiftUI
import ValorantAPI
import HandyOperators
import AudioToolbox

struct LiveGameBox: View {
	var userID: User.ID
	@State var party: Party?
	@State var partyPlayer: PartyPlayer?
	@State var activeMatch: ActiveMatch?
	@State var shownMatch: ActiveMatch?
	
	@Binding var isExpanded: Bool
	
	@AppStorage("LiveGameBox.shouldAutoShow")
	var shouldAutoShow = false
	
	@Environment(\.valorantLoad) private var load
	@EnvironmentObject private var settings: AppSettings
	
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
					AutoRefresher {
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
		.background(Color.secondaryGroupedBackground)
		.cornerRadius(20)
		.shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
		.onSceneActivation {
			guard isExpanded else { return }
			await load(refresh)
		}
		.onChange(of: activeMatch) { [activeMatch] newMatch in
			if shouldAutoShow, activeMatch?.id != newMatch?.id {
				shownMatch = newMatch
			}
			if settings.vibrateOnMatchFound, activeMatch == nil, newMatch != nil {
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
						playersInParty: Set(party?.members.map(\.id) ?? []),
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
		} else if party != nil {
			PartyInfoBox(
				userID: userID,
				party: Binding(
					get: { party! },
					set: { party = $0 }
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
		async let activeMatchUpdate: Void = loadActiveMatch(using: client)
		async let partyUpdate: Void = loadParty(using: client)
		_ = try await (activeMatchUpdate, partyUpdate)
	}
	
	func loadActiveMatch(using client: ValorantClient) async throws {
    	activeMatch = try await client.getActiveMatch()
	}
	
	func loadParty(using client: ValorantClient) async throws {
		async let fetchedParty = client.getPartyInfo()
		async let fetchedPlayer = client.getPartyPlayer()
		let loadedParty = try await fetchedParty
		partyPlayer = try? await fetchedPlayer
		party = loadedParty
		if let loadedParty {
			LocalDataProvider.dataFetched(loadedParty)
			var ids = loadedParty.members.map(\.id)
			ids.append(contentsOf: loadedParty.requests.map(\.requestedBy))
			if let partyPlayer {
				ids.append(contentsOf: partyPlayer.requests.map(\.requestedBy))
			}
			try await client.fetchUsers(for: Array(Set(ids)))
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
