import Foundation
import Network
import ValorantAPI

struct XMPPRegion {
	var affinity: String
	/// XMPP stream domain, i.e. `<domain>.pvp.net`
	var domain: String
	/// prefix of `<prefix>.chat.si.riotgames.com`
	var hostPrefix: String
	
	var host: String { "\(hostPrefix).chat.si.riotgames.com" }
	
	/// Riot's affinity → chat server table. Note e.g. `eu1.chat.si.riotgames.com` doesn't exist—EU is `euw1`.
	init(affinity rawAffinity: String) {
		let affinity = rawAffinity.lowercased()
		self.affinity = affinity
		switch affinity {
		case "asia", "jp1":
			(domain, hostPrefix) = ("jp1", "jp1")
		case "br", "br1", "us-br1":
			(domain, hostPrefix) = ("br1", "br")
		case "eu", "eu1", "euw1", "ru1", "tr1":
			(domain, hostPrefix) = ("eu1", "euw1")
		case "eun1", "eu2":
			(domain, hostPrefix) = ("eu2", "eun1")
		case "kr1", "oc1":
			(domain, hostPrefix) = ("kr1", "kr1")
		case "la1", "us":
			(domain, hostPrefix) = ("la1", "la1")
		case "la2", "us-la2":
			(domain, hostPrefix) = ("la2", "la2")
		case "na1", "na2", "us1", "us2":
			(domain, hostPrefix) = ("na1", "na2")
		case "pbe1":
			(domain, hostPrefix) = ("pb1", "pbe1")
		case "sea1", "sa1", "ap1":
			(domain, hostPrefix) = ("sa1", "sa1")
		case "sea2", "sa2":
			(domain, hostPrefix) = ("sa2", "sa2")
		case "sea3", "sa3":
			(domain, hostPrefix) = ("sa3", "sa3")
		default:
			(domain, hostPrefix) = (affinity, affinity)
		}
	}
	
	static func fromPASToken(_ token: String, fallbackLocation: Location) -> XMPPRegion {
		let segments = token.split(separator: ".")
		if segments.count >= 2 {
			var payload = String(segments[1])
				.replacingOccurrences(of: "-", with: "+")
				.replacingOccurrences(of: "_", with: "/")
			while payload.count % 4 != 0 { payload.append("=") }
			if let data = Data(base64Encoded: payload),
			   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
				for key in ["affinity", "desired.affinity"] {
					if let affinity = json[key] as? String, !affinity.isEmpty {
						return XMPPRegion(affinity: affinity)
					}
				}
				if let desired = json["desired"] as? [String: Any],
				   let affinity = desired["affinity"] as? String, !affinity.isEmpty {
					return XMPPRegion(affinity: affinity)
				}
			}
		}
		switch fallbackLocation {
		case .europe: return XMPPRegion(affinity: "eu1")
		case .northAmerica: return XMPPRegion(affinity: "na1")
		case .korea: return XMPPRegion(affinity: "kr1")
		case .asiaPacific: return XMPPRegion(affinity: "ap1")
		case .brazil: return XMPPRegion(affinity: "br1")
		case .latinAmerica: return XMPPRegion(affinity: "la1")
		default: return XMPPRegion(affinity: "eu1")
		}
	}
}

enum XMPPError: Error, LocalizedError {
	case connectionFailed(String)
	case connectionClosed
	case authenticationFailed
	case bufferOverflow
	case notConnected
	case timedOut(String)
	
	var errorDescription: String? {
		switch self {
		case .connectionFailed(let msg): return "XMPP connection failed: \(msg)"
		case .connectionClosed: return "XMPP connection was closed."
		case .authenticationFailed: return "XMPP authentication failed."
		case .bufferOverflow: return "XMPP buffer exceeded maximum size."
		case .notConnected: return "Not connected to Riot chat server."
		case .timedOut(let step): return "Riot Chat did not respond (\(step)). Check your connection and retry."
		}
	}
}

enum XMPPFriendStatus: String, Comparable, Codable, Sendable {
	case inGame
	case pregame
	case online
	case away
	case offline
	
	private var sortRank: Int {
		switch self {
		case .inGame: return 0
		case .pregame: return 1
		case .online: return 2
		case .away: return 3
		case .offline: return 4
		}
	}
	
	static func < (lhs: XMPPFriendStatus, rhs: XMPPFriendStatus) -> Bool {
		lhs.sortRank < rhs.sortRank
	}
}

struct XMPPFriend: Identifiable, Equatable, Codable, Sendable {
	var id: String { jid }
	var jid: String
	var puuid: User.ID?
	var gameName: String
	var tagLine: String
	var subscription: String
	var note: String? = nil
	var status: XMPPFriendStatus = .offline
	var gameTitle: String? = nil
	var statusText: String? = nil
	var mapPath: String? = nil
	var queueID: String? = nil
	var provisioningFlow: String? = nil
	var allyScore: Int? = nil
	var enemyScore: Int? = nil
	var partyID: String? = nil
	var partySize: Int? = nil
	var maxPartySize: Int? = nil
	var isPartyOwner: Bool = false
	var competitiveTier: Int? = nil
	var accountLevel: Int? = nil
	var playerCardID: PlayerCard.ID? = nil
	var lastOnline: Date? = nil
	
