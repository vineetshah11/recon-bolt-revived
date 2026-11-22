import Foundation
import ValorantAPI

@MainActor
final class SocialManager: ObservableObject {
	enum ConnectionState: Equatable {
		case disconnected
		case connecting
		case connected
		case failed(String)
	}
	
	@Published var connectionState: ConnectionState = .disconnected
	@Published var friendsByJID: [String: XMPPFriend] = [:]
	@Published var messagesByJID: [String: [XMPPChatMessage]] = [:]
	@Published var unreadByJID: [String: Int] = [:]
	@Published var activeChatJID: String?
	@Published var myJID: String = ""
	
	private let client = XMPPClient()
	private var connectedUserID: User.ID?
	private var connectAttempt = 0
	
	var friends: [XMPPFriend] {
		friendsByJID.values.sorted { lhs, rhs in
			if lhs.isIncomingRequest != rhs.isIncomingRequest {
				return lhs.isIncomingRequest
			}
			if lhs.status != rhs.status {
				return lhs.status < rhs.status
			}
			return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
		}
	}
	
	var onlineCount: Int {
		friendsByJID.values.filter {
			!$0.isIncomingRequest && !$0.isOutgoingRequest && $0.status != .offline
		}.count
	}
	
	func connectIfNeeded(using apiClient: ValorantClient?) async {
		guard let apiClient else {
			await disconnect()
			return
		}
		if connectedUserID == apiClient.userID && (connectionState == .connected || connectionState == .connecting) {
			return
		}
		await reconnect(using: apiClient)
	}
	
	func reconnect(using apiClient: ValorantClient) async {
		connectAttempt += 1
		let attempt = connectAttempt
		await client.disconnect() // cancels any stuck in-flight attempt
		connectedUserID = apiClient.userID
		connectionState = .connecting
		friendsByJID = [:]
		do {
			try await client.connect(client: apiClient) { [weak self] event in
				await self?.handle(event)
			}
		} catch {
			guard attempt == connectAttempt else { return } // superseded by a newer attempt
			await client.disconnect()
			connectionState = .failed(error.localizedDescription)
		}
	}
	
	func disconnect() async {
		await client.disconnect()
		connectedUserID = nil
		connectionState = .disconnected
		friendsByJID = [:]
		unreadByJID = [:]
	}
	
	func sendMessage(to jid: String, body: String) async throws {
		let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		try await client.sendMessage(to: jid, body: trimmed)
		let message = XMPPChatMessage(
			id: UUID().uuidString,
			peerJID: jid,
			isOutgoing: true,
			body: trimmed,
			timestamp: Date()
		)
		appendMessage(message, for: jid)
	}
	
	func loadHistory(for jid: String) async {
		unreadByJID[jid] = 0
		try? await client.requestArchive(with: jid)
	}
	
	func addFriend(gameName: String, tagLine: String) async throws {
		try await client.addFriend(gameName: gameName, tagLine: tagLine)
	}
	
	func acceptFriend(_ friend: XMPPFriend) async throws {
		try await client.acceptFriend(jid: friend.jid)
		friendsByJID[friend.jid]?.subscription = "both"
	}
	
	func removeFriend(_ friend: XMPPFriend) async throws {
		try await client.removeFriend(jid: friend.jid)
		friendsByJID.removeValue(forKey: friend.jid)
	}
	
	func markRead(jid: String) {
		unreadByJID[jid] = 0
	}
	
	private func handle(_ event: XMPPEvent) {
		switch event {
		case .connected(let jid):
			self.myJID = jid
			self.connectionState = .connected
			
		case .disconnected(let error):
			if let error {
				self.connectionState = .failed(error.localizedDescription)
			} else {
				self.connectionState = .disconnected
			}
			
		case .rosterReceived(let list):
			for item in list {
				if item.subscription == "remove" {
					friendsByJID.removeValue(forKey: item.jid)
				} else if var existing = friendsByJID[item.jid] {
					if !item.gameName.isEmpty { existing.gameName = item.gameName }
					if !item.tagLine.isEmpty { existing.tagLine = item.tagLine }
					existing.subscription = item.subscription
					existing.puuid = existing.puuid ?? item.puuid
					friendsByJID[item.jid] = existing
				} else {
					friendsByJID[item.jid] = item
				}
			}
			
		case let .presenceUpdated(jid, status, gameTitle, statusText, mapPath, queueID, allyScore, enemyScore, partySize, maxPartySize, competitiveTier, accountLevel):
			var friend = friendsByJID[jid] ?? XMPPFriend(
				jid: jid,
				puuid: jid.components(separatedBy: "@").first.flatMap(User.ID.init),
				gameName: "",
				tagLine: "",
				subscription: "both"
			)
			friend.status = status
			friend.gameTitle = gameTitle
			friend.statusText = statusText
			friend.mapPath = mapPath
			friend.queueID = queueID
			friend.allyScore = allyScore
			friend.enemyScore = enemyScore
			friend.partySize = partySize
			friend.maxPartySize = maxPartySize
			friend.competitiveTier = competitiveTier
			friend.accountLevel = accountLevel
			friendsByJID[jid] = friend
			
		case .messageReceived(let msg):
			appendMessage(msg, for: msg.peerJID)
			if !msg.isOutgoing && activeChatJID != msg.peerJID {
				unreadByJID[msg.peerJID, default: 0] += 1
			}
			
		case let .archiveReceived(peerJID, history):
			let existing = messagesByJID[peerJID] ?? []
			let seenIDs = Set(existing.map(\.id))
			let merged = (existing + history.filter { !seenIDs.contains($0.id) })
				.sorted { $0.timestamp < $1.timestamp }
			messagesByJID[peerJID] = merged
		}
	}
	
	private func appendMessage(_ msg: XMPPChatMessage, for jid: String) {
		var list = messagesByJID[jid] ?? []
		if !list.contains(where: { $0.id == msg.id }) {
			list.append(msg)
			list.sort { $0.timestamp < $1.timestamp }
			messagesByJID[jid] = list
		}
	}
}
