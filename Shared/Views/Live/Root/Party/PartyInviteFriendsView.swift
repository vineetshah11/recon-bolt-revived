import SwiftUI
import ValorantAPI

struct PartyInviteFriendsView: View {
	@Binding var party: Party
	let userID: User.ID
	
	@State private var searchText = ""
	@State private var invitedJIDs: Set<String> = []
	@State private var invitingJIDs: Set<String> = []
	
	@EnvironmentObject private var socialManager: SocialManager
	@Environment(\.valorantLoad) private var load
	
	private var isSelfOwner: Bool {
		(party.members.firstElement(withID: userID) ?? party.members.first)?.isOwner == true
	}
	
	private var canInvite: Bool {
		(isSelfOwner || party.accessibility == .open) && party.state != .inMatchmaking
	}
	
	private func playingValorantFriends(memberIDs: Set<Player.ID>) -> [XMPPFriend] {
		socialManager.friends.filter { friend in
			guard friend.status != .offline,
				  friend.gameTitle == "VALORANT",
				  !friend.gameName.isEmpty else {
				return false
			}
			if let puuid = friend.puuid, memberIDs.contains(puuid) {
				return false
			}
			return true
		}
	}
	
	private func filteredFriends(from playing: [XMPPFriend]) -> [XMPPFriend] {
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !query.isEmpty else { return playing }
		return playing.filter { friend in
			friend.gameName.localizedCaseInsensitiveContains(query)
			|| friend.tagLine.localizedCaseInsensitiveContains(query)
		}
	}
	
	var body: some View {
		let memberIDs = Set(party.members.map(\.id))
		let playing = playingValorantFriends(memberIDs: memberIDs)
		let friends = filteredFriends(from: playing)
		let invitedPlayerIDs = Set(party.invites.map(\.playerID))
		
		Group {
			if playing.isEmpty {
				VStack(spacing: 12) {
					Spacer()
					Image(systemName: "person.2.slash")
						.font(.system(size: 46, weight: .light))
						.foregroundStyle(.secondary)
					Text("No Friends")
						.font(.title3.bold())
					Text("None of your friends are currently playing VALORANT.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 40)
					Spacer()
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if friends.isEmpty {
				VStack(spacing: 10) {
					Spacer()
					Image(systemName: "magnifyingglass")
						.font(.system(size: 36, weight: .light))
						.foregroundStyle(.secondary)
					Text("No Matching Friends")
						.font(.headline)
					Text("No online VALORANT friends match \"\(searchText)\".")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 36)
					Spacer()
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				ScrollView {
					LazyVStack(spacing: 0) {
						ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
							friendRow(friend, invitedPlayerIDs: invitedPlayerIDs)
							if index < friends.count - 1 {
								Divider()
									.padding(.leading, 68)
							}
						}
					}
					.background(
						Color.secondaryGroupedBackground,
						in: RoundedRectangle(cornerRadius: 18, style: .continuous)
					)
					.padding(.horizontal, 16)
					.padding(.vertical, 12)
				}
			}
		}
		.background(Color.groupedBackground)
		.safeAreaInset(edge: .bottom) {
			HStack(spacing: 10) {
				Image(systemName: "magnifyingglass")
					.foregroundStyle(.secondary)
				TextField("Search friends", text: $searchText)
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
				if !searchText.isEmpty {
					Button {
						searchText = ""
					} label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
			.background(
				Capsule()
					.fill(Color.secondaryGroupedBackground)
					.overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
			)
			.padding(.horizontal, 16)
			.padding(.bottom, 10)
			.background(
				Color.groupedBackground.opacity(0.95)
					.ignoresSafeArea(edges: .bottom)
			)
		}
		.navigationTitle("Invite Friends")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	private func isAlreadyInvited(_ friend: XMPPFriend, invitedPlayerIDs: Set<User.ID>) -> Bool {
		if invitedJIDs.contains(friend.jid) { return true }
		if let puuid = friend.puuid, invitedPlayerIDs.contains(puuid) {
			return true
		}
		return false
	}
	
	@ViewBuilder
	private func friendRow(_ friend: XMPPFriend, invitedPlayerIDs: Set<User.ID>) -> some View {
		let invited = isAlreadyInvited(friend, invitedPlayerIDs: invitedPlayerIDs)
		let isInviting = invitingJIDs.contains(friend.jid)
		
		HStack(spacing: 12) {
			PlayerCardImage.small(friend.playerCardID)
				.frame(width: 40, height: 40)
				.mask(RoundedRectangle(cornerRadius: 8, style: .continuous))
			
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 0) {
					Text(friend.gameName)
						.font(.body.weight(.medium))
					if !friend.tagLine.isEmpty {
						Text("#\(friend.tagLine)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				.lineLimit(1)
				
				Text(friend.statusText ?? (friend.status == .away ? "Away" : "Online"))
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			
			Spacer()
			
			if isInviting {
				ProgressView()
					.padding(.horizontal, 8)
			} else if invited {
				Label("Invited", systemImage: "checkmark")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					.background(Color.tertiaryGroupedBackground, in: Capsule())
			} else {
				Button("Invite") {
					invite(friend)
				}
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 14)
				.padding(.vertical, 7)
				.background(Color.tertiaryGroupedBackground, in: Capsule())
				.disabled(!canInvite)
				.opacity(canInvite ? 1 : 0.45)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
	}
	
	private func invite(_ friend: XMPPFriend) {
		guard !friend.gameName.isEmpty, !friend.tagLine.isEmpty else { return }
		guard !invitingJIDs.contains(friend.jid) else { return }
		Task {
			invitingJIDs.insert(friend.jid)
			defer { invitingJIDs.remove(friend.jid) }
			await load {
				party = try await $0.inviteToParty(name: friend.gameName, tag: friend.tagLine, in: party.id)
				invitedJIDs.insert(friend.jid)
			}
		}
	}
}