	var displayName: String {
		if !gameName.isEmpty {
			return tagLine.isEmpty ? gameName : "\(gameName) #\(tagLine)"
		}
		return jid
	}
	
	var isIncomingRequest: Bool { subscription == "pending_in" }
	var isOutgoingRequest: Bool { subscription == "pending_out" }
}

struct XMPPPresenceUpdate: Equatable, Sendable {
	var jid: String
	var resource: String = ""
	var status: XMPPFriendStatus
	var gameTitle: String?
	var statusText: String?
	var mapPath: String?
	var queueID: String?
	var provisioningFlow: String?
	var allyScore: Int?
	var enemyScore: Int?
	var partyID: String?
	var partySize: Int?
	var maxPartySize: Int?
	var isPartyOwner: Bool
	var competitiveTier: Int?
	var accountLevel: Int?
	var playerCardID: PlayerCard.ID?
	var lastOnline: Date? = nil
}

struct XMPPChatMessage: Identifiable, Equatable {
	var id: String
	var peerJID: String
	var isOutgoing: Bool
	var body: String
	var timestamp: Date
}

enum XMPPEvent {
	case connected(myJID: String)
	case disconnected(Error?)
	case rosterReceived([XMPPFriend], isFullSnapshot: Bool)
	case presenceUpdated(XMPPPresenceUpdate)
	case messageReceived(XMPPChatMessage)
	case archiveReceived(peerJID: String, messages: [XMPPChatMessage])
}

