import SwiftUI
import ValorantAPI

struct FriendsView: View {
	@EnvironmentObject private var socialManager: SocialManager
	@EnvironmentObject private var accountManager: AccountManager
	@Environment(\.assets) private var assets
	
	@State private var search = ""
	@State private var showingAddFriend = false
	@State private var friendName = ""
	@State private var friendTag = ""
	@State private var actionError: String?
	
	private var client: ValorantClient? {
		accountManager.activeAccount?.client
	}
	
	var body: some View {
		List {
			statusSection
			
			let incoming = socialManager.friends.filter {
				$0.isIncomingRequest && matchesSearch($0)
			}
			if !incoming.isEmpty {
				Section("Friend Requests (\(incoming.count))") {
					ForEach(incoming) { friend in
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(friend.displayName)
									.font(.headline)
								Text("Incoming Request")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Spacer()
							AsyncButton {
								do {
									try await socialManager.acceptFriend(friend)
								} catch {
									actionError = error.localizedDescription
								}
							} label: {
								Image(systemName: "checkmark.circle.fill")
									.font(.title3)
									.foregroundStyle(.green)
							}
							.buttonStyle(.borderless)
							
							AsyncButton {
								do {
									try await socialManager.removeFriend(friend)
								} catch {
									actionError = error.localizedDescription
								}
							} label: {
								Image(systemName: "xmark.circle.fill")
									.font(.title3)
									.foregroundStyle(.red)
							}
							.buttonStyle(.borderless)
						}
					}
				}
			}
			
			let activeFriends = socialManager.friends.filter {
				!$0.isIncomingRequest && !$0.isOutgoingRequest && $0.status != .offline && matchesSearch($0)
			}
			if !activeFriends.isEmpty {
				Section("Online (\(activeFriends.count))") {
					ForEach(activeFriends) { friend in
						friendRow(friend)
					}
				}
			}
			
			let offlineFriends = socialManager.friends.filter {
				!$0.isIncomingRequest && ($0.status == .offline || $0.isOutgoingRequest) && matchesSearch($0)
			}
			if !offlineFriends.isEmpty {
				Section(search.isEmpty ? "Offline (\(offlineFriends.count))" : "Matching Friends") {
					ForEach(offlineFriends) { friend in
						friendRow(friend)
					}
				}
			}
			
			if socialManager.friends.isEmpty && socialManager.connectionState == .connected {
				Section {
					Text("No friends returned on your Riot roster yet.")
						.foregroundStyle(.secondary)
				}
			}
		}
		.searchable(text: $search, prompt: Text("Search friends"))
		.navigationTitle("Friends")
		.toolbar {
			ToolbarItemGroup(placement: .primaryAction) {
				if let client {
					AsyncButton {
						await socialManager.reconnect(using: client)
					} label: {
						Image(systemName: "arrow.clockwise")
					}
				}
				Button {
					friendName = ""
					friendTag = ""
					showingAddFriend = true
				} label: {
					Image(systemName: "person.badge.plus")
				}
				.disabled(socialManager.connectionState != .connected)
			}
		}
		.task {
			await socialManager.connectIfNeeded(using: client)
		}
		.alert("Add Friend", isPresented: $showingAddFriend) {
			TextField("Game Name", text: $friendName)
			TextField("Tag Line (without #)", text: $friendTag)
			Button("Send Request") {
				let name = friendName.trimmingCharacters(in: .whitespacesAndNewlines)
				let tag = friendTag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
				guard !name.isEmpty, !tag.isEmpty else { return }
				Task {
					do {
						try await socialManager.addFriend(gameName: name, tagLine: tag)
					} catch {
						actionError = error.localizedDescription
					}
				}
			}
			Button("Cancel", role: .cancel) {}
		}
		.alert("Social Error", isPresented: Binding(
			get: { actionError != nil },
			set: { if !$0 { actionError = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			if let actionError {
				Text(actionError)
			}
		}
	}
	
	@ViewBuilder
	private var statusSection: some View {
		Section {
			HStack(spacing: 10) {
				Circle()
					.fill(statusDotColor)
					.frame(width: 10, height: 10)
				
				switch socialManager.connectionState {
				case .connected:
					Text("Connected • \(socialManager.onlineCount) online")
						.font(.subheadline.weight(.medium))
				case .connecting:
					HStack(spacing: 8) {
						ProgressView()
							.controlSize(.small)
						Text("Connecting to Riot Chat...")
							.font(.subheadline)
					}
				case .disconnected:
					Text(client == nil ? "Sign in to view friends" : "Disconnected from Riot Chat")
						.font(.subheadline)
						.foregroundStyle(.secondary)
					Spacer()
					retryButton
				case .failed(let message):
					VStack(alignment: .leading, spacing: 2) {
						Text("Chat Connection Failed")
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.red)
						Text(message)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Spacer()
					retryButton
				}
			}
		}
	}
	
	@ViewBuilder
	private var retryButton: some View {
		if let client {
			AsyncButton {
				await socialManager.reconnect(using: client)
			} label: {
				Text("Retry")
					.font(.subheadline.weight(.semibold))
			}
			.buttonStyle(.borderless)
		}
	}
	
	private var statusDotColor: Color {
		switch socialManager.connectionState {
		case .connected: return .green
		case .connecting: return .orange
		case .disconnected: return .gray
		case .failed: return .red
		}
	}
	
	private func friendRow(_ friend: XMPPFriend) -> some View {
		NavigationLink {
			ChatView(friend: friend)
		} label: {
			HStack(spacing: 12) {
				Circle()
					.fill(color(for: friend.status))
					.frame(width: 10, height: 10)
				
				VStack(alignment: .leading, spacing: 3) {
					Text(friend.displayName)
						.font(.body.weight(.medium))
					
					if friend.isOutgoingRequest {
						Text("Pending outgoing request")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else if let subtitle = presenceSummary(for: friend) {
						Text(subtitle)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				
				Spacer()
				
				let unread = socialManager.unreadByJID[friend.jid, default: 0]
				if unread > 0 {
					Text("\(unread)")
						.font(.caption2.bold())
						.foregroundStyle(.white)
						.padding(.horizontal, 7)
						.padding(.vertical, 3)
						.background(Color.accentColor, in: Capsule())
				}
			}
			.padding(.vertical, 2)
		}
		.swipeActions(edge: .trailing) {
			Button(role: .destructive) {
				Task {
					try? await socialManager.removeFriend(friend)
				}
			} label: {
				Label("Remove", systemImage: "person.badge.minus")
			}
		}
	}
	
	private func presenceSummary(for friend: XMPPFriend) -> String? {
		if friend.status == .offline {
			return nil
		}
		var parts: [String] = []
		switch friend.status {
		case .inGame: parts.append("In Game")
		case .pregame: parts.append("Agent Select")
		case .away: parts.append("Away")
		case .online: parts.append(friend.gameTitle ?? "Online")
		case .offline: break
		}
		if let queue = friend.queueID, !queue.isEmpty {
			parts.append(queue.capitalized)
		}
		if let mapPath = friend.mapPath,
		   let map = assets?.maps.values.first(where: { $0.id.rawValue.localizedCaseInsensitiveContains(mapPath) || $0.assetPath.localizedCaseInsensitiveContains(mapPath) }) {
			parts.append(map.displayName)
		}
		if let a = friend.allyScore, let e = friend.enemyScore {
			parts.append("\(a)–\(e)")
		}
		if let size = friend.partySize, let maxSize = friend.maxPartySize, maxSize > 1 {
			parts.append("Party \(size)/\(maxSize)")
		}
		if let text = friend.statusText, !text.isEmpty {
			parts.append(text)
		}
		return parts.joined(separator: " • ")
	}
	
	private func color(for status: XMPPFriendStatus) -> Color {
		switch status {
		case .inGame, .pregame: return .accentColor
		case .online: return .green
		case .away: return .orange
		case .offline: return .gray
		}
	}
	
	private func matchesSearch(_ friend: XMPPFriend) -> Bool {
		search.isEmpty || friend.displayName.localizedCaseInsensitiveContains(search)
	}
}

struct ChatView: View {
	var friend: XMPPFriend
	
	@EnvironmentObject private var socialManager: SocialManager
	@State private var draft = ""
	@State private var sendError: String?
	
	private var messages: [XMPPChatMessage] {
		socialManager.messagesByJID[friend.jid] ?? []
	}
	
	var body: some View {
		VStack(spacing: 0) {
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(spacing: 8) {
						if messages.isEmpty {
							Text("No recent messages loaded yet.")
								.font(.caption)
								.foregroundStyle(.secondary)
								.padding(.top, 32)
						}
						ForEach(messages) { msg in
							messageBubble(msg)
								.id(msg.id)
						}
					}
					.padding()
				}
				.onChange(of: messages.count) { _ in
					if let lastID = messages.last?.id {
						withAnimation {
							proxy.scrollTo(lastID, anchor: .bottom)
						}
					}
				}
			}
			
			Divider()
			
			HStack(spacing: 10) {
				TextField("Message \(friend.gameName.isEmpty ? friend.jid : friend.gameName)", text: $draft, axis: .vertical)
					.textFieldStyle(.roundedBorder)
					.lineLimit(1...4)
				
				Button {
					send()
				} label: {
					Image(systemName: "arrow.up.circle.fill")
						.font(.title2)
						.foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
				}
				.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || socialManager.connectionState != .connected)
			}
			.padding(.horizontal)
			.padding(.vertical, 10)
			.background(Color.secondaryGroupedBackground)
		}
		.navigationTitle(friend.displayName)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if let puuid = friend.puuid {
				ToolbarItem(placement: .primaryAction) {
					NavigationLink {
						MatchListView(userID: puuid)
					} label: {
						Image(systemName: "person.text.rectangle")
					}
				}
			}
		}
		.task {
			socialManager.activeChatJID = friend.jid
			await socialManager.loadHistory(for: friend.jid)
		}
		.onDisappear {
			if socialManager.activeChatJID == friend.jid {
				socialManager.activeChatJID = nil
			}
		}
		.alert("Message Failed", isPresented: Binding(
			get: { sendError != nil },
			set: { if !$0 { sendError = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			if let sendError {
				Text(sendError)
			}
		}
	}
	
	private func messageBubble(_ msg: XMPPChatMessage) -> some View {
		HStack {
			if msg.isOutgoing { Spacer(minLength: 48) }
			
			VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 3) {
				Text(msg.body)
					.font(.body)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.background(
						msg.isOutgoing ? Color.accentColor : Color.secondaryGroupedBackground,
						in: RoundedRectangle(cornerRadius: 14)
					)
					.foregroundStyle(msg.isOutgoing ? .white : .primary)
				
				Text(msg.timestamp.formatted(date: .omitted, time: .shortened))
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			
			if !msg.isOutgoing { Spacer(minLength: 48) }
		}
	}
	
	private func send() {
		let text = draft
		draft = ""
		Task {
			do {
				try await socialManager.sendMessage(to: friend.jid, body: text)
			} catch {
				draft = text
				sendError = error.localizedDescription
			}
		}
	}
}
