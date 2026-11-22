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
	@State private var showingChanges = false
	
	private var client: ValorantClient? {
		accountManager.activeAccount?.client
	}
	
	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 18) {
				searchBar
				
				connectionBanner
				
				if let ownUserID = accountManager.activeAccount?.id, search.trimmingCharacters(in: .whitespaces).isEmpty {
					ownPartySection(userID: ownUserID)
				}
				
				valorantPartiesSection
				
				friendRequestsSection
				
				otherGamesSection
				
				offlineFriendsSection
				
				if socialManager.friends.isEmpty && socialManager.connectionState == .connected {
					Text("No friends returned on your Riot roster yet.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity)
						.padding(20)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Friends")
		.navigationBarTitleDisplayMode(.inline)
		.background(
			NavigationLink("", isActive: $showingChanges) {
				FriendListChangesView()
			}
			.hidden()
		)
		.toolbar {
			friendsToolbar
		}
		.refreshable {
			if let client {
				await socialManager.refreshNow(using: client)
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
	
	// MARK: - Toolbar
	
	@ToolbarContentBuilder
	private var friendsToolbar: some ToolbarContent {
		if #available(iOS 17.0, *) {
			ToolbarItem(placement: .topBarLeading) {
				NavigationLink {
					FriendListChangesView()
				} label: {
					Image(systemName: "person.badge.clock")
						.foregroundStyle(Color.accentColor)
				}
				.accessibilityLabel("Friend List Changes")
			}
		}
		
		ToolbarItemGroup(placement: .navigationBarTrailing) {
			if #unavailable(iOS 17.0) {
				NavigationLink {
					FriendListChangesView()
				} label: {
					Image(systemName: "person.badge.clock")
						.foregroundStyle(Color.accentColor)
				}
				.accessibilityLabel("Friend List Changes")
			}
			
			Button {
				friendName = ""
				friendTag = ""
				showingAddFriend = true
			} label: {
				Image(systemName: "person.badge.plus")
					.foregroundStyle(Color.accentColor)
			}
			.disabled(socialManager.connectionState != .connected)
			
			Menu {
				if let client {
					Button {
						Task { await socialManager.refreshNow(using: client) }
					} label: {
						Label("Refresh Friends", systemImage: "arrow.clockwise")
					}
					
					Button {
						Task { await socialManager.reconnect(using: client, clearExisting: false) }
					} label: {
						Label("Reconnect Chat", systemImage: "wifi")
					}
				}
				
				Button {
					showingChanges = true
				} label: {
					Label("Friend List Changes", systemImage: "person.badge.clock")
				}
			} label: {
				Image(systemName: "ellipsis")
					.foregroundStyle(Color.primary)
			}
		}
	}
	
	// MARK: - Search & Connection State
	
	private var searchBar: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.font(.subheadline)
				.foregroundStyle(.secondary)
			
			TextField("Search friends", text: $search)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
			
			if !search.isEmpty {
				Button {
					search = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(Color.secondaryGroupedBackground, in: Capsule())
	}
	
	@ViewBuilder
	private var connectionBanner: some View {
		if case .failed(let message) = socialManager.connectionState {
			HStack(spacing: 12) {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(Color.valorantRed)
				VStack(alignment: .leading, spacing: 2) {
					Text("Chat Connection Failed")
						.font(.subheadline.weight(.semibold))
					Text(message)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}
				Spacer()
				if let client {
					Button("Retry") {
						Task { await socialManager.reconnect(using: client, clearExisting: false) }
					}
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(Color.accentColor)
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		} else if client == nil {
			Text("Sign in to view friends")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(14)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		} else if socialManager.friends.isEmpty && socialManager.connectionState == .connecting {
			HStack(spacing: 10) {
				ProgressView()
					.controlSize(.small)
				Text("Connecting to Riot Chat...")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			.padding(14)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		} else if socialManager.isRefreshing {
			HStack(spacing: 8) {
				ProgressView()
					.controlSize(.small)
				Text("Refreshing roster...")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 4)
		}
	}
	
	// MARK: - Your Party
	
	@ViewBuilder
	private func ownPartySection(userID: User.ID) -> some View {
		let ownPartyID = socialManager.myPresence?.partyID
		let partyFriends: [XMPPFriend] = {
			guard let ownPartyID else { return [] }
			return socialManager.friends.filter {
				!$0.isIncomingRequest && !$0.isOutgoingRequest && $0.status != .offline && $0.partyID == ownPartyID
			}
		}()
		let size = socialManager.myPresence?.partySize ?? (1 + partyFriends.count)
		let maxSize = socialManager.myPresence?.maxPartySize ?? 5
		
		VStack(alignment: .leading, spacing: 8) {
			Text("Your Party — \(size)/\(maxSize)")
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				OwnPartyMemberRow(userID: userID, presence: socialManager.myPresence, assets: assets)
				
				ForEach(partyFriends) { member in
					Divider()
						.opacity(0.22)
						.padding(.leading, 72)
					friendPartyRow(member)
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	// MARK: - VALORANT Parties
	
	private struct PartyGroup: Identifiable {
		var id: String
		var headerTitle: String
		var members: [XMPPFriend]
		var totalSize: Int
		var maxSize: Int
		var topSortRank: XMPPFriendStatus
		var leadName: String
	}
	
	private var valorantPartyGroups: [PartyGroup] {
		let ownPartyID = socialManager.myPresence?.partyID
		let activeValFriends = socialManager.friends.filter { friend in
			guard !friend.isIncomingRequest && !friend.isOutgoingRequest && friend.status != .offline else { return false }
			if let ownPartyID, friend.partyID == ownPartyID { return false }
			return friend.gameTitle == "VALORANT" && matchesSearch(friend)
		}
		
		var buckets: [String: [XMPPFriend]] = [:]
		for friend in activeValFriends {
			let key = friend.partyID ?? "solo:\(friend.jid)"
			buckets[key, default: []].append(friend)
		}
		
		return buckets.map { key, members in
			let sortedMembers = members.sorted { lhs, rhs in
				if lhs.isPartyOwner != rhs.isPartyOwner { return lhs.isPartyOwner }
				if lhs.status != rhs.status { return lhs.status < rhs.status }
				return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
			}
			let sample = sortedMembers.first
			let totalSize = max(sortedMembers.count, sample?.partySize ?? sortedMembers.count)
			let maxSize = max(totalSize, sample?.maxPartySize ?? 5)
			let title: String
			if sample?.partyID != nil || totalSize > 1 || (sample?.maxPartySize ?? 0) > 1 {
				title = "Party — \(totalSize)/\(maxSize)"
			} else if sample?.status == .inGame {
				title = "In Game"
			} else if sample?.status == .pregame {
				title = "Agent Select"
			} else {
				title = "Party — \(totalSize)/\(maxSize)"
			}
			return PartyGroup(
				id: key,
				headerTitle: title,
				members: sortedMembers,
				totalSize: totalSize,
				maxSize: maxSize,
				topSortRank: sortedMembers.map(\.status).min() ?? .online,
				leadName: sample?.displayName ?? ""
			)
		}
		.sorted { lhs, rhs in
			if lhs.topSortRank != rhs.topSortRank {
				return lhs.topSortRank < rhs.topSortRank
			}
			if lhs.totalSize != rhs.totalSize {
				return lhs.totalSize > rhs.totalSize
			}
			return lhs.leadName.localizedCaseInsensitiveCompare(rhs.leadName) == .orderedAscending
		}
	}
	
	@ViewBuilder
	private var valorantPartiesSection: some View {
		ForEach(valorantPartyGroups) { group in
			VStack(alignment: .leading, spacing: 8) {
				Text(group.headerTitle)
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				VStack(spacing: 0) {
					ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
						friendPartyRow(member)
						
						if index < group.members.count - 1 {
							Divider()
								.opacity(0.22)
								.padding(.leading, 72)
						}
					}
					
					let hiddenCount = group.totalSize - group.members.count
					if hiddenCount > 0 {
						Divider()
							.opacity(0.22)
						
						HStack {
							Text("+ \(hiddenCount) more")
								.font(.subheadline)
								.foregroundStyle(.secondary)
							Spacer()
						}
						.padding(.horizontal, 14)
						.padding(.vertical, 12)
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	// MARK: - Friend Requests
	
	@ViewBuilder
	private var friendRequestsSection: some View {
		let incoming = socialManager.friends.filter { $0.isIncomingRequest && matchesSearch($0) }
		let outgoing = socialManager.friends.filter { $0.isOutgoingRequest && matchesSearch($0) }
		
		if !incoming.isEmpty {
			VStack(alignment: .leading, spacing: 8) {
				Text("Friend Requests — \(incoming.count)")
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				VStack(spacing: 0) {
					ForEach(Array(incoming.enumerated()), id: \.element.id) { index, friend in
						HStack(spacing: 12) {
							if let cardID = friend.playerCardID {
								PlayerCardImage.small(cardID)
									.frame(width: 44, height: 44)
									.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
							}
							
							VStack(alignment: .leading, spacing: 2) {
								nameTitle(friend)
								Text("Incoming Friend Request")
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
									.font(.title2)
									.foregroundStyle(.green)
							}
							.buttonStyle(.plain)
							
							AsyncButton {
								do {
									try await socialManager.removeFriend(friend)
								} catch {
									actionError = error.localizedDescription
								}
							} label: {
								Image(systemName: "xmark.circle.fill")
									.font(.title2)
									.foregroundStyle(Color.valorantRed)
							}
							.buttonStyle(.plain)
						}
						.padding(14)
						
						if index < incoming.count - 1 {
							Divider().opacity(0.22).padding(.leading, 70)
						}
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
		
		if !outgoing.isEmpty {
			VStack(alignment: .leading, spacing: 8) {
				Text("Sent Requests — \(outgoing.count)")
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				VStack(spacing: 0) {
					ForEach(Array(outgoing.enumerated()), id: \.element.id) { index, friend in
						HStack(spacing: 12) {
							if let cardID = friend.playerCardID {
								PlayerCardImage.small(cardID)
									.frame(width: 44, height: 44)
									.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
							}
							
							VStack(alignment: .leading, spacing: 2) {
								nameTitle(friend)
								Text("Pending")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							AsyncButton {
								do {
									try await socialManager.removeFriend(friend)
								} catch {
									actionError = error.localizedDescription
								}
							} label: {
								Text("Cancel")
									.font(.caption.weight(.semibold))
									.foregroundStyle(Color.valorantRed)
									.padding(.horizontal, 10)
									.padding(.vertical, 6)
									.background(Color.tertiaryGroupedBackground, in: Capsule())
							}
							.buttonStyle(.plain)
						}
						.padding(14)
						
						if index < outgoing.count - 1 {
							Divider().opacity(0.22).padding(.leading, 70)
						}
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	// MARK: - Other Games
	
	@ViewBuilder
	private var otherGamesSection: some View {
		let otherActive = socialManager.friends.filter { friend in
			!friend.isIncomingRequest
			&& !friend.isOutgoingRequest
			&& friend.status != .offline
			&& friend.gameTitle != "VALORANT"
			&& matchesSearch(friend)
		}
		let byGame = Dictionary(grouping: otherActive) { $0.gameTitle ?? "Online" }
		let orderedGames = byGame.keys.sorted()
		
		ForEach(orderedGames, id: \.self) { game in
			let list = byGame[game] ?? []
			VStack(alignment: .leading, spacing: 8) {
				Text("\(game) — \(list.count)")
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				VStack(spacing: 0) {
					ForEach(Array(list.enumerated()), id: \.element.id) { index, friend in
						friendPartyRow(friend)
						if index < list.count - 1 {
							Divider().opacity(0.22).padding(.leading, friend.playerCardID == nil ? 14 : 72)
						}
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	// MARK: - Offline Friends
	
	@ViewBuilder
	private var offlineFriendsSection: some View {
		let offline = socialManager.friends
			.filter {
				!$0.isIncomingRequest && !$0.isOutgoingRequest && $0.status == .offline && matchesSearch($0)
			}
			.sorted { lhs, rhs in
				switch (lhs.lastOnline, rhs.lastOnline) {
				case let (.some(l), .some(r)) where l != r:
					return l > r
				case (.some, .none):
					return true
				case (.none, .some):
					return false
				default:
					return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
				}
			}
		if !offline.isEmpty {
			VStack(alignment: .leading, spacing: 8) {
				Text("Offline — \(offline.count)")
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				VStack(spacing: 0) {
					ForEach(Array(offline.enumerated()), id: \.element.id) { index, friend in
						friendPartyRow(friend, isOfflineStyle: true)
						if index < offline.count - 1 {
							Divider().opacity(0.22).padding(.leading, friend.playerCardID == nil ? 14 : 72)
						}
					}
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	// MARK: - Friend Card Row
	
	private func friendPartyRow(_ friend: XMPPFriend, isOfflineStyle: Bool = false) -> some View {
		NavigationLink {
			ChatView(friend: friend)
		} label: {
			HStack(spacing: 12) {
				if let cardID = friend.playerCardID {
					ZStack(alignment: .bottomTrailing) {
						PlayerCardImage.small(cardID)
							.frame(width: 48, height: 48)
							.background(Color.tertiaryGroupedBackground)
							.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
							.opacity(isOfflineStyle ? 0.55 : 1)
						
						PresenceBadgeView(status: friend.status)
							.offset(x: 3, y: 3)
					}
				}
				
				VStack(alignment: .leading, spacing: 3) {
					nameTitle(friend)
					
					Text(statusHeadline(for: friend))
						.font(.subheadline)
						.foregroundStyle(isOfflineStyle ? Color.secondary : Color.primary.opacity(0.85))
						.lineLimit(1)
					
					if let detail = matchDetailLine(for: friend) {
						Text(detail)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					
					if let note = friend.note, !note.isEmpty {
						HStack(spacing: 5) {
							Image(systemName: "text.quote")
								.font(.caption2)
							Text(note)
								.lineLimit(1)
						}
						.font(.caption)
						.foregroundStyle(.secondary)
					}
				}
				
				Spacer(minLength: 8)
				
				if let unread = socialManager.unreadByJID[friend.jid], unread > 0 {
					Text("\(unread)")
						.font(.caption2.bold())
						.padding(.horizontal, 7)
						.padding(.vertical, 3)
						.background(Color.accentColor, in: Capsule())
						.foregroundStyle(.white)
				}
				
				if let tier = friend.competitiveTier, tier >= 3 {
					CompetitiveTierImage(tier: tier, time: .now)
						.frame(width: 34, height: 34)
				}
				
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 12)
			.background(alignment: .center) {
				if friend.isPartyOwner && friend.status != .offline {
					Image(systemName: "crown")
						.font(.system(size: 46, weight: .ultraLight))
						.foregroundStyle(.white.opacity(0.08))
						.offset(x: 20, y: 2)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.contextMenu {
			if let puuid = friend.puuid {
				NavigationLink {
					MatchListView(userID: puuid)
				} label: {
					Label("Open Profile", systemImage: "person.crop.circle")
				}
			}
			Button(role: .destructive) {
				Task {
					do {
						try await socialManager.removeFriend(friend)
					} catch {
						actionError = error.localizedDescription
					}
				}
			} label: {
				Label("Remove Friend", systemImage: "person.badge.minus")
			}
		}
	}
	
	private func nameTitle(_ friend: XMPPFriend) -> some View {
		HStack(spacing: 0) {
			Text(friend.gameName.isEmpty ? friend.jid : friend.gameName)
				.font(.headline.weight(.semibold))
				.foregroundStyle(.primary)
				.lineLimit(1)
			if !friend.tagLine.isEmpty {
				Text("#\(friend.tagLine)")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
	}
	
	private static let lastOnlineFormatter: DateComponentsFormatter = {
		let f = DateComponentsFormatter()
		f.allowedUnits = [.day, .hour, .minute]
		f.unitsStyle = .full
		f.maximumUnitCount = 3
		return f
	}()
	
	private static func formatLastOnline(_ date: Date) -> String {
		let elapsed = max(Double(0), Date().timeIntervalSince(date))
		if elapsed < 60 {
			return "Last online just now"
		}
		if let formatted = lastOnlineFormatter.string(from: elapsed), !formatted.isEmpty {
			return "Last online \(formatted) ago"
		}
		return "Offline"
	}
	
	private func statusHeadline(for friend: XMPPFriend) -> String {
		if let game = friend.gameTitle, game != "VALORANT" {
			if game == "Riot Client" {
				return friend.statusText ?? (friend.status == .away ? "Away" : "Online")
			}
			return friend.statusText ?? (friend.status == .away ? "Away" : "In Game")
		}
		switch friend.status {
		case .inGame:
			if let ally = friend.allyScore, let enemy = friend.enemyScore {
				return "In Game  |  \(ally) – \(enemy)"
			}
			return "In Game"
		case .pregame:
			return "Agent Select"
		case .online:
			return friend.statusText ?? "Online"
		case .away:
			return friend.statusText ?? "Away"
		case .offline:
			if let lastOnline = friend.lastOnline {
				return Self.formatLastOnline(lastOnline)
			}
			return "Offline"
		}
	}
	
	private func matchDetailLine(for friend: XMPPFriend) -> String? {
		guard friend.status == .inGame || friend.status == .pregame else {
			return nil
		}
		var parts: [String] = []
		if friend.provisioningFlow == "CustomGame" {
			parts.append("Custom")
		} else if let q = friend.queueID, !q.isEmpty {
			let qName = assets?.queues[QueueID(q)]?.name ?? formattedQueueName(q)
			parts.append(qName)
		}
		if let path = friend.mapPath, !path.isEmpty {
			let mapName = resolvedMapName(path)
			parts.append(mapName)
		}
		return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
	}
	
	private func resolvedMapName(_ path: String) -> String {
		if let match = assets?.maps[MapID(path)] {
			return match.displayName
		}
		if let match = assets?.maps.values.first(where: {
			$0.assetPath.caseInsensitiveCompare(path) == .orderedSame
			|| $0.id.rawValue.caseInsensitiveCompare(path) == .orderedSame
		}) {
			return match.displayName
		}
		let segment = path.split(separator: "/").last.map(String.init) ?? path
		return formattedQueueName(segment)
	}
	
	private func formattedQueueName(_ raw: String) -> String {
		raw.replacingOccurrences(of: "_", with: " ").capitalized
	}
	
	private func matchesSearch(_ friend: XMPPFriend) -> Bool {
		let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return true }
		return friend.displayName.localizedCaseInsensitiveContains(trimmed)
			|| (friend.note?.localizedCaseInsensitiveContains(trimmed) ?? false)
	}
}

// MARK: - Own Party Card Row

private struct OwnPartyMemberRow: View {
	let userID: User.ID
	let presence: XMPPPresenceUpdate?
	let assets: AssetCollection?
	
	@LocalData var user: User?
	@LocalData var identity: Player.Identity?
	
	init(userID: User.ID, presence: XMPPPresenceUpdate?, assets: AssetCollection?) {
		self.userID = userID
		self.presence = presence
		self.assets = assets
		self._user = .init(id: userID)
		self._identity = .init(id: userID)
	}
	
	var body: some View {
		let cardID = presence?.playerCardID ?? identity?.cardID
		let status = presence?.status ?? .online
		
		HStack(spacing: 12) {
			ZStack(alignment: .bottomTrailing) {
				PlayerCardImage.small(cardID)
					.frame(width: 48, height: 48)
					.background(Color.tertiaryGroupedBackground)
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
				
				PresenceBadgeView(status: status)
					.offset(x: 3, y: 3)
			}
			
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 0) {
					Text(user?.gameName ?? "You")
						.font(.headline.weight(.semibold))
						.lineLimit(1)
					if let tag = user?.tagLine, !tag.isEmpty {
						Text("#\(tag)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				
				Text(ownStatusText(status))
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			
			Spacer()
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.withLocalData($user, id: userID)
		.withLocalData($identity, id: userID)
	}
	
	private func ownStatusText(_ status: XMPPFriendStatus) -> String {
		switch status {
		case .inGame:
			if let ally = presence?.allyScore, let enemy = presence?.enemyScore {
				return "In Game  |  \(ally) – \(enemy)"
			}
			return "In Game"
		case .pregame:
			return "Agent Select"
		case .away:
			return "Away"
		case .online, .offline:
			return "Online"
		}
	}
}

// MARK: - Presence Dot / Minus Badge

private struct PresenceBadgeView: View {
	let status: XMPPFriendStatus
	
	var body: some View {
		ZStack {
			switch status {
			case .inGame, .pregame:
				Circle()
					.fill(Color.valorantRed)
					.frame(width: 14, height: 14)
					.overlay {
						Rectangle()
							.fill(.black.opacity(0.85))
							.frame(width: 8, height: 2.2)
							.clipShape(Capsule())
					}
			case .online:
				Circle()
					.fill(.green)
					.frame(width: 13, height: 13)
			case .away:
				Circle()
					.fill(.yellow)
					.frame(width: 13, height: 13)
			case .offline:
				Circle()
					.fill(.gray)
					.frame(width: 12, height: 12)
			}
		}
		.overlay(
			Circle()
				.stroke(Color.secondaryGroupedBackground, lineWidth: 2)
		)
	}
}

// MARK: - Valpaw-style Chat View

struct ChatView: View {
	let friend: XMPPFriend
	@EnvironmentObject private var socialManager: SocialManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var draft = ""
	@State private var sendError: String?
	@State private var showingProfile = false
	
	private var liveFriend: XMPPFriend {
		socialManager.friendsByJID[friend.jid] ?? friend
	}
	
	private var messages: [XMPPChatMessage] {
		socialManager.messagesByJID[friend.jid] ?? []
	}
	
	var body: some View {
		ZStack {
			Color.groupedBackground.ignoresSafeArea()
			
			if messages.isEmpty {
				VStack(spacing: 10) {
					Image(systemName: "bubble.left.and.bubble.right")
						.font(.system(size: 42, weight: .light))
						.foregroundStyle(.secondary)
					Text("No Messages")
						.font(.headline.weight(.bold))
					Text("Send a message to start the conversation.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}
				.padding(32)
			} else {
				ScrollViewReader { proxy in
					ScrollView {
						LazyVStack(spacing: 10) {
							ForEach(messages) { message in
								messageBubble(message)
									.id(message.id)
							}
						}
						.padding(16)
					}
					.onChange(of: messages.count) { _ in
						if let last = messages.last {
							withAnimation {
								proxy.scrollTo(last.id, anchor: .bottom)
							}
						}
					}
					.onAppear {
						if let last = messages.last {
							proxy.scrollTo(last.id, anchor: .bottom)
						}
					}
				}
			}
		}
		.background(
			Group {
				if let puuid = liveFriend.puuid {
					NavigationLink("", isActive: $showingProfile) {
						MatchListView(userID: puuid)
					}
					.hidden()
				}
			}
		)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				chatPrincipalHeader
			}
			
			ToolbarItem(placement: .navigationBarTrailing) {
				Menu {
					if liveFriend.puuid != nil {
						Button {
							showingProfile = true
						} label: {
							Label("Open Profile", systemImage: "person.crop.circle")
						}
					}
					
					Button {
						Task { await socialManager.loadHistory(for: friend.jid) }
					} label: {
						Label("Refresh Messages", systemImage: "arrow.clockwise")
					}
					
					Button(role: .destructive) {
						Task {
							try? await socialManager.removeFriend(liveFriend)
							dismiss()
						}
					} label: {
						Label("Remove Friend", systemImage: "person.badge.minus")
					}
				} label: {
					Image(systemName: "ellipsis")
				}
			}
		}
		.safeAreaInset(edge: .bottom) {
			composerPill
		}
		.onAppear {
			socialManager.activeChatJID = friend.jid
			socialManager.markRead(jid: friend.jid)
		}
		.onDisappear {
			if socialManager.activeChatJID == friend.jid {
				socialManager.activeChatJID = nil
			}
		}
		.task {
			await socialManager.loadHistory(for: friend.jid)
		}
		.alert("Message Error", isPresented: Binding(
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
	
	private var chatPrincipalHeader: some View {
		HStack(spacing: 9) {
			PlayerCardImage.small(liveFriend.playerCardID)
				.frame(width: 30, height: 30)
				.background(Color.tertiaryGroupedBackground)
				.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
			
			VStack(alignment: .leading, spacing: 1) {
				HStack(spacing: 0) {
					Text(liveFriend.gameName.isEmpty ? liveFriend.jid : liveFriend.gameName)
						.font(.subheadline.weight(.bold))
						.lineLimit(1)
					if !liveFriend.tagLine.isEmpty {
						Text("#\(liveFriend.tagLine)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				
				if let subtitle = chatStatusSubtitle {
					Text(subtitle)
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}
		}
	}
	
	private var chatStatusSubtitle: String? {
		if let game = liveFriend.gameTitle, game != "VALORANT" {
			return liveFriend.statusText ?? game
		}
		switch liveFriend.status {
		case .inGame:
			var text = "In Game"
			if let a = liveFriend.allyScore, let e = liveFriend.enemyScore {
				text += "  |  \(a) – \(e)"
			}
			if let map = chatMatchDetail {
				text += "  ·  \(map)"
			}
			return text
		case .pregame:
			return chatMatchDetail.map { "Agent Select  ·  \($0)" } ?? "Agent Select"
		case .online:
			return "Online"
		case .away:
			return "Away"
		case .offline:
			return "Offline"
		}
	}
	
	private var chatMatchDetail: String? {
		var parts: [String] = []
		if liveFriend.provisioningFlow == "CustomGame" {
			parts.append("Custom")
		} else if let q = liveFriend.queueID, !q.isEmpty {
			parts.append(assets?.queues[QueueID(q)]?.name ?? q.replacingOccurrences(of: "_", with: " ").capitalized)
		}
		if let path = liveFriend.mapPath, !path.isEmpty {
			let name = assets?.maps[MapID(path)]?.displayName
				?? assets?.maps.values.first(where: { $0.assetPath.caseInsensitiveCompare(path) == .orderedSame })?.displayName
				?? path.split(separator: "/").last.map(String.init)?.capitalized
				?? path
			parts.append(name)
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}
	
	private var composerPill: some View {
		HStack(spacing: 8) {
			TextField("Message", text: $draft, axis: .vertical)
				.lineLimit(1...4)
				.padding(.leading, 14)
				.padding(.vertical, 9)
			
			let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			Button {
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
			} label: {
				Image(systemName: "arrow.up")
					.font(.subheadline.weight(.bold))
					.foregroundStyle(.white)
					.frame(width: 30, height: 30)
					.background(canSend ? Color.accentColor : Color.white.opacity(0.18), in: Circle())
			}
			.disabled(!canSend)
			.padding(.trailing, 5)
		}
		.background(.ultraThinMaterial, in: Capsule())
		.overlay(
			Capsule()
				.stroke(Color.white.opacity(0.14), lineWidth: 1)
		)
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
	}
	
	private func messageBubble(_ message: XMPPChatMessage) -> some View {
		HStack {
			if message.isOutgoing { Spacer(minLength: 44) }
			
			VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
				Text(message.body)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.background(
						message.isOutgoing ? Color.accentColor : Color.secondaryGroupedBackground,
						in: RoundedRectangle(cornerRadius: 14, style: .continuous)
					)
					.foregroundStyle(.primary)
				
				Text(message.timestamp, style: .time)
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			
			if !message.isOutgoing { Spacer(minLength: 44) }
		}
	}
}

// MARK: - Friend List Changes View

struct FriendListChangesView: View {
	@EnvironmentObject private var socialManager: SocialManager
	@EnvironmentObject private var accountManager: AccountManager
	
	private static let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
	
	var body: some View {
		let cutoff = Date().addingTimeInterval(-Self.thirtyDays)
		let last30 = socialManager.changeEvents.filter { $0.timestamp >= cutoff }
		let leftCount = last30.filter { $0.kind == .removedFriend }.count
		let acceptedCount = last30.filter { $0.kind == .acceptedRequest }.count
		let noLongerPendingCount = last30.filter { $0.kind == .requestNoLongerPending }.count
		
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				summaryCard(
					left: leftCount,
					accepted: acceptedCount,
					noLongerPending: noLongerPendingCount
				)
				
				if socialManager.changeEvents.isEmpty {
					VStack(spacing: 8) {
						Image(systemName: "person.badge.clock")
							.font(.system(size: 36, weight: .light))
							.foregroundStyle(.secondary)
						Text("No Friend List Changes Yet")
							.font(.headline.weight(.bold))
						Text("When someone leaves your friend list or responds to your friend request, it will appear here automatically.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}
					.frame(maxWidth: .infinity)
					.padding(24)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
				} else {
					ForEach(groupedSections, id: \.title) { section in
						VStack(alignment: .leading, spacing: 8) {
							Text(section.title)
								.font(.headline.weight(.bold))
								.padding(.horizontal, 4)
							
							VStack(spacing: 0) {
								ForEach(Array(section.events.enumerated()), id: \.element.id) { index, event in
									changeEventRow(event)
									if index < section.events.count - 1 {
										Divider().opacity(0.22).padding(.leading, 64)
									}
								}
							}
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
						}
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Friend List Changes")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if let client = accountManager.activeAccount?.client {
				ToolbarItem(placement: .navigationBarTrailing) {
					AsyncButton {
						await socialManager.refreshNow(using: client)
					} label: {
						Image(systemName: "arrow.clockwise")
					}
				}
			}
		}
	}
	
	private func summaryCard(left: Int, accepted: Int, noLongerPending: Int) -> some View {
		VStack(alignment: .leading, spacing: 14) {
			VStack(alignment: .leading, spacing: 6) {
				Text("Watching \(socialManager.confirmedFriendCount) friends")
					.font(.title2.weight(.bold))
				
				let pendingCount = socialManager.outgoingRequestCount
				let reqLabel = pendingCount == 1 ? "1 friend request" : "\(pendingCount) friend requests"
				let checked = checkedRelativeString
				Text("and \(reqLabel) you sent · Checked \(checked)")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			
			Divider().opacity(0.25)
			
			Text("Last 30 Days")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
			
			HStack(alignment: .top, spacing: 12) {
				summaryStat(value: left, label: "Left")
				summaryStat(value: accepted, label: "Accepted")
				summaryStat(value: noLongerPending, label: "No longer\npending")
			}
		}
		.padding(18)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func summaryStat(value: Int, label: String) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("\(value)")
				.font(.title3.weight(.bold).monospacedDigit())
			Text(label)
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
	
	private var checkedRelativeString: String {
		guard let date = socialManager.lastSyncedAt else { return "just now" }
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter.localizedString(for: date, relativeTo: .now)
	}
	
	private struct EventGroup {
		var title: String
		var events: [FriendListChangeEvent]
	}
	
	private var groupedSections: [EventGroup] {
		let cal = Calendar.current
		let now = Date()
		let weekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
		
		var today: [FriendListChangeEvent] = []
		var thisWeek: [FriendListChangeEvent] = []
		var older: [FriendListChangeEvent] = []
		
		for event in socialManager.changeEvents.sorted(by: { $0.timestamp > $1.timestamp }) {
			if cal.isDateInToday(event.timestamp) {
				today.append(event)
			} else if event.timestamp >= weekAgo {
				thisWeek.append(event)
			} else {
				older.append(event)
			}
		}
		
		var groups: [EventGroup] = []
		if !today.isEmpty { groups.append(EventGroup(title: "Today", events: today)) }
		if !thisWeek.isEmpty { groups.append(EventGroup(title: "This Week", events: thisWeek)) }
		if !older.isEmpty { groups.append(EventGroup(title: "Older", events: older)) }
		return groups
	}
	
	@ViewBuilder
	private func changeEventRow(_ event: FriendListChangeEvent) -> some View {
		if let puuid = event.puuid {
			NavigationLink {
				MatchListView(userID: puuid)
			} label: {
				eventRowContent(event, hasLink: true)
			}
			.buttonStyle(.plain)
		} else {
			eventRowContent(event, hasLink: false)
		}
	}
	
	private func eventRowContent(_ event: FriendListChangeEvent, hasLink: Bool) -> some View {
		HStack(spacing: 12) {
			ZStack {
				Circle()
					.fill(iconColor(for: event.kind).opacity(0.22))
					.frame(width: 36, height: 36)
				Image(systemName: iconName(for: event.kind))
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(iconColor(for: event.kind))
			}
			
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 0) {
					Text(event.gameName.isEmpty ? event.jid : event.gameName)
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.primary)
						.lineLimit(1)
					if !event.tagLine.isEmpty {
						Text("#\(event.tagLine)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				
				Text(subtitle(for: event.kind))
					.font(.caption)
					.foregroundStyle(.secondary)
				
				Text(eventRelativeString(event.timestamp))
					.font(.caption2)
					.foregroundStyle(.secondary.opacity(0.85))
			}
			
			Spacer()
			
			if hasLink {
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
		}
		.padding(14)
		.contentShape(Rectangle())
	}
	
	private func iconName(for kind: FriendChangeKind) -> String {
		switch kind {
		case .acceptedRequest: return "person.badge.checkmark"
		case .removedFriend: return "person.fill.badge.minus"
		case .requestNoLongerPending: return "person.fill.xmark"
		case .addedFriend: return "person.fill.badge.plus"
		}
	}
	
	private func iconColor(for kind: FriendChangeKind) -> Color {
		switch kind {
		case .acceptedRequest: return .green
		case .removedFriend: return .secondary
		case .requestNoLongerPending: return .secondary
		case .addedFriend: return Color.accentColor
		}
	}
	
	private func subtitle(for kind: FriendChangeKind) -> String {
		switch kind {
		case .acceptedRequest: return "Accepted your friend request"
		case .removedFriend: return "No longer on your friend list"
		case .requestNoLongerPending: return "Friend request no longer pending"
		case .addedFriend: return "Added to your friend list"
		}
	}
	
	private func eventRelativeString(_ date: Date) -> String {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter.localizedString(for: date, relativeTo: .now)
	}
}