actor XMPPClient {
	private var connection: NWConnection?
	private var buffer = ""
	private var region: XMPPRegion?
	private var myJID = ""
	private var isRunning = false
	private var receiveTask: Task<Void, Never>?
	private var eventHandler: (@Sendable (XMPPEvent) async -> Void)?
	
	private let queue = DispatchQueue(label: "com.reconbolt.xmpp")
	private let maxBufferBytes = 2_000_000
	
	func connect(
		client: ValorantClient,
		onEvent: @escaping @Sendable (XMPPEvent) async -> Void
	) async throws {
		disconnect()
		eventHandler = onEvent
		
		async let accessToken = client.getAccessToken()
		async let entitlementsToken = client.getEntitlementsToken()
		async let pasToken = client.getChatPASToken()
		
		let (rso, ent, pas) = try await (accessToken, entitlementsToken, pasToken)
		let resolvedRegion = XMPPRegion.fromPASToken(pas, fallbackLocation: client.location)
		self.region = resolvedRegion
		
		let conn = NWConnection(
			host: NWEndpoint.Host(resolvedRegion.host),
			port: NWEndpoint.Port(rawValue: 5223)!,
			using: .tls
		)
		self.connection = conn
		
		try await awaitReady(connection: conn)
		isRunning = true
		
		// 1. Open XMPP stream & SASL auth
		try await openStream(region: resolvedRegion)
		let featuresResp = try await readUntil(contains: "</stream:features>")
		guard featuresResp.contains("X-Riot-RSO-PAS") else {
			throw XMPPError.authenticationFailed
		}
		buffer = ""
		
		let authStanza = "<auth mechanism=\"X-Riot-RSO-PAS\" xmlns=\"urn:ietf:params:xml:ns:xmpp-sasl\"><rso_token>\(escapeXML(rso))</rso_token><pas_token>\(escapeXML(pas))</pas_token></auth>"
		try await sendRaw(authStanza)
		let authResp = try await readUntil(anyOf: ["<success", "<failure"])
		if authResp.contains("<failure") {
			throw XMPPError.authenticationFailed
		}
		buffer = ""
		
		// 2. Restart stream -> Bind -> Session -> Entitlements
		try await openStream(region: resolvedRegion)
		_ = try await readUntil(contains: "</stream:features>")
		buffer = ""
		
		try await sendRaw("<iq id=\"_xmpp_bind1\" type=\"set\"><bind xmlns=\"urn:ietf:params:xml:ns:xmpp-bind\"><puuid-mode enabled=\"true\"/><resource>RC-VALORANT-SWIFT</resource></bind></iq>")
		let bindResp = try await readIQResponse(id: "_xmpp_bind1")
		if let extractedJID = extractTagContent(from: bindResp, tag: "jid") {
			self.myJID = extractedJID.components(separatedBy: "/").first ?? extractedJID
		}
		
		try await sendRaw("<iq id=\"_xmpp_session1\" type=\"set\"><session xmlns=\"urn:ietf:params:xml:ns:xmpp-session\"/></iq>")
		_ = try await readIQResponse(id: "_xmpp_session1")
		
		try await sendRaw("<iq id=\"xmpp_entitlements_0\" type=\"set\"><entitlements xmlns=\"urn:riotgames:entitlements\"><token xmlns=\"\">\(escapeXML(ent))</token></entitlements></iq>")
		_ = try await readIQResponse(id: "xmpp_entitlements_0")
		
		await onEvent(.connected(myJID: myJID))
		
		// 3. Request roster & announce initial presence
		try await sendRaw("<iq type=\"get\" id=\"roster_request\"><query xmlns=\"jabber:iq:riotgames:roster\" last_state=\"true\" /></iq>")
		try await sendRaw("<presence/>")
		
		receiveTask = Task { [weak self] in
			await self?.runReceiveLoop()
		}
	}
	
	func disconnect() {
		isRunning = false
		receiveTask?.cancel()
		receiveTask = nil
		connection?.cancel()
		connection = nil
		buffer = ""
	}
	
	func requestRosterRefresh() async throws {
		guard isRunning else { throw XMPPError.notConnected }
		let id = "roster_request_\(UUID().uuidString.prefix(8))"
		let xml = "<iq type=\"get\" id=\"\(id)\"><query xmlns=\"jabber:iq:riotgames:roster\" last_state=\"true\" /></iq>"
		try await sendRaw(xml)
	}
	
	func sendMessage(to jid: String, body: String) async throws {
		guard isRunning else { throw XMPPError.notConnected }
		let id = "msg_\(UUID().uuidString.prefix(8))"
		let xml = "<message id=\"\(id)\" to=\"\(escapeXML(jid))\" type=\"chat\"><body>\(escapeXML(body))</body></message>"
		try await sendRaw(xml)
	}
	
	func requestArchive(with jid: String) async throws {
		guard isRunning else { throw XMPPError.notConnected }
		let id = "arch_\(UUID().uuidString.prefix(8))"
		let xml = "<iq type=\"get\" id=\"\(id)\"><query xmlns=\"jabber:iq:riotgames:archive\"><with>\(escapeXML(jid))</with></query></iq>"
		try await sendRaw(xml)
	}
	
	func addFriend(gameName: String, tagLine: String) async throws {
		guard isRunning else { throw XMPPError.notConnected }
		let id = UUID().uuidString.prefix(8)
		let xml = "<iq type=\"set\" id=\"roster_add_\(id)\"><query xmlns=\"jabber:iq:riotgames:roster\"><item subscription=\"pending_out\"><id name=\"\(escapeXML(gameName))\" tagline=\"\(escapeXML(tagLine))\"/></item></query></iq>"
		try await sendRaw(xml)
	}
	
	func acceptFriend(jid: String) async throws {
		guard isRunning else { throw XMPPError.notConnected }
		let id = UUID().uuidString.prefix(8)
		let bare = jid.components(separatedBy: "/").first ?? jid
		let xml = "<iq type=\"set\" id=\"roster_accept_\(id)\"><query xmlns=\"jabber:iq:riotgames:roster\"><item jid=\"\(escapeXML(bare))\" subscription=\"both\"/></query></iq>"
		try await sendRaw(xml)
	}
	
	func removeFriend(jid: String) async throws {
		guard isRunning else { throw XMPPError.notConnected }
		let id = UUID().uuidString.prefix(8)
		let bare = jid.components(separatedBy: "/").first ?? jid
		let xml = "<iq type=\"set\" id=\"roster_remove_\(id)\"><query xmlns=\"jabber:iq:riotgames:roster\"><item jid=\"\(escapeXML(bare))\" subscription=\"remove\"/></query></iq>"
		try await sendRaw(xml)
	}
	
	// MARK: - Networking Helpers
	
	private func openStream(region: XMPPRegion) async throws {
		let open = "<?xml version='1.0'?><stream:stream to='\(region.domain).pvp.net' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>"
		try await sendRaw(open)
	}
	
	private func awaitReady(connection: NWConnection, timeout: TimeInterval = 12) async throws {
		final class StateBox: @unchecked Sendable {
			let lock = NSLock()
			var resolved = false
			func resolve() -> Bool {
				lock.lock(); defer { lock.unlock() }
				if resolved { return false }
				resolved = true
				return true
			}
		}
		let box = StateBox()
		let host = region?.host ?? "chat server"
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			connection.stateUpdateHandler = { state in
				switch state {
				case .ready:
					if box.resolve() { continuation.resume() }
				case .failed(let err):
					if box.resolve() { continuation.resume(throwing: XMPPError.connectionFailed(err.localizedDescription)) }
				case .waiting(let err):
					// e.g. DNS failure: NWConnection would otherwise wait forever
					if box.resolve() {
						connection.cancel()
						continuation.resume(throwing: XMPPError.connectionFailed("\(host): \(err.localizedDescription)"))
					}
				case .cancelled:
					if box.resolve() { continuation.resume(throwing: XMPPError.connectionClosed) }
				default:
					break
				}
			}
			connection.start(queue: queue)
			queue.asyncAfter(deadline: .now() + timeout) {
				if box.resolve() {
					connection.cancel()
					continuation.resume(throwing: XMPPError.timedOut("connecting to \(host)"))
				}
			}
		}
	}
	
	private func sendRaw(_ string: String) async throws {
		guard let connection, let data = string.data(using: .utf8) else {
			throw XMPPError.notConnected
		}
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			connection.send(content: data, completion: .contentProcessed { error in
				if let error {
					continuation.resume(throwing: XMPPError.connectionFailed(error.localizedDescription))
				} else {
					continuation.resume()
				}
			})
		}
	}
	
	/// Receives with a deadline: if nothing arrives in time the connection is cancelled, which fails the pending receive.
	private func receiveChunk(timeout: TimeInterval) async throws -> String {
		guard let connection else { throw XMPPError.connectionClosed }
		let timer = DispatchWorkItem { connection.cancel() }
		queue.asyncAfter(deadline: .now() + timeout, execute: timer)
		defer { timer.cancel() }
		do {
			return try await receiveChunk()
		} catch {
			if timer.isCancelled == false, connection.state == .cancelled {
				throw XMPPError.timedOut("reading from Riot Chat")
			}
			throw error
		}
	}
	
	private func receiveChunk() async throws -> String {
		guard let connection else { throw XMPPError.connectionClosed }
		return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
			connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
				if let error {
					continuation.resume(throwing: XMPPError.connectionFailed(error.localizedDescription))
				} else if let data, !data.isEmpty {
					let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
					continuation.resume(returning: text)
				} else if isComplete {
					continuation.resume(throwing: XMPPError.connectionClosed)
				} else {
					continuation.resume(throwing: XMPPError.connectionClosed)
				}
			}
		}
	}
	
	private func readUntil(contains marker: String) async throws -> String {
		try await readUntil(anyOf: [marker])
	}
	
	private func readUntil(anyOf markers: [String], timeout: TimeInterval = 12) async throws -> String {
		let deadline = Date().addingTimeInterval(timeout)
		while !markers.contains(where: { buffer.contains($0) }) {
			if buffer.contains("<stream:error") || buffer.contains("</stream:stream>") {
				throw XMPPError.connectionClosed
			}
			let remaining = deadline.timeIntervalSinceNow
			guard remaining > 0 else { throw XMPPError.timedOut("waiting for \(markers.first ?? "response")") }
			let chunk = try await receiveChunk(timeout: remaining)
			buffer.append(chunk)
			if buffer.utf8.count > maxBufferBytes {
				throw XMPPError.bufferOverflow
			}
		}
		return buffer
	}
	
	private func readIQResponse(id: String, timeout: TimeInterval = 12) async throws -> String {
		let deadline = Date().addingTimeInterval(timeout)
		while true {
			if let iqStart = findIQStart(containingID: id, in: buffer) {
				let searchRange = iqStart..<buffer.endIndex
				let closeRange: Range<String.Index>? = {
					if let closeIQ = buffer.range(of: "</iq>", range: searchRange) {
						return closeIQ
					}
					if let selfClose = buffer.range(of: "/>", range: searchRange),
					   let firstGT = buffer.range(of: ">", range: searchRange),
					   selfClose.upperBound == firstGT.upperBound {
						return selfClose
					}
					return nil
				}()
				if let closeRange {
					let stanza = String(buffer[iqStart..<closeRange.upperBound])
					buffer.removeSubrange(buffer.startIndex..<closeRange.upperBound)
					return stanza
				}
			}
			if buffer.contains("<stream:error") || buffer.contains("</stream:stream>") {
				throw XMPPError.connectionClosed
			}
			let remaining = deadline.timeIntervalSinceNow
			guard remaining > 0 else { throw XMPPError.timedOut("waiting for \(id)") }
			let chunk = try await receiveChunk(timeout: remaining)
			buffer.append(chunk)
			if buffer.utf8.count > maxBufferBytes {
				throw XMPPError.bufferOverflow
			}
		}
	}
	
	private func findIQStart(containingID id: String, in xml: String) -> String.Index? {
		guard let idRange = xml.range(of: id) else { return nil }
		return xml.range(of: "<iq", options: .backwards, range: xml.startIndex..<idRange.lowerBound)?.lowerBound
	}
	
	private func runReceiveLoop() async {
		while isRunning && !Task.isCancelled {
			do {
				while let stanza = popNextStanza() {
					await handleStanza(stanza)
				}
				let chunk = try await receiveChunk()
				buffer.append(chunk)
				if buffer.utf8.count > maxBufferBytes {
					throw XMPPError.bufferOverflow
				}
				if buffer.contains("</stream:stream>") {
					throw XMPPError.connectionClosed
				}
				while let stanza = popNextStanza() {
					await handleStanza(stanza)
				}
			} catch {
				if isRunning {
					isRunning = false
					await eventHandler?(.disconnected(error))
				}
				break
			}
		}
	}
	
	// MARK: - Stanza Extraction & Parsing
	
	private func popNextStanza() -> String? {
		let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty {
			buffer = ""
			return nil
		}
		
		let tags = ["iq", "presence", "message"]
		var earliest: (tag: String, start: String.Index)?
		for tag in tags {
			if let r = buffer.range(of: "<\(tag)") {
				// ensure boundary after tag name
				let after = buffer[r.upperBound...]
				if after.first == " " || after.first == ">" || after.first == "/" {
					if earliest == nil || r.lowerBound < earliest!.start {
						earliest = (tag, r.lowerBound)
					}
				}
			}
		}
		guard let match = earliest else { return nil }
		
		let searchStart = match.start
		if let selfClose = buffer.range(of: "/>", range: searchStart..<buffer.endIndex),
		   let firstGT = buffer.range(of: ">", range: searchStart..<buffer.endIndex),
		   selfClose.upperBound == firstGT.upperBound {
			let stanza = String(buffer[searchStart..<selfClose.upperBound])
			buffer.removeSubrange(buffer.startIndex..<selfClose.upperBound)
			return stanza
		}
		
		let closeTag = "</\(match.tag)>"
		if let closeRange = buffer.range(of: closeTag, range: searchStart..<buffer.endIndex) {
			let stanza = String(buffer[searchStart..<closeRange.upperBound])
			buffer.removeSubrange(buffer.startIndex..<closeRange.upperBound)
			return stanza
		}
		return nil
	}
	
	private func handleStanza(_ stanza: String) async {
		if stanza.hasPrefix("<iq") {
			if stanza.contains("jabber:iq:riotgames:roster") || stanza.contains("jabber:iq:roster") {
				let iqID = extractAttribute("id", from: stanza) ?? ""
				let iqType = extractAttribute("type", from: stanza) ?? ""
				let isFullSnapshot = (iqType == "result" && iqID.hasPrefix("roster_request"))
				let friends = parseRosterItems(from: stanza)
				if !friends.isEmpty || isFullSnapshot {
					await eventHandler?(.rosterReceived(friends, isFullSnapshot: isFullSnapshot))
				}
			} else if stanza.contains("jabber:iq:riotgames:archive") {
				let (peer, messages) = parseArchiveMessages(from: stanza)
				if let peer {
					await eventHandler?(.archiveReceived(peerJID: peer, messages: messages))
				}
			}
		} else if stanza.hasPrefix("<presence") {
			if let event = parsePresence(from: stanza) {
				await eventHandler?(event)
			}
		} else if stanza.hasPrefix("<message") {
			if let msg = parseIncomingMessage(from: stanza) {
				await eventHandler?(.messageReceived(msg))
			}
		}
	}
	
	private func parseRosterItems(from xml: String) -> [XMPPFriend] {
		var result: [XMPPFriend] = []
		var cursor = xml.startIndex
		while let itemStart = xml.range(of: "<item", range: cursor..<xml.endIndex) {
			let rest = itemStart.lowerBound..<xml.endIndex
			let itemEnd: String.Index
			if let close = xml.range(of: "</item>", range: rest) {
				itemEnd = close.upperBound
			} else if let selfClose = xml.range(of: "/>", range: rest) {
				itemEnd = selfClose.upperBound
			} else {
				break
			}
			let itemXML = String(xml[itemStart.lowerBound..<itemEnd])
			cursor = itemEnd
			
			let jid = (extractAttribute("jid", from: itemXML) ?? "").components(separatedBy: "/").first ?? ""
			let puuidStr = extractAttribute("puuid", from: itemXML) ?? jid.components(separatedBy: "@").first
			let puuid = puuidStr.flatMap(User.ID.init)
			let subscription = extractAttribute("subscription", from: itemXML) ?? "both"
			let gameName = unescapeXML(
				extractNestedAttribute("id", attr: "name", from: itemXML)
				?? extractNestedAttribute("riot", attr: "name", from: itemXML)
				?? extractNestedAttribute("item", attr: "name", from: itemXML)
				?? ""
			)
			let tagLine = unescapeXML(
				extractNestedAttribute("id", attr: "tagline", from: itemXML)
				?? extractNestedAttribute("riot", attr: "tagline", from: itemXML)
				?? extractNestedAttribute("item", attr: "tagline", from: itemXML)
				?? ""
			)
			let rawNote = extractTagContent(from: itemXML, tag: "note")
				.map(unescapeXML)?
				.trimmingCharacters(in: .whitespacesAndNewlines)
			let note = (rawNote?.isEmpty == false) ? rawNote : nil
			let lastOnline = parseRiotTimestamp(extractTagContent(from: itemXML, tag: "last_online"))
			
			guard !jid.isEmpty else { continue }
			result.append(XMPPFriend(
				jid: jid,
				puuid: puuid,
				gameName: gameName,
				tagLine: tagLine,
				subscription: subscription,
				note: note,
				lastOnline: lastOnline
			))
		}
		return result
	}
	
	private func parsePresence(from xml: String) -> XMPPEvent? {
		guard let rawFrom = extractAttribute("from", from: xml) else { return nil }
		let parts = rawFrom.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
		let bareJID = String(parts.first ?? Substring(rawFrom))
		let resource = parts.count > 1 ? String(parts[1]) : ""
		let typeAttr = extractAttribute("type", from: xml)
		var lastOnline = parseRiotTimestamp(extractTagContent(from: xml, tag: "last_online"))
		
		if typeAttr == "unavailable" {
			return .presenceUpdated(XMPPPresenceUpdate(
				jid: bareJID,
				resource: resource,
				status: .offline,
				gameTitle: nil,
				statusText: nil,
				mapPath: nil,
				queueID: nil,
				provisioningFlow: nil,
				allyScore: nil,
				enemyScore: nil,
				partyID: nil,
				partySize: nil,
				maxPartySize: nil,
				isPartyOwner: false,
				competitiveTier: nil,
				accountLevel: nil,
				playerCardID: nil,
				lastOnline: lastOnline
			))
		}
		
		let show = extractTagContent(from: xml, tag: "show")?
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		let platform = extractTagContent(from: xml, tag: "platform")?
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		let baseStatus = resolveBaseStatus(show: show, platform: platform)
		
		var status: XMPPFriendStatus = baseStatus
		var gameTitle: String? = nil
		var statusText: String? = unescapeXML(extractTagContent(from: xml, tag: "status") ?? "")
		if statusText?.isEmpty == true { statusText = nil }
		
		var mapPath: String?
		var queueID: String?
		var provisioningFlow: String?
		var allyScore: Int?
		var enemyScore: Int?
		var partyID: String?
		var partySize: Int?
		var maxPartySize: Int?
		var isPartyOwner = false
		var competitiveTier: Int?
		var accountLevel: Int?
		var playerCardID: PlayerCard.ID?
		
		var didSetActiveGame = false
		
		if let valBlock = extractTagContent(from: xml, tag: "valorant") {
			let (gameStatus, stTime) = parseGameBlockStatus(valBlock, fallback: baseStatus)
			if let stTime, (lastOnline == nil || stTime > lastOnline!) { lastOnline = stTime }
			
			var isPresenceValid = true
			if let b64 = extractTagContent(from: valBlock, tag: "p"),
			   let decoded = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)),
			   let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] {
				if let valid = json["isValid"] as? Bool, !valid {
					isPresenceValid = false
				}
				
				let matchData = json["matchPresenceData"] as? [String: Any]
				let partyData = json["partyPresenceData"] as? [String: Any]
				let playerData = json["playerPresenceData"] as? [String: Any]
				
				competitiveTier = (playerData?["competitiveTier"] as? Int) ?? (json["competitiveTier"] as? Int)
				accountLevel = (playerData?["accountLevel"] as? Int) ?? (json["accountLevel"] as? Int)
				
				let rawCard = (playerData?["playerCardId"] as? String) ?? (json["playerCardId"] as? String)
				if let rawCard, !rawCard.isEmpty, rawCard != "00000000-0000-0000-0000-000000000000" {
					playerCardID = PlayerCard.ID(rawCard)
				}
				
				if gameStatus != .offline && isPresenceValid {
					didSetActiveGame = true
					gameTitle = "VALORANT"
					status = gameStatus
					
					let loopState = (json["sessionLoopState"] as? String)
						?? (matchData?["sessionLoopState"] as? String)
						?? (playerData?["sessionLoopState"] as? String)
						?? (json["partyOwnerSessionLoopState"] as? String)
					switch loopState {
					case "INGAME":
						status = .inGame
					case "PREGAME", "AGENT_SELECT":
						status = .pregame
					default:
						break
					}
					
					let rawMap = (matchData?["matchMap"] as? String)
						?? (json["matchMap"] as? String)
						?? (json["partyOwnerMatchMap"] as? String)
					mapPath = (rawMap?.isEmpty == false) ? rawMap : nil
					
					let rawQueue = (matchData?["queueId"] as? String)
						?? (partyData?["queueId"] as? String)
						?? (json["queueId"] as? String)
					queueID = (rawQueue?.isEmpty == false) ? rawQueue : nil
					
					let rawFlow = (matchData?["provisioningFlow"] as? String)
						?? (json["provisioningFlow"] as? String)
						?? (json["partyOwnerProvisioningFlow"] as? String)
					provisioningFlow = (rawFlow?.isEmpty == false && rawFlow != "Invalid") ? rawFlow : nil
					
					allyScore = (json["partyOwnerMatchScoreAllyTeam"] as? Int) ?? (matchData?["partyOwnerMatchScoreAllyTeam"] as? Int)
					enemyScore = (json["partyOwnerMatchScoreEnemyTeam"] as? Int) ?? (matchData?["partyOwnerMatchScoreEnemyTeam"] as? Int)
					
					let rawParty = (partyData?["partyId"] as? String) ?? (json["partyId"] as? String)
					if let rawParty, !rawParty.isEmpty, rawParty != "00000000-0000-0000-0000-000000000000" {
						partyID = rawParty
					}
					partySize = (partyData?["partySize"] as? Int) ?? (json["partySize"] as? Int)
					maxPartySize = (partyData?["maxPartySize"] as? Int) ?? (json["maxPartySize"] as? Int)
					isPartyOwner = (partyData?["isPartyOwner"] as? Bool) ?? (json["isPartyOwner"] as? Bool) ?? false
				}
			} else if gameStatus != .offline {
				didSetActiveGame = true
				gameTitle = "VALORANT"
				status = gameStatus
			}
		}
		
		if !didSetActiveGame, let lolBlock = extractTagContent(from: xml, tag: "league_of_legends") {
			let (gameStatus, stTime) = parseGameBlockStatus(lolBlock, fallback: baseStatus)
			if let stTime, (lastOnline == nil || stTime > lastOnline!) { lastOnline = stTime }
			if gameStatus != .offline {
				didSetActiveGame = true
				status = gameStatus
				if let p = extractTagContent(from: lolBlock, tag: "p"), p.contains("TFT") {
					gameTitle = "Teamfight Tactics"
				} else {
					gameTitle = "League of Legends"
				}
			}
		}
		
		if !didSetActiveGame, let lorBlock = extractTagContent(from: xml, tag: "bacon") ?? extractTagContent(from: xml, tag: "lor") {
			let (gameStatus, stTime) = parseGameBlockStatus(lorBlock, fallback: baseStatus)
			if let stTime, (lastOnline == nil || stTime > lastOnline!) { lastOnline = stTime }
			if gameStatus != .offline {
				didSetActiveGame = true
				status = gameStatus
				gameTitle = "Legends of Runeterra"
			}
		}
		
		if !didSetActiveGame, let clientBlock = extractTagContent(from: xml, tag: "keystone") ?? extractTagContent(from: xml, tag: "riot_client") {
			let (gameStatus, stTime) = parseGameBlockStatus(clientBlock, fallback: baseStatus)
			if let stTime, (lastOnline == nil || stTime > lastOnline!) { lastOnline = stTime }
			if gameStatus != .offline {
				didSetActiveGame = true
				status = gameStatus
				gameTitle = "Riot Client"
			}
		}
		
		if !didSetActiveGame {
			// If <games> had blocks and none were online, treat friend as offline.
			if extractTagContent(from: xml, tag: "games") != nil || baseStatus == .offline {
				status = .offline
			}
		}
		
		return .presenceUpdated(XMPPPresenceUpdate(
			jid: bareJID,
			resource: resource,
			status: status,
			gameTitle: gameTitle,
			statusText: status == .offline ? nil : statusText,
			mapPath: mapPath,
			queueID: queueID,
			provisioningFlow: provisioningFlow,
			allyScore: allyScore,
			enemyScore: enemyScore,
			partyID: partyID,
			partySize: partySize,
			maxPartySize: maxPartySize,
			isPartyOwner: isPartyOwner,
			competitiveTier: competitiveTier,
			accountLevel: accountLevel,
			playerCardID: playerCardID,
			lastOnline: lastOnline
		))
	}
	
	private func resolveBaseStatus(show: String?, platform: String?) -> XMPPFriendStatus {
		if platform == "absent" {
			return .offline
		}
		if platform == nil && show == nil {
			return .offline
		}
		switch show {
		case "away", "xa":
			return .away
		case "dnd", "chat":
			return .online
		case nil:
			return platform != nil ? .online : .offline
		default:
			return .online
		}
	}
	
	private func parseGameBlockStatus(_ block: String, fallback: XMPPFriendStatus) -> (XMPPFriendStatus, Date?) {
		let stTime = parseRiotTimestamp(extractTagContent(from: block, tag: "s.t"))
		let st = (extractTagContent(from: block, tag: "st") ?? extractTagContent(from: block, tag: "s"))?
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		switch st {
		case "offline", "mobile":
			return (.offline, stTime)
		case "away", "xa":
			return (.away, stTime)
		case "chat", "dnd", "online":
			return (.online, stTime)
		default:
			return (fallback, stTime)
		}
	}
	
	private func parseIncomingMessage(from xml: String) -> XMPPChatMessage? {
		guard let rawBody = extractTagContent(from: xml, tag: "body") else { return nil }
		let body = unescapeXML(rawBody)
		guard !body.isEmpty else { return nil }
		
		let fromJID = (extractAttribute("from", from: xml) ?? "").components(separatedBy: "/").first ?? ""
		let toJID = (extractAttribute("to", from: xml) ?? "").components(separatedBy: "/").first ?? ""
		let stamp = extractAttribute("stamp", from: xml)
		let timestamp = stamp.flatMap(parseXMPPDate) ?? Date()
		let isOutgoing = !myJID.isEmpty && fromJID == myJID
		let peer = isOutgoing ? toJID : fromJID
		guard !peer.isEmpty else { return nil }
		
		let id = extractAttribute("id", from: xml) ?? UUID().uuidString
		return XMPPChatMessage(id: id, peerJID: peer, isOutgoing: isOutgoing, body: body, timestamp: timestamp)
	}
	
	private func parseArchiveMessages(from xml: String) -> (String?, [XMPPChatMessage]) {
		let withJID = extractTagContent(from: xml, tag: "with")?.components(separatedBy: "/").first
		var messages: [XMPPChatMessage] = []
		var cursor = xml.startIndex
		while let msgStart = xml.range(of: "<message", range: cursor..<xml.endIndex),
			  let msgEnd = xml.range(of: "</message>", range: msgStart.lowerBound..<xml.endIndex) {
			let msgXML = String(xml[msgStart.lowerBound..<msgEnd.upperBound])
			cursor = msgEnd.upperBound
			if let msg = parseIncomingMessage(from: msgXML) {
				messages.append(msg)
			}
		}
		let peer = withJID ?? messages.first?.peerJID
		return (peer, messages.sorted { $0.timestamp < $1.timestamp })
	}
	
	// MARK: - Small XML Utilities
	
	private func extractTagContent(from xml: String, tag: String) -> String? {
		var searchStart = xml.startIndex
		while let openStart = xml.range(of: "<\(tag)", range: searchStart..<xml.endIndex) {
			let afterTag = openStart.upperBound
			guard afterTag < xml.endIndex else { return nil }
			let nextChar = xml[afterTag]
			if nextChar == ">" || nextChar == " " {
				guard let openEnd = xml.range(of: ">", range: afterTag..<xml.endIndex) else { return nil }
				// Self-closing tag has no body
				if xml[xml.index(before: openEnd.lowerBound)] == "/" {
					return nil
				}
				guard let closeStart = xml.range(of: "</\(tag)>", range: openEnd.upperBound..<xml.endIndex) else {
					return nil
				}
				return String(xml[openEnd.upperBound..<closeStart.lowerBound])
			}
			searchStart = afterTag
		}
		return nil
	}
	
	private static let riotMilliDateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.timeZone = TimeZone(secondsFromGMT: 0)
		f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		return f
	}()
	
	private static let riotDateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.timeZone = TimeZone(secondsFromGMT: 0)
		f.dateFormat = "yyyy-MM-dd HH:mm:ss"
		return f
	}()
	
	private func parseRiotTimestamp(_ raw: String?) -> Date? {
		guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
			return nil
		}
		if let num = Int64(trimmed) {
			if num >= 1_000_000_000_000 {
				return Date(timeIntervalSince1970: Double(num) / Double(1000))
			} else if num >= 1_000_000_000 {
				return Date(timeIntervalSince1970: Double(num))
			}
		}
		if let d = Self.riotMilliDateFormatter.date(from: trimmed) {
			return d
		}
		if let d = Self.riotDateFormatter.date(from: trimmed) {
			return d
		}
		return parseXMPPDate(trimmed)
	}
	
	private func extractAttribute(_ name: String, from xml: String) -> String? {
		for quote in ["'", "\""] {
			let prefix = "\(name)=\(quote)"
			if let start = xml.range(of: prefix),
			   let end = xml.range(of: quote, range: start.upperBound..<xml.endIndex) {
				return String(xml[start.upperBound..<end.lowerBound])
			}
		}
		return nil
	}
	
	private func extractNestedAttribute(_ tag: String, attr: String, from xml: String) -> String? {
		guard let start = xml.range(of: "<\(tag)"),
			  let end = xml.range(of: ">", range: start.lowerBound..<xml.endIndex) else { return nil }
		return extractAttribute(attr, from: String(xml[start.lowerBound..<end.upperBound]))
	}
	
	private func escapeXML(_ string: String) -> String {
		string
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "'", with: "&apos;")
	}
	
	private func unescapeXML(_ string: String) -> String {
		string
			.replacingOccurrences(of: "&apos;", with: "'")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&amp;", with: "&")
	}
	
	private func parseXMPPDate(_ string: String) -> Date? {
		let isoFractional = ISO8601DateFormatter()
		isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let d = isoFractional.date(from: string) { return d }
		return ISO8601DateFormatter().date(from: string)
	}
}
