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

struct XMPPChatMessage: Identifiable, Equatable, Codable, Sendable {
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

private final class ContinuationBox<Value: Sendable>: @unchecked Sendable {
	private let lock = NSLock()
	private var continuation: CheckedContinuation<Value, Error>?
	private var pendingResult: Result<Value, Error>?
	private var isResolved = false
	private var waitingTimer: DispatchWorkItem?
	
	func setContinuation(_ continuation: CheckedContinuation<Value, Error>) {
		let immediateResult: Result<Value, Error>?
		lock.lock()
		if let pending = pendingResult {
			self.pendingResult = nil
			immediateResult = pending
		} else {
			self.continuation = continuation
			immediateResult = nil
		}
		lock.unlock()
		if let immediateResult {
			continuation.resume(with: immediateResult)
		}
	}
	
	@discardableResult
	func resolve(with result: Result<Value, Error>) -> Bool {
		let cont: CheckedContinuation<Value, Error>?
		let timerToCancel: DispatchWorkItem?
		lock.lock()
		if isResolved {
			lock.unlock()
			return false
		}
		isResolved = true
		timerToCancel = waitingTimer
		waitingTimer = nil
		if let existing = continuation {
			continuation = nil
			cont = existing
		} else {
			pendingResult = result
			cont = nil
		}
		lock.unlock()
		timerToCancel?.cancel()
		if let cont {
			cont.resume(with: result)
		}
		return true
	}
	
	func scheduleWaitingGrace(
		on queue: DispatchQueue,
		delay: TimeInterval,
		action: @escaping @Sendable () -> Void
	) {
		lock.lock()
		if isResolved || waitingTimer != nil {
			lock.unlock()
			return
		}
		let item = DispatchWorkItem(block: action)
		waitingTimer = item
		lock.unlock()
		queue.asyncAfter(deadline: .now() + delay, execute: item)
	}
	
	func cancelWaitingGrace() {
		lock.lock()
		let item = waitingTimer
		waitingTimer = nil
		lock.unlock()
		item?.cancel()
	}
}

actor XMPPClient {
	private var connection: NWConnection?
	private var buffer = ""
	private var pendingUTF8Bytes = Data()
	private var region: XMPPRegion?
	private var myJID = ""
	private var isRunning = false
	private var generation: UInt64 = 0
	private var receiveTask: Task<Void, Never>?
	private var keepaliveTask: Task<Void, Never>?
	private var eventHandler: (@Sendable (XMPPEvent) async -> Void)?
	private var pendingArchivePeerByIQID: [String: String] = [:]
	
	private let queue = DispatchQueue(label: "com.reconbolt.xmpp")
	private let maxBufferBytes = 2_000_000
	
	private let riotMilliDateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.timeZone = TimeZone(secondsFromGMT: 0)
		f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		return f
	}()
	
