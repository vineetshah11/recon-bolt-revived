import SwiftUI
import ValorantAPI

struct FriendsView: View {
	@EnvironmentObject private var socialManager: SocialManager
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var settings: AppSettings
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	
	private static let collapsedSectionsDefaultsKey = "Social.collapsedFriendSections"
	
	private enum SectionKey {
		static let pinned = "pinned"
		static let offline = "offline"
		static let incomingRequests = "requests:incoming"
		static let outgoingRequests = "requests:outgoing"
		static func otherGame(_ game: String) -> String { "game:\(game)" }
	}
	
	private static func loadCollapsedSections() -> Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: collapsedSectionsDefaultsKey) ?? [])
	}
	
	@State private var search = ""
	@State private var showingAddFriend = false
	@State private var friendName = ""
	@State private var friendTag = ""
	@State private var actionError: String?
	@State private var showingChanges = false
	@State private var contextChatFriend: XMPPFriend?
	@State private var contextProfileUserID: User.ID?
	@State private var editingNoteFriend: XMPPFriend?
	@State private var showingNotesManager = false
	@State private var collapsedSections: Set<String> = Self.loadCollapsedSections()
	@State private var lastSectionsKey: SectionsKey?
	@State private var cachedSections = FriendSectionsSnapshot()
	
	private struct SectionsKey: Equatable {
		var friendsRevision: Int
		var pinnedJIDs: Set<String>
		var ownPartyID: String?
		var search: String
		var sortOrder: AppSettings.FriendsSortOrder
		var sortOfflineByLastSeen: Bool
	}
	
	private struct OtherGameGroup: Identifiable {
		var id: String { game }
		var game: String
		var members: [XMPPFriend]
	}
	
	private struct FriendSectionsSnapshot {
		var partyFriends: [XMPPFriend] = []
		var pinned: [XMPPFriend] = []
		var valorantPartyGroups: [PartyGroup] = []
		var incoming: [XMPPFriend] = []
		var outgoing: [XMPPFriend] = []
		var otherGameGroups: [OtherGameGroup] = []
		var offline: [XMPPFriend] = []
	}
	
	private var client: ValorantClient? {
		accountManager.activeAccount?.client
	}
	
	private var sectionsKey: SectionsKey {
		SectionsKey(
			friendsRevision: socialManager.friendsRevision,
			pinnedJIDs: socialManager.pinnedFriendJIDs,
			ownPartyID: socialManager.myPresence?.partyID,
			search: search,
			sortOrder: settings.friendsSortOrder,
			sortOfflineByLastSeen: settings.sortOfflineByLastSeen
		)
	}
	
	var body: some View {
		let currentTiers = seasons?.currentTiers()
		let isSearching = !trimmedSearch.isEmpty
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 18) {
				searchBar
				
				connectionBanner
				
				if let ownUserID = accountManager.activeAccount?.id, !isSearching {
					ownPartySection(userID: ownUserID, currentTiers: currentTiers)
				}
				
				pinnedFriendsSection(currentTiers: currentTiers, isSearching: isSearching)
				
				valorantPartiesSection(currentTiers: currentTiers)
				
				otherGamesSection(currentTiers: currentTiers, isSearching: isSearching)
				
				offlineFriendsSection(currentTiers: currentTiers, isSearching: isSearching)
				
				friendRequestsSection(isSearching: isSearching)
				
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
			HStack {
				NavigationLink("", isActive: $showingChanges) {
					FriendListChangesView()
				}
				NavigationLink("", isActive: Binding(
					get: { contextChatFriend != nil },
					set: { if !$0 { contextChatFriend = nil } }
				)) {
					if let friend = contextChatFriend {
						ChatView(friend: friend)
					}
				}
				NavigationLink("", isActive: Binding(
					get: { contextProfileUserID != nil },
					set: { if !$0 { contextProfileUserID = nil } }
				)) {
					if let userID = contextProfileUserID {
						MatchListView(userID: userID)
					}
				}
			}
			.frame(width: 0, height: 0)
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
		.onAppear {
			if lastSectionsKey == nil {
				recomputeSections(for: sectionsKey)
			}
		}
		.task {
			await socialManager.connectIfNeeded(using: client)
		}
		.task(id: sectionsKey) {
			recomputeSections(for: sectionsKey)
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
		.sheet(item: $editingNoteFriend) { friend in
			FriendNoteEditorSheet(friend: friend)
		}
		.sheet(isPresented: $showingNotesManager) {
			FriendNotesManagerSheet()
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
				Menu {
					Picker("Sort By", selection: $settings.friendsSortOrder) {
						ForEach(AppSettings.FriendsSortOrder.allCases, id: \.self) { order in
							Label(order.title, systemImage: order.icon)
								.tag(order)
						}
					}
				} label: {
					Label("Sort: \(settings.friendsSortOrder.shortTitle)", systemImage: "arrow.up.arrow.down")
				}
				
				Toggle(isOn: $settings.openProfileDirectly) {
					Label("Open Profile Directly", systemImage: "person.crop.circle")
				}
				
				Divider()
				
				let activeKeys = activeCollapsibleSectionKeys
				if !activeKeys.isEmpty && trimmedSearch.isEmpty {
					let expandAll = activeKeys.contains { collapsedSections.contains($0) }
					Button {
						toggleAllCollapsibleSections()
					} label: {
						Label(
							expandAll ? "Expand All Sections" : "Collapse All Sections",
							systemImage: expandAll ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
						)
					}
					
					Divider()
				}
				
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
					showingNotesManager = true
				} label: {
					Label("Friend Notes", systemImage: "note.text")
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
	
	// MARK: - Collapsible Sections
	
	private func isSectionCollapsed(_ key: String, isSearching: Bool) -> Bool {
		!isSearching && collapsedSections.contains(key)
	}
	
	private func toggleSection(_ key: String) {
		withAnimation(.easeInOut(duration: 0.18)) {
			if !collapsedSections.insert(key).inserted {
				collapsedSections.remove(key)
			}
		}
		UserDefaults.standard.set(Array(collapsedSections), forKey: Self.collapsedSectionsDefaultsKey)
	}
	
	private var activeCollapsibleSectionKeys: [String] {
		var keys: [String] = []
		if !cachedSections.pinned.isEmpty {
			keys.append(SectionKey.pinned)
		}
		for group in cachedSections.otherGameGroups {
			keys.append(SectionKey.otherGame(group.game))
		}
		if !cachedSections.offline.isEmpty {
			keys.append(SectionKey.offline)
		}
		if !cachedSections.incoming.isEmpty {
			keys.append(SectionKey.incomingRequests)
		}
		if !cachedSections.outgoing.isEmpty {
			keys.append(SectionKey.outgoingRequests)
		}
		return keys
	}
	
	private func toggleAllCollapsibleSections() {
		let activeKeys = activeCollapsibleSectionKeys
		guard !activeKeys.isEmpty else { return }
		let shouldExpand = activeKeys.contains { collapsedSections.contains($0) }
		withAnimation(.easeInOut(duration: 0.18)) {
			if shouldExpand {
				collapsedSections.subtract(activeKeys)
			} else {
				collapsedSections.formUnion(activeKeys)
			}
		}
		UserDefaults.standard.set(Array(collapsedSections), forKey: Self.collapsedSectionsDefaultsKey)
	}
	
	@ViewBuilder
	private func collapsibleFriendSection<Content: View>(
		key: String,
		title: String,
		isSearching: Bool,
		@ViewBuilder content: () -> Content
	) -> some View {
		let collapsed = isSectionCollapsed(key, isSearching: isSearching)
		VStack(alignment: .leading, spacing: collapsed ? 0 : 8) {
			CollapsibleSectionHeader(
				title: title,
				isCollapsed: collapsed,
				isForcedExpanded: isSearching,
				onToggle: { toggleSection(key) }
			)
			.equatable()
			
			if !collapsed {
				LazyVStack(spacing: 0) {
					content()
				}
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			}
		}
	}
	
	@ViewBuilder
	private func friendCardRows(
		_ list: [XMPPFriend],
		currentTiers: CompetitiveTier.Collection?
	) -> some View {
		let lastID = list.last?.id
		ForEach(list) { friend in
			friendPartyRow(friend, isOfflineStyle: friend.status == .offline, currentTiers: currentTiers)
			if friend.id != lastID {
				Divider()
					.opacity(0.22)
					.padding(.leading, friend.playerCardID == nil ? 14 : 72)
			}
		}
	}
	
	@ViewBuilder
	private func friendRequestRows(_ list: [XMPPFriend], isIncoming: Bool) -> some View {
		let lastID = list.last?.id
		ForEach(list) { friend in
			friendRequestRow(friend, isIncoming: isIncoming)
			if friend.id != lastID {
				Divider().opacity(0.22).padding(.leading, 70)
			}
		}
	}
	
	// MARK: - Sections Snapshot
	
	private func recomputeSections(for key: SectionsKey) {
		guard lastSectionsKey != key else { return }
		lastSectionsKey = key
		let query = key.search.isEmpty ? "" : key.search.trimmingCharacters(in: .whitespacesAndNewlines)
		let rawOwnPartyID = key.ownPartyID
		let effectiveOwnPartyID = query.isEmpty ? rawOwnPartyID : nil
		
		var partyFriends: [XMPPFriend] = []
		var pinned: [XMPPFriend] = []
		var valorantBuckets: [String: [XMPPFriend]] = [:]
		var incoming: [XMPPFriend] = []
		var outgoing: [XMPPFriend] = []
		var otherBuckets: [String: [XMPPFriend]] = [:]
		var offline: [XMPPFriend] = []
		
		for friend in socialManager.friends {
			let matches = matchesSearch(friend, query: query)
			if friend.isIncomingRequest {
				if matches { incoming.append(friend) }
				continue
			}
			if friend.isOutgoingRequest {
				if matches { outgoing.append(friend) }
				continue
			}
			
			let inEffectiveOwnParty = (effectiveOwnPartyID != nil && friend.status != .offline && friend.partyID == effectiveOwnPartyID)
			if inEffectiveOwnParty {
				partyFriends.append(friend)
			}
			
			guard matches else { continue }
			
			if socialManager.isPinned(friend) {
				if !inEffectiveOwnParty {
					pinned.append(friend)
				}
				continue
			}
			
			if friend.status == .offline {
				offline.append(friend)
			} else if friend.gameTitle == "VALORANT" {
				if let rawOwnPartyID, friend.partyID == rawOwnPartyID {
					continue
				}
				let bucketKey = friend.partyID ?? "solo:\(friend.jid)"
				valorantBuckets[bucketKey, default: []].append(friend)
			} else {
				otherBuckets[friend.gameTitle ?? "Online", default: []].append(friend)
			}
		}
		
		pinned.sort { lhs, rhs in
			let lhsOffline = lhs.status == .offline
			let rhsOffline = rhs.status == .offline
			if lhsOffline != rhsOffline {
				return !lhsOffline
			}
			return compareFriends(lhs, rhs, isOffline: lhsOffline, sortOrder: key.sortOrder, sortOfflineByLastSeen: key.sortOfflineByLastSeen)
		}
		
		let partyGroups: [PartyGroup] = valorantBuckets.compactMap { bucketKey, members in
			let sortedMembers = members.sorted { lhs, rhs in
				if key.sortOrder == .defaultOrder, lhs.isPartyOwner != rhs.isPartyOwner {
					return lhs.isPartyOwner
				}
				return compareFriends(lhs, rhs, isOffline: false, sortOrder: key.sortOrder, sortOfflineByLastSeen: key.sortOfflineByLastSeen)
			}
			guard let sample = sortedMembers.first else { return nil }
			let totalSize = max(sortedMembers.count, sample.partySize ?? sortedMembers.count)
			let maxSize = max(totalSize, sample.maxPartySize ?? 5)
			let title: String
			if sample.partyID != nil || totalSize > 1 || (sample.maxPartySize ?? 0) > 1 {
				title = "Party — \(totalSize)/\(maxSize)"
			} else if sample.status == .inGame {
				title = "In Game"
			} else if sample.status == .pregame {
				title = "Agent Select"
			} else {
				title = "Party — \(totalSize)/\(maxSize)"
			}
			return PartyGroup(
				id: bucketKey,
				headerTitle: title,
				members: sortedMembers,
				totalSize: totalSize,
				maxSize: maxSize,
				topSortRank: sortedMembers.map(\.status).min() ?? .online,
				leadFriend: sample
			)
		}
		.sorted { lhs, rhs in
			switch key.sortOrder {
			case .alphabeticalAsc:
				return XMPPFriend.compareNames(lhs.leadFriend, rhs.leadFriend)
			case .alphabeticalDesc:
				return XMPPFriend.compareNames(rhs.leadFriend, lhs.leadFriend)
			case .rank:
				let lRank = lhs.members.compactMap(\.competitiveTier).max() ?? -1
				let rRank = rhs.members.compactMap(\.competitiveTier).max() ?? -1
				if lRank != rRank { return lRank > rRank }
			case .level:
				let lLevel = lhs.members.compactMap(\.accountLevel).max() ?? -1
				let rLevel = rhs.members.compactMap(\.accountLevel).max() ?? -1
				if lLevel != rLevel { return lLevel > rLevel }
			case .defaultOrder, .lastSeen:
				break
			}
			if lhs.topSortRank != rhs.topSortRank {
				return lhs.topSortRank < rhs.topSortRank
			}
			if lhs.totalSize != rhs.totalSize {
				return lhs.totalSize > rhs.totalSize
			}
			return XMPPFriend.compareNames(lhs.leadFriend, rhs.leadFriend)
		}
		
		let otherGameGroups: [OtherGameGroup] = otherBuckets.keys.sorted().map { game in
			let sorted = (otherBuckets[game] ?? []).sorted {
				compareFriends($0, $1, isOffline: false, sortOrder: key.sortOrder, sortOfflineByLastSeen: key.sortOfflineByLastSeen)
			}
			return OtherGameGroup(game: game, members: sorted)
		}
		
		incoming.sort(by: XMPPFriend.compareNames)
		outgoing.sort(by: XMPPFriend.compareNames)
		offline.sort {
			compareFriends($0, $1, isOffline: true, sortOrder: key.sortOrder, sortOfflineByLastSeen: key.sortOfflineByLastSeen)
		}
		
		cachedSections = FriendSectionsSnapshot(
			partyFriends: partyFriends,
			pinned: pinned,
			valorantPartyGroups: partyGroups,
			incoming: incoming,
			outgoing: outgoing,
			otherGameGroups: otherGameGroups,
			offline: offline
		)
	}
	
	// MARK: - Your Party
	
	@ViewBuilder
	private func ownPartySection(userID: User.ID, currentTiers: CompetitiveTier.Collection?) -> some View {
		let partyFriends = cachedSections.partyFriends
		let size = socialManager.myPresence?.partySize ?? (1 + partyFriends.count)
		let maxSize = socialManager.myPresence?.maxPartySize ?? 5
		
		VStack(alignment: .leading, spacing: 8) {
			Text("Your Party — \(size)/\(maxSize)")
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			LazyVStack(spacing: 0) {
				OwnPartyMemberRow(userID: userID, presence: socialManager.myPresence, assets: assets)
				
				ForEach(partyFriends) { member in
					Divider()
						.opacity(0.22)
						.padding(.leading, 72)
					friendPartyRow(member, isOfflineStyle: false, currentTiers: currentTiers)
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	// MARK: - Pinned Friends
	
	@ViewBuilder
	private func pinnedFriendsSection(currentTiers: CompetitiveTier.Collection?, isSearching: Bool) -> some View {
		let pinned = cachedSections.pinned
		if !pinned.isEmpty {
			collapsibleFriendSection(
				key: SectionKey.pinned,
				title: "Pinned — \(pinned.count)",
				isSearching: isSearching
			) {
				friendCardRows(pinned, currentTiers: currentTiers)
			}
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
		var leadFriend: XMPPFriend
	}
	
	@ViewBuilder
	private func valorantPartiesSection(currentTiers: CompetitiveTier.Collection?) -> some View {
		ForEach(cachedSections.valorantPartyGroups) { group in
			VStack(alignment: .leading, spacing: 8) {
				Text(group.headerTitle)
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				LazyVStack(spacing: 0) {
					friendCardRows(group.members, currentTiers: currentTiers)
					
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
	private func friendRequestsSection(isSearching: Bool) -> some View {
		let incoming = cachedSections.incoming
		let outgoing = cachedSections.outgoing
		
		if !incoming.isEmpty {
			collapsibleFriendSection(
				key: SectionKey.incomingRequests,
				title: "Incoming Requests — \(incoming.count)",
				isSearching: isSearching
			) {
				friendRequestRows(incoming, isIncoming: true)
			}
		}
		
		if !outgoing.isEmpty {
			collapsibleFriendSection(
				key: SectionKey.outgoingRequests,
				title: "Outgoing Requests — \(outgoing.count)",
				isSearching: isSearching
			) {
				friendRequestRows(outgoing, isIncoming: false)
			}
		}
	}
	
	private func friendRequestRow(_ friend: XMPPFriend, isIncoming: Bool) -> some View {
		let profileID = friend.resolvedUserID
		
		return HStack(spacing: 12) {
			Button {
				if let profileID {
					contextProfileUserID = profileID
				}
			} label: {
				HStack(spacing: 12) {
					requestAvatar(friend, isIncoming: isIncoming)
					
					VStack(alignment: .leading, spacing: 3) {
						HStack(spacing: 4) {
							FriendNameTitleView(friend: friend, isPinned: false)
							if profileID != nil {
								Image(systemName: "chevron.right")
									.font(.caption2.weight(.semibold))
									.foregroundStyle(.tertiary)
							}
						}
						Text(isIncoming ? "Incoming Friend Request" : "Outgoing Request · Pending")
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					
					Spacer(minLength: 4)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.disabled(profileID == nil)
			
			if isIncoming {
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
				.accessibilityLabel("Accept Friend Request")
				
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
				.accessibilityLabel("Decline Friend Request")
			} else {
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
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.contextMenu {
			if let profileID {
				Button {
					contextProfileUserID = profileID
				} label: {
					Label("Open Profile", systemImage: "person.crop.circle")
				}
			}
			
			if isIncoming {
				Button {
					Task {
						do {
							try await socialManager.acceptFriend(friend)
						} catch {
							actionError = error.localizedDescription
						}
					}
				} label: {
					Label("Accept Request", systemImage: "checkmark.circle")
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
					Label("Decline Request", systemImage: "xmark.circle")
				}
			} else {
				Button(role: .destructive) {
					Task {
						do {
							try await socialManager.removeFriend(friend)
						} catch {
							actionError = error.localizedDescription
						}
					}
				} label: {
					Label("Cancel Request", systemImage: "xmark.circle")
				}
			}
		}
	}
	
	@ViewBuilder
	private func requestAvatar(_ friend: XMPPFriend, isIncoming: Bool) -> some View {
		if let cardID = friend.playerCardID {
			PlayerCardImage.small(cardID)
				.frame(width: 44, height: 44)
				.background(Color.tertiaryGroupedBackground)
				.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
		} else {
			ZStack {
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.fill(Color.tertiaryGroupedBackground)
					.frame(width: 44, height: 44)
				Image(systemName: isIncoming ? "person.badge.plus" : "paperplane.fill")
					.font(.system(size: 17, weight: .semibold))
					.foregroundStyle(isIncoming ? Color.accentColor : Color.secondary)
			}
		}
	}
	
	// MARK: - Other Games
	
	@ViewBuilder
	private func otherGamesSection(currentTiers: CompetitiveTier.Collection?, isSearching: Bool) -> some View {
		ForEach(cachedSections.otherGameGroups) { group in
			collapsibleFriendSection(
				key: SectionKey.otherGame(group.game),
				title: "\(group.game) — \(group.members.count)",
				isSearching: isSearching
			) {
				friendCardRows(group.members, currentTiers: currentTiers)
			}
		}
	}
	
	// MARK: - Offline Friends
	
	@ViewBuilder
	private func offlineFriendsSection(currentTiers: CompetitiveTier.Collection?, isSearching: Bool) -> some View {
		let offline = cachedSections.offline
		if !offline.isEmpty {
			collapsibleFriendSection(
				key: SectionKey.offline,
				title: "Offline — \(offline.count)",
				isSearching: isSearching
			) {
				friendCardRows(offline, currentTiers: currentTiers)
			}
		}
	}
	
	// MARK: - Sorting
	
	private func compareFriends(
		_ lhs: XMPPFriend,
		_ rhs: XMPPFriend,
		isOffline: Bool,
		sortOrder: AppSettings.FriendsSortOrder,
		sortOfflineByLastSeen: Bool
	) -> Bool {
		let tieBreak: () -> Bool = {
			if isOffline {
				return compareByLastOnlineOrName(lhs, rhs)
			}
			if lhs.status != rhs.status {
				return lhs.status < rhs.status
			}
			return XMPPFriend.compareNames(lhs, rhs)
		}
		
		switch sortOrder {
		case .defaultOrder:
			if isOffline {
				return sortOfflineByLastSeen
					? compareByLastOnlineOrName(lhs, rhs)
					: XMPPFriend.compareNames(lhs, rhs)
			}
			if lhs.status != rhs.status { return lhs.status < rhs.status }
			return XMPPFriend.compareNames(lhs, rhs)
		case .alphabeticalAsc:
			return XMPPFriend.compareNames(lhs, rhs)
		case .alphabeticalDesc:
			return XMPPFriend.compareNames(rhs, lhs)
		case .lastSeen:
			return tieBreak()
		case .rank:
			let lRank = lhs.competitiveTier ?? -1
			let rRank = rhs.competitiveTier ?? -1
			if lRank != rRank { return lRank > rRank }
			return tieBreak()
		case .level:
			let lLevel = lhs.accountLevel ?? -1
			let rLevel = rhs.accountLevel ?? -1
			if lLevel != rLevel { return lLevel > rLevel }
			return tieBreak()
		}
	}
	
	private func compareByLastOnlineOrName(_ lhs: XMPPFriend, _ rhs: XMPPFriend) -> Bool {
		switch (lhs.lastOnline, rhs.lastOnline) {
		case let (.some(l), .some(r)) where l != r:
			return l > r
		case (.some, .none):
			return true
		case (.none, .some):
			return false
		default:
			return XMPPFriend.compareNames(lhs, rhs)
		}
	}
	
	// MARK: - Friend Card Row
	
	private func friendPartyRow(
		_ friend: XMPPFriend,
		isOfflineStyle: Bool = false,
		currentTiers: CompetitiveTier.Collection?
	) -> some View {
		let unreadCount = socialManager.unreadByJID[friend.jid] ?? 0
		let isPinned = socialManager.isPinned(friend)
		let openProfileDirectly = settings.openProfileDirectly && unreadCount == 0 && friend.resolvedUserID != nil
		let matchDetail = matchDetailLine(for: friend)
		let tierIcon = friend.competitiveTier.flatMap { $0 >= 3 ? currentTiers?.tier($0)?.icon : nil }
		
		return FriendCardRowView(
			friend: friend,
			isOfflineStyle: isOfflineStyle,
			isPinned: isPinned,
			unreadCount: unreadCount,
			openProfileDirectly: openProfileDirectly,
			matchDetail: matchDetail,
			tierIcon: tierIcon,
			onPrimaryTap: {
				if openProfileDirectly, let profileID = friend.resolvedUserID {
					contextProfileUserID = profileID
				} else {
					contextChatFriend = friend
				}
			},
			onTogglePin: {
				withAnimation {
					socialManager.togglePinned(jid: friend.jid)
				}
			},
			onOpenChat: {
				contextChatFriend = friend
			},
			onOpenProfile: {
				if let profileID = friend.resolvedUserID {
					contextProfileUserID = profileID
				}
			},
			onEditNote: {
				editingNoteFriend = friend
			},
			onRemove: {
				Task {
					do {
						try await socialManager.removeFriend(friend)
					} catch {
						actionError = error.localizedDescription
					}
				}
			}
		)
		.equatable()
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
		if let match = assets?.mapInfo(for: path) {
			return match.displayName
		}
		let segment = path.split(separator: "/").last.map(String.init) ?? path
		return formattedQueueName(segment)
	}
	
	private func formattedQueueName(_ raw: String) -> String {
		raw.replacingOccurrences(of: "_", with: " ").capitalized
	}
	
	private var trimmedSearch: String {
		search.isEmpty ? "" : search.trimmingCharacters(in: .whitespacesAndNewlines)
	}
	
	private func matchesSearch(_ friend: XMPPFriend, query: String) -> Bool {
		guard !query.isEmpty else { return true }
		if friend.gameName.localizedCaseInsensitiveContains(query)
			|| friend.tagLine.localizedCaseInsensitiveContains(query)
			|| (friend.note?.localizedCaseInsensitiveContains(query) ?? false) {
			return true
		}
		if friend.gameName.isEmpty && friend.jid.localizedCaseInsensitiveContains(query) {
			return true
		}
		if !friend.tagLine.isEmpty && query.contains("#") {
			return friend.displayName.localizedCaseInsensitiveContains(query)
		}
		return false
	}
}

// MARK: - Section Header & Friend Row Subviews

private struct CollapsibleSectionHeader: View, Equatable {
	let title: String
	let isCollapsed: Bool
	let isForcedExpanded: Bool
	let onToggle: () -> Void
	
	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.title == rhs.title
			&& lhs.isCollapsed == rhs.isCollapsed
			&& lhs.isForcedExpanded == rhs.isForcedExpanded
	}
	
	var body: some View {
		Button(action: onToggle) {
			HStack(spacing: 6) {
				Text(title)
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.secondary)
				
				Spacer(minLength: 8)
				
				if !isForcedExpanded {
					Image(systemName: "chevron.down")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.tertiary)
						.rotationEffect(.degrees(isCollapsed ? -90 : 0))
						.animation(.easeInOut(duration: 0.18), value: isCollapsed)
				}
			}
			.padding(.horizontal, 4)
			.padding(.vertical, 2)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(isForcedExpanded)
	}
}

private struct FriendNameTitleView: View {
	let friend: XMPPFriend
	let isPinned: Bool
	
	var body: some View {
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
			if isPinned {
				Image(systemName: "pin.fill")
					.font(.caption)
					.foregroundStyle(.yellow)
					.padding(.leading, 5)
			}
		}
	}
}

private struct FriendCardRowView: View, Equatable {
	let friend: XMPPFriend
	let isOfflineStyle: Bool
	let isPinned: Bool
	let unreadCount: Int
	let openProfileDirectly: Bool
	let matchDetail: String?
	let tierIcon: AssetImage?
	let onPrimaryTap: () -> Void
	let onTogglePin: () -> Void
	let onOpenChat: () -> Void
	let onOpenProfile: () -> Void
	let onEditNote: () -> Void
	let onRemove: () -> Void
	
	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.friend == rhs.friend
			&& lhs.isOfflineStyle == rhs.isOfflineStyle
			&& lhs.isPinned == rhs.isPinned
			&& lhs.unreadCount == rhs.unreadCount
			&& lhs.openProfileDirectly == rhs.openProfileDirectly
			&& lhs.matchDetail == rhs.matchDetail
			&& lhs.tierIcon == rhs.tierIcon
	}
	
	var body: some View {
		Button(action: onPrimaryTap) {
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
					FriendNameTitleView(friend: friend, isPinned: isPinned)
					
					Text(Self.statusHeadline(for: friend))
						.font(.subheadline)
						.foregroundStyle(isOfflineStyle ? Color.secondary : Color.primary.opacity(0.85))
						.lineLimit(1)
					
					if let matchDetail {
						Text(matchDetail)
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
				
				if unreadCount > 0 {
					Text("\(unreadCount)")
						.font(.caption2.bold())
						.padding(.horizontal, 7)
						.padding(.vertical, 3)
						.background(Color.accentColor, in: Capsule())
						.foregroundStyle(.white)
				}
				
				if let tier = friend.competitiveTier, tier >= 3 {
					if let tierIcon {
						tierIcon.view(bucket: .icon)
							.frame(width: 34, height: 34)
					} else {
						Circle()
							.opacity(0.1)
							.aspectRatio(1, contentMode: .fit)
							.frame(width: 34, height: 34)
					}
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
			Button(action: onTogglePin) {
				Label(isPinned ? "Unpin Friend" : "Pin Friend", systemImage: isPinned ? "pin.slash" : "pin")
			}
			
			if openProfileDirectly {
				Button(action: onOpenChat) {
					Label("Open Chat", systemImage: "message")
				}
			} else if friend.resolvedUserID != nil {
				Button(action: onOpenProfile) {
					Label("Open Profile", systemImage: "person.crop.circle")
				}
			}
			
			if !friend.isIncomingRequest && !friend.isOutgoingRequest {
				Button(action: onEditNote) {
					let hasNote = (friend.note?.isEmpty == false)
					Label(hasNote ? "Edit Note" : "Add Note", systemImage: hasNote ? "note.text" : "note.text.badge.plus")
				}
			}
			
			Button(role: .destructive, action: onRemove) {
				Label("Remove Friend", systemImage: "person.badge.minus")
			}
		}
	}
	
	private static func formatLastOnline(_ date: Date, now: Date = .now) -> String {
		let totalSeconds = Int(max(0, now.timeIntervalSince(date)))
		if totalSeconds < 60 {
			return "Last online just now"
		}
		let days = totalSeconds / 86_400
		let hours = (totalSeconds % 86_400) / 3_600
		let minutes = (totalSeconds % 3_600) / 60
		
		var parts: [String] = []
		parts.reserveCapacity(3)
		if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
		if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
		if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
		
		guard !parts.isEmpty else {
			return "Last online just now"
		}
		return "Last online \(parts.joined(separator: ", ")) ago"
	}
	
	private static func statusHeadline(for friend: XMPPFriend) -> String {
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
				return formatLastOnline(lastOnline)
			}
			return "Offline"
		}
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

// MARK: - Friend Chat View

struct ChatView: View {
	let friend: XMPPFriend
	@EnvironmentObject private var socialManager: SocialManager
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var sendError: String?
	@State private var showingProfile = false
	@State private var showingNoteEditor = false
	
	private var liveFriend: XMPPFriend {
		socialManager.friendsByJID[friend.jid] ?? friend
	}
	
	private var messages: [XMPPChatMessage] {
		socialManager.messages(for: friend.jid)
	}
	
	var body: some View {
		ZStack {
			Color.groupedBackground.ignoresSafeArea()
			
			if messages.isEmpty {
				VStack(spacing: 10) {
					if socialManager.isLoadingHistory(for: friend.jid) {
						ProgressView()
							.padding(.bottom, 4)
						Text("Loading Messages...")
							.font(.headline.weight(.bold))
					} else {
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
				if let profileID = liveFriend.resolvedUserID {
					NavigationLink("", isActive: $showingProfile) {
						MatchListView(userID: profileID)
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
					if liveFriend.resolvedUserID != nil {
						Button {
							showingProfile = true
						} label: {
							Label("Open Profile", systemImage: "person.crop.circle")
						}
					}
					
					Button {
						showingNoteEditor = true
					} label: {
						let hasNote = (liveFriend.note?.isEmpty == false)
						Label(hasNote ? "Edit Note" : "Add Note", systemImage: hasNote ? "note.text" : "note.text.badge.plus")
					}
					
					let pinned = socialManager.isPinned(liveFriend)
					Button {
						withAnimation {
							socialManager.togglePinned(jid: liveFriend.jid)
						}
					} label: {
						Label(pinned ? "Unpin Friend" : "Pin Friend", systemImage: pinned ? "pin.slash" : "pin")
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
		.safeAreaInset(edge: .top) {
			if let note = liveFriend.note, !note.isEmpty {
				Button {
					showingNoteEditor = true
				} label: {
					HStack(spacing: 8) {
						Image(systemName: "text.quote")
							.font(.caption)
							.foregroundStyle(Color.accentColor)
						Text(note)
							.font(.caption)
							.foregroundStyle(.primary)
							.lineLimit(2)
							.multilineTextAlignment(.leading)
						Spacer(minLength: 4)
						Image(systemName: "pencil")
							.font(.caption2.weight(.semibold))
							.foregroundStyle(.secondary)
					}
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.stroke(Color.white.opacity(0.1), lineWidth: 1)
					)
					.padding(.horizontal, 14)
					.padding(.top, 6)
				}
				.buttonStyle(.plain)
			}
		}
		.safeAreaInset(edge: .bottom) {
			ChatComposerView(friendJID: friend.jid) { errorMessage in
				sendError = errorMessage
			}
		}
		.sheet(isPresented: $showingNoteEditor) {
			FriendNoteEditorSheet(friend: liveFriend)
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
		Button {
			guard liveFriend.resolvedUserID != nil else { return }
			showingProfile = true
		} label: {
			HStack(spacing: 9) {
				PlayerCardImage.small(liveFriend.playerCardID)
					.frame(width: 30, height: 30)
					.background(Color.tertiaryGroupedBackground)
					.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
				
				VStack(alignment: .leading, spacing: 1) {
					HStack(spacing: 2) {
						Text(liveFriend.gameName.isEmpty ? liveFriend.jid : liveFriend.gameName)
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.primary)
							.lineLimit(1)
						if !liveFriend.tagLine.isEmpty {
							Text("#\(liveFriend.tagLine)")
								.font(.subheadline)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
						if socialManager.isPinned(liveFriend) {
							Image(systemName: "pin.fill")
								.font(.caption2)
								.foregroundStyle(.yellow)
								.padding(.leading, 2)
						}
						if liveFriend.resolvedUserID != nil {
							Image(systemName: "chevron.right")
								.font(.caption2.weight(.semibold))
								.foregroundStyle(.secondary)
								.padding(.leading, 2)
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
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(liveFriend.resolvedUserID == nil)
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
			let name = assets?.mapInfo(for: path)?.displayName
				?? path.split(separator: "/").last.map(String.init)?.capitalized
				?? path
			parts.append(name)
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

// MARK: - Isolated Chat Composer

private struct ChatComposerView: View {
	let friendJID: String
	var onSendError: (String) -> Void
	
	@EnvironmentObject private var socialManager: SocialManager
	@State private var draft = ""
	
	private var canSend: Bool {
		!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
	
	var body: some View {
		HStack(spacing: 8) {
			TextField("Message", text: $draft, axis: .vertical)
				.lineLimit(1...4)
				.padding(.leading, 14)
				.padding(.vertical, 9)
			
			Button {
				let text = draft
				draft = ""
				Task {
					do {
						try await socialManager.sendMessage(to: friendJID, body: text)
					} catch {
						draft = text
						onSendError(error.localizedDescription)
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
}

// MARK: - Friend List Changes View

struct FriendListChangesView: View {
	@EnvironmentObject private var socialManager: SocialManager
	@EnvironmentObject private var accountManager: AccountManager
	
	private static let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
	
	@State private var cachedLeftCount = 0
	@State private var cachedAcceptedCount = 0
	@State private var cachedNoLongerPendingCount = 0
	@State private var cachedGroupedSections: [EventGroup] = []
	
	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 20) {
				summaryCard(
					left: cachedLeftCount,
					accepted: cachedAcceptedCount,
					noLongerPending: cachedNoLongerPendingCount
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
					ForEach(cachedGroupedSections, id: \.title) { section in
						VStack(alignment: .leading, spacing: 8) {
							Text(section.title)
								.font(.headline.weight(.bold))
								.padding(.horizontal, 4)
							
							LazyVStack(spacing: 0) {
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
		.task(id: socialManager.changeEvents) {
			recomputeChanges()
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
	
	private static let relativeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter
	}()
	
	private var checkedRelativeString: String {
		guard let date = socialManager.lastSyncedAt else { return "just now" }
		return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
	}
	
	private struct EventGroup {
		var title: String
		var events: [FriendListChangeEvent]
	}
	
	private func recomputeChanges() {
		let cal = Calendar.current
		let now = Date()
		let cutoff = now.addingTimeInterval(-Self.thirtyDays)
		let weekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
		
		var leftCount = 0
		var acceptedCount = 0
		var noLongerPendingCount = 0
		var today: [FriendListChangeEvent] = []
		var thisWeek: [FriendListChangeEvent] = []
		var older: [FriendListChangeEvent] = []
		
		for event in socialManager.changeEvents.sorted(by: { $0.timestamp > $1.timestamp }) {
			if event.timestamp >= cutoff {
				switch event.kind {
				case .removedFriend: leftCount += 1
				case .acceptedRequest: acceptedCount += 1
				case .requestNoLongerPending: noLongerPendingCount += 1
				case .addedFriend: break
				}
			}
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
		
		cachedLeftCount = leftCount
		cachedAcceptedCount = acceptedCount
		cachedNoLongerPendingCount = noLongerPendingCount
		cachedGroupedSections = groups
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
		Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
	}
}

// MARK: - Friend Note Editor & Manager

private struct FriendNoteEditorSheet: View {
	let friend: XMPPFriend
	
	@EnvironmentObject private var socialManager: SocialManager
	@Environment(\.dismiss) private var dismiss
	
	@State private var draft: String
	@State private var isSaving = false
	@State private var errorMessage: String?
	@FocusState private var isFocused: Bool
	
	init(friend: XMPPFriend) {
		self.friend = friend
		self._draft = State(initialValue: friend.note ?? "")
	}
	
	private var liveFriend: XMPPFriend {
		socialManager.friendsByJID[friend.jid] ?? friend
	}
	
	private var isOverLimit: Bool {
		draft.count > SocialManager.maxFriendNoteLength
	}
	
	private var canSave: Bool {
		!isSaving && !isOverLimit && socialManager.connectionState == .connected
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					headerCard
					
					VStack(alignment: .leading, spacing: 10) {
						TextField(
							"Write a private note (syncs with VALORANT)...",
							text: $draft,
							axis: .vertical
						)
						.lineLimit(3...6)
						.focused($isFocused)
						
						Divider().opacity(0.22)
						
						HStack {
							Text("Saved privately on your Riot account")
								.font(.caption2)
								.foregroundStyle(.secondary)
							
							Spacer()
							
							Text("\(draft.count) / \(SocialManager.maxFriendNoteLength)")
								.font(.caption.monospacedDigit())
								.foregroundStyle(isOverLimit ? Color.valorantRed : Color.secondary)
						}
					}
					.padding(14)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
					
					if socialManager.connectionState != .connected {
						HStack(spacing: 8) {
							Image(systemName: "wifi.exclamationmark")
								.foregroundStyle(.orange)
							Text("Connect to Riot Chat to save friend notes.")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.padding(12)
						.frame(maxWidth: .infinity, alignment: .leading)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					}
					
					if let errorMessage {
						Text(errorMessage)
							.font(.caption)
							.foregroundStyle(Color.valorantRed)
							.padding(.horizontal, 4)
					}
					
					if let existing = liveFriend.note, !existing.isEmpty {
						Button(role: .destructive) {
							save(note: nil)
						} label: {
							Label("Clear Note", systemImage: "trash")
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(Color.valorantRed)
								.frame(maxWidth: .infinity)
								.padding(.vertical, 12)
								.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.buttonStyle(.plain)
						.disabled(isSaving || socialManager.connectionState != .connected)
					}
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Friend Note")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				
				ToolbarItem(placement: .confirmationAction) {
					if isSaving {
						ProgressView()
					} else {
						Button("Save") {
							save(note: draft)
						}
						.fontWeight(.semibold)
						.disabled(!canSave)
					}
				}
			}
			.onAppear {
				isFocused = true
			}
		}
		.presentationDetents([.medium])
	}
	
	private var headerCard: some View {
		HStack(spacing: 12) {
			if let cardID = liveFriend.playerCardID {
				PlayerCardImage.small(cardID)
					.frame(width: 44, height: 44)
					.background(Color.tertiaryGroupedBackground)
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			} else {
				ZStack {
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(Color.tertiaryGroupedBackground)
						.frame(width: 44, height: 44)
					Image(systemName: "person.crop.circle")
						.font(.title3)
						.foregroundStyle(.secondary)
				}
			}
			
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 0) {
					Text(liveFriend.gameName.isEmpty ? liveFriend.jid : liveFriend.gameName)
						.font(.headline.weight(.semibold))
						.lineLimit(1)
					if !liveFriend.tagLine.isEmpty {
						Text("#\(liveFriend.tagLine)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				Text("Private note · visible only to you")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			
			Spacer()
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func save(note: String?) {
		guard !isSaving else { return }
		errorMessage = nil
		isSaving = true
		Task {
			defer { isSaving = false }
			do {
				try await socialManager.updateFriendNote(liveFriend, note: note)
				dismiss()
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}
}

private struct FriendNotesManagerSheet: View {
	@EnvironmentObject private var socialManager: SocialManager
	@Environment(\.dismiss) private var dismiss
	
	@State private var search = ""
	@State private var selectedFriend: XMPPFriend?
	
	private var confirmedFriends: [XMPPFriend] {
		let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
		return socialManager.friends
			.filter { friend in
				guard !friend.isIncomingRequest, !friend.isOutgoingRequest else { return false }
				guard !query.isEmpty else { return true }
				return friend.displayName.localizedCaseInsensitiveContains(query)
					|| (friend.note?.localizedCaseInsensitiveContains(query) ?? false)
			}
			.sorted {
				$0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
			}
	}
	
	var body: some View {
		let friends = confirmedFriends
		let withNotes = friends.filter { $0.note?.isEmpty == false }
		let withoutNotes = friends.filter { $0.note?.isEmpty != false }
		
		NavigationStack {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 16) {
					HStack(spacing: 8) {
						Image(systemName: "magnifyingglass")
							.font(.subheadline)
							.foregroundStyle(.secondary)
						TextField("Search friends or notes", text: $search)
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
					
					if !withNotes.isEmpty {
						notesSection(title: "With Notes — \(withNotes.count)", friends: withNotes)
					}
					
					if !withoutNotes.isEmpty {
						notesSection(title: "Other Friends — \(withoutNotes.count)", friends: withoutNotes)
					}
					
					if friends.isEmpty {
						Text("No matching friends.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity)
							.padding(24)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
					}
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Friend Notes")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
			.sheet(item: $selectedFriend) { friend in
				FriendNoteEditorSheet(friend: friend)
			}
		}
	}
	
	private func notesSection(title: String, friends: [XMPPFriend]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title)
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			LazyVStack(spacing: 0) {
				ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
					Button {
						selectedFriend = friend
					} label: {
						HStack(spacing: 12) {
							if let cardID = friend.playerCardID {
								PlayerCardImage.small(cardID)
									.frame(width: 40, height: 40)
									.background(Color.tertiaryGroupedBackground)
									.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
							} else {
								ZStack {
									RoundedRectangle(cornerRadius: 9, style: .continuous)
										.fill(Color.tertiaryGroupedBackground)
										.frame(width: 40, height: 40)
									Image(systemName: "person.fill")
										.font(.subheadline)
										.foregroundStyle(.secondary)
								}
							}
							
							VStack(alignment: .leading, spacing: 3) {
								HStack(spacing: 0) {
									Text(friend.gameName.isEmpty ? friend.jid : friend.gameName)
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(.primary)
										.lineLimit(1)
									if !friend.tagLine.isEmpty {
										Text("#\(friend.tagLine)")
											.font(.caption)
											.foregroundStyle(.secondary)
											.lineLimit(1)
									}
								}
								
								if let note = friend.note, !note.isEmpty {
									HStack(spacing: 4) {
										Image(systemName: "text.quote")
											.font(.caption2)
											.foregroundStyle(Color.accentColor)
										Text(note)
											.font(.caption)
											.foregroundStyle(.secondary)
											.lineLimit(2)
									}
								} else {
									Text("Tap to add note")
										.font(.caption)
										.foregroundStyle(.tertiary)
								}
							}
							
							Spacer()
							
							Image(systemName: friend.note?.isEmpty == false ? "pencil" : "plus.circle")
								.font(.subheadline)
								.foregroundStyle(Color.accentColor)
						}
						.padding(.horizontal, 14)
						.padding(.vertical, 11)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					
					if index < friends.count - 1 {
						Divider().opacity(0.22).padding(.leading, 66)
					}
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
}