	private let riotDateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.timeZone = TimeZone(secondsFromGMT: 0)
		f.dateFormat = "yyyy-MM-dd HH:mm:ss"
		return f
	}()
	
	private let xmppFractionalDateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
	private let xmppDateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
	
	private func clearBuffer() {
		buffer = ""
		pendingUTF8Bytes.removeAll(keepingCapacity: true)
	}
	
	private func ensureActiveGeneration(_ expectedGeneration: UInt64) throws {
		try Task.checkCancellation()
		guard generation == expectedGeneration else {
			throw CancellationError()
		}
	}
	
	func connect(
		client: ValorantClient,
		onEvent: @escaping @Sendable (XMPPEvent) async -> Void
	) async throws {
		disconnect()
		let gen = self.generation
		eventHandler = onEvent
		
		let rso = try await client.getAccessToken()
		try ensureActiveGeneration(gen)
		
		async let entitlementsToken = client.getEntitlementsToken()
		async let pasToken = client.getChatPASToken()
		let (ent, pas) = try await (entitlementsToken, pasToken)
		try ensureActiveGeneration(gen)
		
		let resolvedRegion = XMPPRegion.fromPASToken(pas, fallbackLocation: client.location)
		self.region = resolvedRegion
		
		let conn = NWConnection(
			host: NWEndpoint.Host(resolvedRegion.host),
			port: NWEndpoint.Port(rawValue: 5223)!,
			using: .tls
		)
		self.connection = conn
		
		do {
			try await awaitReady(connection: conn, host: resolvedRegion.host)
			try ensureActiveGeneration(gen)
			isRunning = true
			
			// 1. Open XMPP stream & SASL auth
			try await openStream(region: resolvedRegion, on: conn)
			try ensureActiveGeneration(gen)
			let featuresResp = try await readUntil(contains: "</stream:features>", on: conn)
			try ensureActiveGeneration(gen)
			guard featuresResp.contains("X-Riot-RSO-PAS") else {
				throw XMPPError.authenticationFailed
			}
			clearBuffer()
			
			let authStanza = "<auth mechanism=\"X-Riot-RSO-PAS\" xmlns=\"urn:ietf:params:xml:ns:xmpp-sasl\"><rso_token>\(escapeXML(rso))</rso_token><pas_token>\(escapeXML(pas))</pas_token></auth>"
			try await sendRaw(authStanza, on: conn)
			let authResp = try await readUntil(anyOf: ["<success", "<failure"], on: conn)
			try ensureActiveGeneration(gen)
			if authResp.contains("<failure") {
				throw XMPPError.authenticationFailed
			}
			clearBuffer()
			
			// 2. Restart stream -> Bind -> Session -> Entitlements
			try await openStream(region: resolvedRegion, on: conn)
			_ = try await readUntil(contains: "</stream:features>", on: conn)
			try ensureActiveGeneration(gen)
			clearBuffer()
			
			try await sendRaw("<iq id=\"_xmpp_bind1\" type=\"set\"><bind xmlns=\"urn:ietf:params:xml:ns:xmpp-bind\"><puuid-mode enabled=\"true\"/><resource>RC-VALORANT-SWIFT</resource></bind></iq>", on: conn)
			let bindResp = try await readIQResponse(id: "_xmpp_bind1", on: conn)
			try ensureActiveGeneration(gen)
			if let extractedJID = extractTagContent(from: bindResp, tag: "jid") {
				self.myJID = extractedJID.components(separatedBy: "/").first ?? extractedJID
			}
			
			try await sendRaw("<iq id=\"_xmpp_session1\" type=\"set\"><session xmlns=\"urn:ietf:params:xml:ns:xmpp-session\"/></iq>", on: conn)
			_ = try await readIQResponse(id: "_xmpp_session1", on: conn)
			try ensureActiveGeneration(gen)
			
			try await sendRaw("<iq id=\"xmpp_entitlements_0\" type=\"set\"><entitlements xmlns=\"urn:riotgames:entitlements\"><token xmlns=\"\">\(escapeXML(ent))</token></entitlements></iq>", on: conn)
			_ = try await readIQResponse(id: "xmpp_entitlements_0", on: conn)
			try ensureActiveGeneration(gen)
			
			await onEvent(.connected(myJID: myJID))
			try ensureActiveGeneration(gen)
			
			// 3. Request roster & announce initial presence
			try await sendRaw("<iq type=\"get\" id=\"roster_request\"><query xmlns=\"jabber:iq:riotgames:roster\" last_state=\"true\" /></iq>", on: conn)
			try await sendRaw("<presence/>", on: conn)
			try ensureActiveGeneration(gen)
			
			receiveTask = Task { [weak self] in
				await self?.runReceiveLoop(generation: gen, connection: conn)
			}
			keepaliveTask = Task { [weak self] in
				await self?.runKeepaliveLoop(generation: gen, connection: conn)
			}
		} catch {
			if generation == gen {
				disconnect()
			} else {
				conn.cancel()
			}
			if case XMPPError.authenticationFailed = error {
				await client.invalidateChatPASToken()
			}
			throw error
		}
	}
	
	func disconnect() {
		generation &+= 1
		isRunning = false
		receiveTask?.cancel()
		receiveTask = nil
		keepaliveTask?.cancel()
		keepaliveTask = nil
		pendingArchivePeerByIQID.removeAll()
		connection?.cancel()
		connection = nil
		clearBuffer()
	}
	
	func ping(timeout: TimeInterval = 4) async -> Bool {
		guard isRunning, let conn = connection, conn.state == .ready else {
			return false
		}
		let box = ContinuationBox<Void>()
		let timeoutItem = DispatchWorkItem {
			if box.resolve(with: .failure(XMPPError.timedOut("pinging Riot Chat"))) {
				conn.cancel()
			}
		}
		defer { timeoutItem.cancel() }
		do {
			try await withTaskCancellationHandler {
				try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
					queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
					conn.send(content: Data(" ".utf8), completion: .contentProcessed { error in
						if let error {
							box.resolve(with: .failure(XMPPError.connectionFailed(error.localizedDescription)))
						} else {
							box.resolve(with: .success(()))
						}
					})
					box.setContinuation(continuation)
				}
			} onCancel: {
				_ = box.resolve(with: .failure(CancellationError()))
			}
			return true
		} catch {
			return false
		}
	}
	
	func requestRosterRefresh() async throws {
		guard isRunning else { throw XMPPError.notConnected }
		let id = "roster_request_\(UUID().uuidString.prefix(8))"
		let xml = "<iq type=\"get\" id=\"\(id)\"><query xmlns=\"jabber:iq:riotgames:roster\" last_state=\"true\" /></iq>"
		try await sendRaw(xml)
	}
	
	@discardableResult
	func sendMessage(to jid: String, body: String, id: String? = nil) async throws -> String {
		guard isRunning else { throw XMPPError.notConnected }
		let bare = jid.components(separatedBy: "/").first ?? jid
		let msgID = id ?? "msg_\(UUID().uuidString.prefix(8))"
		let xml = "<message id=\"\(escapeXML(msgID))\" to=\"\(escapeXML(bare))\" type=\"chat\"><body>\(escapeXML(body))</body></message>"
		try await sendRaw(xml)
		return msgID
	}
	
	func requestArchive(with jid: String) async throws {
		guard isRunning else { throw XMPPError.notConnected }
		let bare = jid.components(separatedBy: "/").first ?? jid
		let id = "get_archive_\(Int.random(in: 1...9999))_\(UUID().uuidString.prefix(6))"
		pendingArchivePeerByIQID[id] = bare
		let xml = "<iq type=\"get\" id=\"\(id)\"><query xmlns=\"jabber:iq:riotgames:archive\"><with>\(escapeXML(bare))</with></query></iq>"
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
	
	private func openStream(region: XMPPRegion, on connection: NWConnection) async throws {
		let open = "<?xml version='1.0'?><stream:stream to='\(region.domain).pvp.net' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>"
		try await sendRaw(open, on: connection)
	}
	
	private func awaitReady(connection: NWConnection, host: String, timeout: TimeInterval = 12) async throws {
		let box = ContinuationBox<Void>()
		let overallTimeout = DispatchWorkItem {
			if box.resolve(with: .failure(XMPPError.timedOut("connecting to \(host)"))) {
				connection.cancel()
			}
		}
		defer { overallTimeout.cancel() }
		
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				connection.stateUpdateHandler = { [queue] state in
					switch state {
					case .ready:
						_ = box.resolve(with: .success(()))
					case .failed(let err):
						_ = box.resolve(with: .failure(XMPPError.connectionFailed(err.localizedDescription)))
					case .waiting(let err):
						// Allow brief network transitions (e.g. Wi-Fi <-> cellular) before failing.
						box.scheduleWaitingGrace(on: queue, delay: 4) {
							if box.resolve(with: .failure(XMPPError.connectionFailed("\(host): \(err.localizedDescription)"))) {
								connection.cancel()
							}
						}
					case .preparing, .setup:
						box.cancelWaitingGrace()
					case .cancelled:
						_ = box.resolve(with: .failure(XMPPError.connectionClosed))
					@unknown default:
						break
					}
				}
				queue.asyncAfter(deadline: .now() + timeout, execute: overallTimeout)
				connection.start(queue: queue)
				box.setContinuation(continuation)
			}
		} onCancel: {
			if box.resolve(with: .failure(CancellationError())) {
				connection.cancel()
			}
		}
	}
	
	private func sendRaw(_ string: String, on targetConnection: NWConnection? = nil) async throws {
		guard let conn = targetConnection ?? connection, let data = string.data(using: .utf8) else {
			throw XMPPError.notConnected
		}
		let box = ContinuationBox<Void>()
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				conn.send(content: data, completion: .contentProcessed { error in
					if let error {
						box.resolve(with: .failure(XMPPError.connectionFailed(error.localizedDescription)))
					} else {
						box.resolve(with: .success(()))
					}
				})
				box.setContinuation(continuation)
			}
		} onCancel: {
			_ = box.resolve(with: .failure(CancellationError()))
		}
	}
	
	private func receiveChunk(on connection: NWConnection, timeout: TimeInterval? = nil) async throws -> Data {
		let box = ContinuationBox<Data>()
		let timeoutItem: DispatchWorkItem? = timeout.map { _ in
			DispatchWorkItem {
				if box.resolve(with: .failure(XMPPError.timedOut("reading from Riot Chat"))) {
					connection.cancel()
				}
			}
		}
		defer { timeoutItem?.cancel() }
		
		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
				if let timeoutItem, let timeout {
					queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
				}
				connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
					if let error {
						box.resolve(with: .failure(XMPPError.connectionFailed(error.localizedDescription)))
					} else if let data, !data.isEmpty {
						box.resolve(with: .success(data))
					} else if isComplete {
						box.resolve(with: .failure(XMPPError.connectionClosed))
					} else {
						box.resolve(with: .failure(XMPPError.connectionClosed))
					}
				}
				box.setContinuation(continuation)
			}
		} onCancel: {
			if box.resolve(with: .failure(CancellationError())) {
				connection.cancel()
			}
		}
	}
	
	private func appendUTF8Chunk(_ data: Data) {
		guard !data.isEmpty else { return }
		pendingUTF8Bytes.append(data)
		
		if let fullText = String(data: pendingUTF8Bytes, encoding: .utf8) {
			buffer.append(fullText)
			pendingUTF8Bytes.removeAll(keepingCapacity: true)
			return
		}
		
		let count = pendingUTF8Bytes.count
		for trim in 1...min(3, count) {
			let prefix = pendingUTF8Bytes.prefix(count - trim)
			if let text = String(data: prefix, encoding: .utf8) {
				buffer.append(text)
				pendingUTF8Bytes = Data(pendingUTF8Bytes.suffix(trim))
				return
			}
		}
		
		buffer.append(String(decoding: pendingUTF8Bytes, as: UTF8.self))
		pendingUTF8Bytes.removeAll(keepingCapacity: true)
	}
	
	private func readUntil(contains marker: String, on connection: NWConnection) async throws -> String {
		try await readUntil(anyOf: [marker], on: connection)
	}
	
	private func readUntil(anyOf markers: [String], on connection: NWConnection, timeout: TimeInterval = 12) async throws -> String {
		let deadline = Date().addingTimeInterval(timeout)
		while !markers.contains(where: { buffer.contains($0) }) {
			if buffer.contains("<stream:error") || buffer.contains("</stream:stream>") {
				throw XMPPError.connectionClosed
			}
			let remaining = deadline.timeIntervalSinceNow
			guard remaining > 0 else { throw XMPPError.timedOut("waiting for \(markers.first ?? "response")") }
			let chunk = try await receiveChunk(on: connection, timeout: remaining)
			appendUTF8Chunk(chunk)
			if buffer.utf8.count + pendingUTF8Bytes.count > maxBufferBytes {
				throw XMPPError.bufferOverflow
			}
		}
		return buffer
	}
	
	private func readIQResponse(id: String, on connection: NWConnection, timeout: TimeInterval = 12) async throws -> String {
		let deadline = Date().addingTimeInterval(timeout)
		while true {
			if let iqStart = findIQStart(containingID: id, in: buffer) {
				let closeRange: Range<String.Index>? = {
					if let openTagEnd = findTagEnd(in: buffer, from: iqStart) {
						if openTagEnd > iqStart && buffer[buffer.index(before: openTagEnd)] == "/" {
							let slashIdx = buffer.index(before: openTagEnd)
							return slashIdx..<buffer.index(after: openTagEnd)
						}
						if let closeIQ = buffer.range(of: "</iq>", range: buffer.index(after: openTagEnd)..<buffer.endIndex) {
							return closeIQ
						}
					}
					return nil
				}()
				if let closeRange {
					let stanza = String(buffer[iqStart..<closeRange.upperBound])
					buffer.removeSubrange(iqStart..<closeRange.upperBound)
					if extractAttribute("type", from: stanza) == "error" {
						throw id == "xmpp_entitlements_0"
							? XMPPError.authenticationFailed
							: XMPPError.connectionFailed("XMPP IQ error for \(id)")
					}
					return stanza
				}
			}
			if buffer.contains("<stream:error") || buffer.contains("</stream:stream>") {
				throw XMPPError.connectionClosed
			}
			let remaining = deadline.timeIntervalSinceNow
			guard remaining > 0 else { throw XMPPError.timedOut("waiting for \(id)") }
			let chunk = try await receiveChunk(on: connection, timeout: remaining)
			appendUTF8Chunk(chunk)
			if buffer.utf8.count + pendingUTF8Bytes.count > maxBufferBytes {
				throw XMPPError.bufferOverflow
			}
		}
	}
	
	private func findIQStart(containingID id: String, in xml: String) -> String.Index? {
		guard let idRange = xml.range(of: id) else { return nil }
		return xml.range(of: "<iq", options: .backwards, range: xml.startIndex..<idRange.lowerBound)?.lowerBound
	}
	
	private func runKeepaliveLoop(generation expectedGeneration: UInt64, connection: NWConnection) async {
		while isRunning && generation == expectedGeneration && !Task.isCancelled {
			try? await Task.sleep(for: .seconds(45))
			guard isRunning && generation == expectedGeneration && !Task.isCancelled else { break }
			do {
				try await sendRaw(" ", on: connection)
			} catch {
				if isRunning && generation == expectedGeneration {
					connection.cancel()
				}
				break
			}
		}
	}
	
	private func runReceiveLoop(generation expectedGeneration: UInt64, connection: NWConnection) async {
		while isRunning && generation == expectedGeneration && !Task.isCancelled {
			do {
				while let stanza = popNextStanza() {
					await handleStanza(stanza)
				}
				let chunk = try await receiveChunk(on: connection, timeout: nil)
				appendUTF8Chunk(chunk)
				if buffer.utf8.count + pendingUTF8Bytes.count > maxBufferBytes {
					throw XMPPError.bufferOverflow
				}
				if buffer.contains("</stream:stream>") {
					throw XMPPError.connectionClosed
				}
				while let stanza = popNextStanza() {
					await handleStanza(stanza)
				}
			} catch {
				if isRunning && generation == expectedGeneration {
					isRunning = false
					keepaliveTask?.cancel()
					keepaliveTask = nil
					await eventHandler?(.disconnected(error))
				}
				break
			}
		}
	}
	
	// MARK: - Stanza Extraction & Parsing
	
	private func findTagEnd(in string: String, from start: String.Index) -> String.Index? {
		var quote: Character?
		var idx = start
		while idx < string.endIndex {
			let ch = string[idx]
			if let q = quote {
				if ch == q { quote = nil }
			} else if ch == "\"" || ch == "'" {
				quote = ch
			} else if ch == ">" {
				return idx
			}
			idx = string.index(after: idx)
		}
		return nil
	}
	
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
		let openPrefix = "<\(match.tag)"
		let closeTag = "</\(match.tag)>"
		var depth = 0
		var scan = searchStart
		
		while scan < buffer.endIndex {
			guard let ltIndex = buffer.range(of: "<", range: scan..<buffer.endIndex)?.lowerBound else {
				break
			}
			if buffer[ltIndex...].hasPrefix(closeTag) {
				let afterClose = buffer.index(ltIndex, offsetBy: closeTag.count)
				depth -= 1
				if depth <= 0 {
					let stanza = String(buffer[searchStart..<afterClose])
					buffer.removeSubrange(buffer.startIndex..<afterClose)
					return stanza
				}
				scan = afterClose
				continue
			}
			if buffer[ltIndex...].hasPrefix(openPrefix) {
				let afterName = buffer.index(ltIndex, offsetBy: openPrefix.count)
				if afterName < buffer.endIndex {
					let next = buffer[afterName]
					if next == " " || next == ">" || next == "/" {
						guard let gtIndex = findTagEnd(in: buffer, from: afterName) else {
							return nil
						}
						let isSelfClosing = gtIndex > afterName && buffer[buffer.index(before: gtIndex)] == "/"
						let gtEnd = buffer.index(after: gtIndex)
						if !isSelfClosing {
							depth += 1
						} else if depth == 0 {
							let stanza = String(buffer[searchStart..<gtEnd])
							buffer.removeSubrange(buffer.startIndex..<gtEnd)
							return stanza
						}
						scan = gtEnd
						continue
					}
				}
			}
			scan = buffer.index(after: ltIndex)
		}
		return nil
	}
	
	private func handleStanza(_ stanza: String) async {
		if stanza.hasPrefix("<iq") {
			let iqID = extractAttribute("id", from: stanza) ?? ""
			let iqType = extractAttribute("type", from: stanza) ?? ""
			if stanza.contains("jabber:iq:riotgames:roster") || stanza.contains("jabber:iq:roster") {
				let isFullSnapshot = (iqType == "result" && iqID.hasPrefix("roster_request"))
				let friends = parseRosterItems(from: stanza)
				if !friends.isEmpty || isFullSnapshot {
					await eventHandler?(.rosterReceived(friends, isFullSnapshot: isFullSnapshot))
				}
			} else if stanza.contains("jabber:iq:riotgames:archive") || pendingArchivePeerByIQID[iqID] != nil {
				let trackedPeer = pendingArchivePeerByIQID.removeValue(forKey: iqID)
				if iqType == "error" {
					if let trackedPeer {
						await eventHandler?(.archiveReceived(peerJID: trackedPeer, messages: []))
					}
				} else {
					let (peer, messages) = parseArchiveMessages(from: stanza, expectedPeerJID: trackedPeer)
					if let peer {
						await eventHandler?(.archiveReceived(peerJID: peer, messages: messages))
					}
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
	
	private func parseIncomingMessage(from xml: String, expectedPeerJID: String? = nil) -> XMPPChatMessage? {
		var msgXML = xml
		var carbonForcedOutgoing: Bool? = nil
		if xml.contains("urn:xmpp:carbons:2"),
		   let outerEnd = xml.range(of: ">")?.upperBound,
		   let innerStart = xml.range(of: "<message", range: outerEnd..<xml.endIndex),
		   let innerEnd = xml.range(of: "</message>", range: innerStart.lowerBound..<xml.endIndex) {
			msgXML = String(xml[innerStart.lowerBound..<innerEnd.upperBound])
			if xml.contains("<sent") {
				carbonForcedOutgoing = true
			} else if xml.contains("<received") {
				carbonForcedOutgoing = false
			}
		}
		
		guard let rawBody = extractTagContent(from: msgXML, tag: "body") else { return nil }
		let body = unescapeXML(rawBody)
		guard !body.isEmpty else { return nil }
		
		let fromJID = (extractNestedAttribute("message", attr: "from", from: msgXML) ?? extractAttribute("from", from: msgXML) ?? "")
			.components(separatedBy: "/").first ?? ""
		let toJID = (extractNestedAttribute("message", attr: "to", from: msgXML) ?? extractAttribute("to", from: msgXML) ?? "")
			.components(separatedBy: "/").first ?? ""
		let stamp = extractNestedAttribute("message", attr: "stamp", from: msgXML)
			?? extractNestedAttribute("delay", attr: "stamp", from: msgXML)
			?? extractAttribute("stamp", from: msgXML)
		let timestamp = stamp.flatMap { parseRiotTimestamp($0) } ?? Date()
		
		let myNode = myJID.split(separator: "@").first?.lowercased()
		let fromNode = fromJID.split(separator: "@").first?.lowercased()
		let isOutgoing = carbonForcedOutgoing ?? (myNode != nil && !myNode!.isEmpty && fromNode == myNode)
		let peer = expectedPeerJID ?? (isOutgoing ? toJID : fromJID)
		guard !peer.isEmpty else { return nil }
		
		let rawID = extractNestedAttribute("message", attr: "id", from: msgXML)
		let id: String
		if let rawID, !rawID.isEmpty {
			id = rawID
		} else {
			let ms = Int64((timestamp.timeIntervalSince1970 * Double(1000)).rounded())
			id = "msg:\(peer.lowercased()):\(isOutgoing ? "o" : "i"):\(ms):\(Self.stableHashHex(body))"
		}
		return XMPPChatMessage(id: id, peerJID: peer, isOutgoing: isOutgoing, body: body, timestamp: timestamp)
	}
	
	private func parseArchiveMessages(from xml: String, expectedPeerJID: String? = nil) -> (String?, [XMPPChatMessage]) {
		let withJID = expectedPeerJID
			?? extractTagContent(from: xml, tag: "with")?.components(separatedBy: "/").first
		var messages: [XMPPChatMessage] = []
		var cursor = xml.startIndex
		while let msgStart = xml.range(of: "<message", range: cursor..<xml.endIndex) {
			let afterName = msgStart.upperBound
			guard afterName < xml.endIndex else { break }
			let next = xml[afterName]
			guard next == " " || next == ">" || next == "/" else {
				cursor = afterName
				continue
			}
			guard let firstGT = xml.range(of: ">", range: afterName..<xml.endIndex) else {
				break
			}
			if firstGT.lowerBound > afterName && xml[xml.index(before: firstGT.lowerBound)] == "/" {
				cursor = firstGT.upperBound
				continue
			}
			guard let msgEnd = xml.range(of: "</message>", range: msgStart.lowerBound..<xml.endIndex) else {
				break
			}
			let msgXML = String(xml[msgStart.lowerBound..<msgEnd.upperBound])
			cursor = msgEnd.upperBound
			if let msg = parseIncomingMessage(from: msgXML, expectedPeerJID: withJID) {
				messages.append(msg)
			}
		}
		let peer = withJID ?? messages.first?.peerJID
		return (peer, messages.sorted { $0.timestamp < $1.timestamp })
	}
	
	private static func stableHashHex(_ text: String) -> String {
		var hash: UInt64 = 14695981039346656037
		for byte in text.utf8 {
			hash ^= UInt64(byte)
			hash = hash &* 1099511628211
		}
		return String(hash, radix: 16)
	}
	
	// MARK: - Small XML Utilities
	
	private func extractTagContent(from xml: String, tag: String) -> String? {
		var searchStart = xml.startIndex
		while let openStart = xml.range(of: "<\(tag)", range: searchStart..<xml.endIndex) {
			let afterTag = openStart.upperBound
			guard afterTag < xml.endIndex else { return nil }
			let nextChar = xml[afterTag]
			if nextChar == ">" || nextChar == " " {
				guard let openEnd = findTagEnd(in: xml, from: afterTag) else { return nil }
				// Self-closing tag has no body
				if xml[xml.index(before: openEnd)] == "/" {
					return nil
				}
				let contentStart = xml.index(after: openEnd)
				guard let closeStart = xml.range(of: "</\(tag)>", range: contentStart..<xml.endIndex) else {
					return nil
				}
				return String(xml[contentStart..<closeStart.lowerBound])
			}
			searchStart = afterTag
		}
		return nil
	}
	
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
		if let d = riotMilliDateFormatter.date(from: trimmed) {
			return d
		}
		if let d = riotDateFormatter.date(from: trimmed) {
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
			  let end = findTagEnd(in: xml, from: start.lowerBound) else { return nil }
		return extractAttribute(attr, from: String(xml[start.lowerBound..<xml.index(after: end)]))
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
		if let d = try? Date(string, strategy: xmppFractionalDateStyle) { return d }
		return try? Date(string, strategy: xmppDateStyle)
	}
}
