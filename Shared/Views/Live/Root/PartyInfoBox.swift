import SwiftUI
import ValorantAPI
import HandyOperators

struct PartyInfoBox: View {
	var userID: User.ID
	@Binding var party: Party
	var partyPlayer: PartyPlayer? = nil
	@Binding var shouldAutoShow: Bool
	var onPartyChanged: () async -> Void = {}
	var onStartPracticeRange: () async -> Void = {}
	
	@State private var showingSettings = false
	@State private var showingCustomSettings = false
	@State private var isTogglingAccessibility = false
	@State private var optimisticAccessibility: Party.Accessibility?
	@State private var isRunningCustomAction = false
	@State private var isExitingCustomGame = false
	@State private var selectedProfileMemberID: Player.ID?
	@State private var processingRequestIDs: Set<String> = []
	@State private var isStartingRange = false


	@Namespace private var accessibilityNamespace
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	
	var member: Party.Member {
		party.members.firstElement(withID: userID)
		?? party.members.first! // can be nil while switching accounts
	}
	
	private var isSelfOwner: Bool {
		member.isOwner
	}
	
	private var displayedAccessibility: Party.Accessibility {
		optimisticAccessibility ?? party.accessibility
	}
	
	var body: some View {
		VStack(spacing: 14) {
			if party.isCustomGame {
				customGameLobbyContent
			} else {
				VStack(spacing: 10) {
					ForEach(party.members) { partyMember in
						PartyMemberRow(
							party: $party,
							member: partyMember,
							userID: userID,
							isSelfOwner: isSelfOwner,
							onViewProfile: { selectedProfileMemberID = partyMember.id },
							onPartyChanged: onPartyChanged
						)
					}
				}
			}
			
			if isSelfOwner && !party.requests.isEmpty {
				joinRequestsSection
			}
			
			if let incomingRequests = partyPlayer?.requests.filter({ $0.partyID != party.id }),
			   !incomingRequests.isEmpty {
				incomingInvitesSection(incomingRequests)
			}
			
			Divider()
				.opacity(0.45)
			
			bottomControlsBar
		}
		.background(
			NavigationLink(
				"",
				isActive: Binding(
					get: { selectedProfileMemberID != nil },
					set: { if !$0 { selectedProfileMemberID = nil } }
				)
			) {
				if let selectedProfileMemberID {
					MatchListView(userID: selectedProfileMemberID)
				}
			}
			.hidden()
		)
		.sheet(isPresented: $showingSettings) {
			PartySettingsView(
				party: $party,
				userID: userID,
				shouldAutoShow: $shouldAutoShow,
				onPartyChanged: onPartyChanged,
				onStartPracticeRange: onStartPracticeRange
			)
		}
		.sheet(isPresented: $showingCustomSettings) {
			PartyCustomGameSettingsSheet(
				party: $party,
				userID: userID,
				onPartyChanged: onPartyChanged
			)
		}
		.onChange(of: party.accessibility) { _ in
			if !isTogglingAccessibility {
				withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
					optimisticAccessibility = nil
				}
			}
		}
	}
	
	// MARK: - Custom Game Lobby
	
	@ViewBuilder
	private var customGameLobbyContent: some View {
		let customData = party.customGameData ?? .init()
		let membership = customData.membership
		let settings = customData.settings
		let rules = settings.gameRules
		let membersByID = Dictionary(party.members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		let assignedIDs = Set(
			membership.teamOne.map(\.subject)
			+ membership.teamTwo.map(\.subject)
			+ membership.teamSpectate.map(\.subject)
			+ membership.teamOneCoaches.map(\.subject)
			+ membership.teamTwoCoaches.map(\.subject)
		)
		let unassignedMembers = party.members.filter { !assignedIDs.contains($0.id) }
		let showCoaches = rules?.tournamentModeEnabled == true
			|| !membership.teamOneCoaches.isEmpty
			|| !membership.teamTwoCoaches.isEmpty
		
		VStack(spacing: 12) {
			customGameSummaryBanner(settings: settings)
			
			customTeamSection(
				title: "Attackers",
				team: .teamOne,
				members: membership.teamOne.compactMap { membersByID[$0.subject] },
				accentColor: .valorantRed,
				canJoin: membership.team(for: userID) != .teamOne
			)
			
			customTeamSection(
				title: "Defenders",
				team: .teamTwo,
				members: membership.teamTwo.compactMap { membersByID[$0.subject] },
				accentColor: .valorantBlue,
				canJoin: membership.team(for: userID) != .teamTwo
			)
			
			customTeamSection(
				title: "Spectators",
				team: .spectate,
				members: membership.teamSpectate.compactMap { membersByID[$0.subject] },
				accentColor: .secondary,
				joinLabel: "Spectate",
				canJoin: membership.team(for: userID) != .spectate
			)
			
			if showCoaches {
				customTeamSection(
					title: "Attackers Coach",
					team: .teamOneCoaches,
					members: membership.teamOneCoaches.compactMap { membersByID[$0.subject] },
					accentColor: .valorantRed.opacity(0.8),
					joinLabel: "Coach",
					canJoin: membership.team(for: userID) != .teamOneCoaches
				)
				
				customTeamSection(
					title: "Defenders Coach",
					team: .teamTwoCoaches,
					members: membership.teamTwoCoaches.compactMap { membersByID[$0.subject] },
					accentColor: .valorantBlue.opacity(0.8),
					joinLabel: "Coach",
					canJoin: membership.team(for: userID) != .teamTwoCoaches
				)
			}
			
			if !unassignedMembers.isEmpty {
				VStack(alignment: .leading, spacing: 6) {
					Text("Unassigned")
						.font(.caption.weight(.bold))
						.foregroundStyle(.secondary)
						.padding(.horizontal, 4)
					
					ForEach(unassignedMembers) { partyMember in
						PartyMemberRow(
							party: $party,
							member: partyMember,
							userID: userID,
							isSelfOwner: isSelfOwner,
							onViewProfile: { selectedProfileMemberID = partyMember.id },
							onPartyChanged: onPartyChanged,
							onMoveCustomTeam: { movePlayer(partyMember.id, to: $0) }
						)
					}
				}
			}
			
			customGameUtilityRow
		}
	}
	
	private func customGameSummaryBanner(settings: Party.CustomGameData.Settings) -> some View {
		let mapPath = settings.map.isEmpty ? MapID.ascent.rawValue : settings.map
		let resolvedMap = assets?.mapInfo(for: mapPath)
		let mapID = resolvedMap?.id ?? MapID(mapPath)
		let mapName = resolvedMap?.displayName ?? mapPath.split(separator: "/").last.map(String.init) ?? "Custom Map"
		let modeName = assets?.customModeDisplayName(for: settings.mode)
			?? AssetCollection.fallbackCustomModeDisplayName(for: settings.mode)
		let serverName: String = {
			guard !settings.gamePod.isEmpty else { return String(localized: "Auto Server") }
			return assets?.serverDisplayName(for: settings.gamePod)
				?? MatchAnalytics.parseServerName(from: settings.gamePod)
				?? settings.gamePod
		}()
		let rules = settings.gameRules
		let activeFlags: [String] = [
			rules?.allowCheats == true ? "Cheats" : nil,
			rules?.tournamentModeEnabled == true ? "Tournament" : nil,
			rules?.overtimeWinByTwo == true ? "OT Win by 2" : nil,
			rules?.playOutAllRoundsEnabled == true ? "Play All" : nil,
			rules?.hideMatchHistory == true ? "Skip History" : nil,
		].compactMap { $0 }
		
		return ZStack(alignment: .bottomLeading) {
			MapImage.splash(mapID)
				.aspectRatio(contentMode: .fill)
				.frame(height: 108)
				.clipped()
				.overlay(
					LinearGradient(
						colors: [.black.opacity(0.2), .black.opacity(0.84)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
			
			HStack(alignment: .bottom) {
				VStack(alignment: .leading, spacing: 3) {
					Text("CUSTOM GAME")
						.font(.system(size: 10, weight: .bold))
						.tracking(0.8)
						.foregroundStyle(Color.accentColor)
					
					Text(mapName)
						.font(.headline.weight(.bold))
						.foregroundStyle(.white)
					
					Text("\(modeName) · \(serverName)")
						.font(.caption)
						.foregroundStyle(.white.opacity(0.8))
					
					if !activeFlags.isEmpty {
						Text(activeFlags.joined(separator: " · "))
							.font(.system(size: 10, weight: .semibold))
							.foregroundStyle(.white.opacity(0.75))
							.lineLimit(1)
					}
				}
				
				Spacer()
				
				if isSelfOwner {
					Button {
						showingCustomSettings = true
					} label: {
						Label("Edit", systemImage: "slider.horizontal.3")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.white)
							.padding(.horizontal, 10)
							.padding(.vertical, 6)
							.background(.ultraThinMaterial, in: Capsule())
					}
					.buttonStyle(.plain)
				}
			}
			.padding(12)
		}
		.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func customTeamSection(
		title: LocalizedStringKey,
		team: CustomGameTeam,
		members: [Party.Member],
		accentColor: Color,
		joinLabel: LocalizedStringKey = "Join",
		canJoin: Bool
	) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				HStack(spacing: 6) {
					Circle()
						.fill(accentColor)
						.frame(width: 7, height: 7)
					Text(title)
						.font(.caption.weight(.bold))
						.foregroundStyle(.primary)
					Text("(\(members.count))")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(.secondary)
						.monospacedDigit()
				}
				
				Spacer()
				
				if canJoin && party.state == .customGameSetup {
					Button {
						movePlayer(userID, to: team)
					} label: {
						Text(joinLabel)
							.font(.caption2.weight(.bold))
							.foregroundStyle(accentColor == .secondary ? Color.accentColor : accentColor)
							.padding(.horizontal, 10)
							.padding(.vertical, 4)
							.background(Color.tertiaryGroupedBackground, in: Capsule())
					}
					.buttonStyle(.plain)
					.disabled(isRunningCustomAction)
				}
			}
			.padding(.horizontal, 4)
			
			if members.isEmpty {
				Text("Empty slot")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.background(Color.tertiaryGroupedBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			} else {
				VStack(spacing: 8) {
					ForEach(members) { partyMember in
						PartyMemberRow(
							party: $party,
							member: partyMember,
							userID: userID,
							isSelfOwner: isSelfOwner,
							onViewProfile: { selectedProfileMemberID = partyMember.id },
							onPartyChanged: onPartyChanged,
							onMoveCustomTeam: { movePlayer(partyMember.id, to: $0) }
						)
					}
				}
			}
		}
	}
	
	@ViewBuilder
	private var customGameUtilityRow: some View {
		if isSelfOwner && party.state == .customGameSetup {
			HStack(spacing: 8) {
				Button {
					balanceTeams()
				} label: {
					Label("Balance", systemImage: "arrow.triangle.swap")
						.font(.caption.weight(.semibold))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 9)
						.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
						.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
						.foregroundStyle(.primary)
				}
				.buttonStyle(.plain)
				.disabled(isRunningCustomAction || party.members.count < 2)
				
				Button {
					exitCustomGame()
				} label: {
					HStack(spacing: 6) {
						if isExitingCustomGame {
							ProgressView()
								.controlSize(.mini)
						} else {
							Image(systemName: "arrow.uturn.backward")
						}
						Text("Standard")
					}
					.font(.caption.weight(.semibold))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 9)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
					.foregroundStyle(Color.accentColor)
				}
				.buttonStyle(.plain)
				.disabled(isRunningCustomAction)
			}
		}
	}
	
	// MARK: - Bottom Bar
	
	private var bottomControlsBar: some View {
		HStack(spacing: 10) {
			accessibilitySegmentedPill
			
			Spacer(minLength: 4)
			
			matchmakingPill
			
			Spacer(minLength: 4)
			
			practiceRangeButton
			
			Button {
				showingSettings = true
			} label: {
				Image(systemName: "ellipsis")
					.font(.body.weight(.semibold))
					.foregroundStyle(Color.accentColor)
					.frame(width: 42, height: 42)
					.background(Color.tertiaryGroupedBackground, in: Circle())
			}
			.accessibilityLabel("Party Settings")
		}
	}
	
	private var accessibilitySegmentedPill: some View {
		let canToggle = isSelfOwner
			&& (party.state == .default || party.state == .customGameSetup)
			&& !isTogglingAccessibility
		
		return HStack(spacing: 2) {
			accessibilityButton(.open, icon: "lock.open", canToggle: canToggle)
			accessibilityButton(.closed, icon: "lock", canToggle: canToggle)
		}
		.padding(4)
		.background(Color.tertiaryGroupedBackground, in: Capsule())
		.opacity((isSelfOwner && (party.state == .default || party.state == .customGameSetup)) ? 1 : 0.65)
	}
	
	private func accessibilityButton(
		_ target: Party.Accessibility,
		icon: String,
		canToggle: Bool
	) -> some View {
		let isActive = displayedAccessibility == target
		return Button {
			guard displayedAccessibility != target else { return }
			setAccessibility(to: target)
		} label: {
			Image(systemName: icon)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(isActive ? Color.accentColor : .secondary)
				.frame(width: 38, height: 32)
				.background {
					if isActive {
						Capsule()
							.fill(Color.secondaryGroupedBackground)
							.matchedGeometryEffect(id: "accessibilityThumb", in: accessibilityNamespace)
							.shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
					}
				}
		}
		.buttonStyle(.plain)
		.disabled(!canToggle)
		.accessibilityLabel(target == .open ? "Open Party" : "Closed Party")
		.animation(.spring(response: 0.28, dampingFraction: 0.78), value: displayedAccessibility)
	}
	
	@ViewBuilder
	private var matchmakingPill: some View {
		switch party.state {
		case .inMatchmaking:
			AsyncButton {
				await load {
					party = try await $0.leaveMatchmaking(in: party.id)
				}
			} label: {
				HStack(spacing: 8) {
					Image(systemName: "stop.fill")
						.font(.caption.weight(.bold))
					queueTimer(entryTime: party.queueEntryTime)
				}
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 18)
				.padding(.vertical, 11)
				.background(Color.accentColor.opacity(0.16), in: Capsule())
				.overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1))
			}
			.buttonStyle(.plain)
		case .customGameStarting:
			HStack(spacing: 8) {
				ProgressView()
					.scaleEffect(0.8)
				Text("Starting")
					.font(.subheadline.weight(.semibold))
			}
			.foregroundStyle(Color.accentColor)
			.padding(.horizontal, 18)
			.padding(.vertical, 11)
			.background(Color.tertiaryGroupedBackground, in: Capsule())
		case .customGameSetup:
			let membership = party.customGameData?.membership
			let hasTeamPlayers = !(membership?.teamOne.isEmpty ?? true) || !(membership?.teamTwo.isEmpty ?? true)
			let canStartCustom = isSelfOwner && hasTeamPlayers
			AsyncButton {
				await load {
					party = try await $0.startCustomGame(in: party.id)
				}
			} label: {
				HStack(spacing: 7) {
					Text("Start")
						.font(.headline.weight(.semibold))
					Image(systemName: "play.fill")
						.font(.caption.weight(.bold))
				}
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 20)
				.padding(.vertical, 11)
				.background(Color.tertiaryGroupedBackground, in: Capsule())
			}
			.buttonStyle(.plain)
			.disabled(!canStartCustom)
			.opacity(canStartCustom ? 1 : 0.45)
		case .default:
			let canStart = isSelfOwner && party.members.allSatisfy(\.isReady)
			AsyncButton {
				await load {
					party = try await $0.joinMatchmaking(in: party.id)
				}
			} label: {
				HStack(spacing: 7) {
					Text("Start")
						.font(.headline.weight(.semibold))
					Image(systemName: "play.fill")
						.font(.caption.weight(.bold))
				}
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 20)
				.padding(.vertical, 11)
				.background(Color.tertiaryGroupedBackground, in: Capsule())
			}
			.buttonStyle(.plain)
			.disabled(!canStart)
			.opacity(canStart ? 1 : 0.45)
		default:
			EmptyView()
		}
	}
	
	private var practiceRangeButton: some View {
		let canEnterRange = party.members.count <= 1
			&& (party.state == .default || party.state == .customGameSetup)
			&& !isStartingRange
		return Button {
			Task {
				isStartingRange = true
				defer { isStartingRange = false }
				await onStartPracticeRange()
			}
		} label: {
			Group {
				if isStartingRange {
					ProgressView()
						.tint(Color.accentColor)
				} else {
					Image(systemName: "scope")
						.font(.body.weight(.semibold))
						.foregroundStyle(Color.accentColor)
				}
			}
			.frame(width: 42, height: 42)
			.background(Color.tertiaryGroupedBackground, in: Circle())
		}
		.buttonStyle(.plain)
		.disabled(!canEnterRange)
		.opacity((party.members.count <= 1 && (party.state == .default || party.state == .customGameSetup)) ? 1 : 0.4)
		.accessibilityLabel("Practice Range")
	}
	
	private var joinRequestsSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Join Requests")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			ForEach(party.requests) { request in
				RequestPlayerRow(
					request: request,
					isProcessing: processingRequestIDs.contains(request.id),
					onDecline: { declineJoinRequest(request) }
				)
			}
		}
	}
	
	private func incomingInvitesSection(_ requests: [Party.JoinRequest]) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Party Invites")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			ForEach(requests) { request in
				IncomingInviteRow(
					request: request,
					isProcessing: processingRequestIDs.contains(request.id),
					onAccept: { acceptPartyInvite(request) },
					onDecline: { declinePartyInvite(request) }
				)
			}
		}
	}
	
	private static let queueTimeFormatter = DateComponentsFormatter() <- {
		$0.zeroFormattingBehavior = .pad
		$0.allowedUnits = [.minute, .second]
	}
	
	func queueTimer(entryTime: Date) -> some View {
		TimelineView(.periodic(from: entryTime, by: 1)) { context in
			let elapsed = max(0, context.date.timeIntervalSince(entryTime))
			let time = Self.queueTimeFormatter.string(from: elapsed) ?? "0:00"
			Text(time)
				.monospacedDigit()
		}
	}
	
	private func setAccessibility(to accessibility: Party.Accessibility) {
		Task {
			isTogglingAccessibility = true
			withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
				optimisticAccessibility = accessibility
			}
			defer {
				isTogglingAccessibility = false
				withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
					optimisticAccessibility = nil
				}
			}
			await load {
				party = try await $0.setPartyAccessibility(in: party.id, to: accessibility)
			}
		}
	}
	
	private func movePlayer(_ playerID: Player.ID, to team: CustomGameTeam) {
		Task {
			isRunningCustomAction = true
			defer { isRunningCustomAction = false }
			await load {
				party = try await $0.changeCustomGameTeam(player: playerID, to: team, in: party.id)
			}
		}
	}
	
	private func balanceTeams() {
		Task {
			isRunningCustomAction = true
			defer { isRunningCustomAction = false }
			await load {
				party = try await $0.balanceCustomGameTeams(in: party.id)
			}
		}
	}
	
	private func exitCustomGame() {
		Task {
			isRunningCustomAction = true
			isExitingCustomGame = true
			defer {
				isRunningCustomAction = false
				isExitingCustomGame = false
			}
			let targetQueue = party.eligibleQueues?.first(where: { $0 == .unrated })
				?? party.eligibleQueues?.first
				?? .unrated
			await load {
				party = try await $0.makeDefaultQueue(targetQueue, in: party.id)
			}
		}
	}
	
	private func declineJoinRequest(_ request: Party.JoinRequest) {
		Task {
			processingRequestIDs.insert(request.id)
			defer { processingRequestIDs.remove(request.id) }
			await load {
				party = try await $0.declinePartyRequest(request.id, in: party.id)
			}
		}
	}
	
	private func acceptPartyInvite(_ request: Party.JoinRequest) {
		Task {
			processingRequestIDs.insert(request.id)
			defer { processingRequestIDs.remove(request.id) }
			await load {
				party = try await $0.joinParty(request.partyID)
			}
		}
	}
	
	private func declinePartyInvite(_ request: Party.JoinRequest) {
		Task {
			processingRequestIDs.insert(request.id)
			defer { processingRequestIDs.remove(request.id) }
			await load {
				try await $0.declinePartyInvite(for: request.partyID)
			}
			await onPartyChanged()
		}
	}
	
	struct PartyMemberRow: View {
		@Binding var party: Party
		let member: Party.Member
		let userID: User.ID
		let isSelfOwner: Bool
		var onViewProfile: () -> Void
		var onPartyChanged: () async -> Void
		var onMoveCustomTeam: ((CustomGameTeam) -> Void)? = nil
		
		@State private var isSettingReady = false
		@State private var isRunningAction = false
		
		@LocalData var memberUser: User?
		@LocalData var summary: CareerSummary?
		
		@Environment(\.valorantLoad) private var load
		
		init(
			party: Binding<Party>,
			member: Party.Member,
			userID: User.ID,
			isSelfOwner: Bool,
			onViewProfile: @escaping () -> Void = {},
			onPartyChanged: @escaping () async -> Void = {},
			onMoveCustomTeam: ((CustomGameTeam) -> Void)? = nil
		) {
			self._party = party
			self.member = member
			self.userID = userID
			self.isSelfOwner = isSelfOwner
			self.onViewProfile = onViewProfile
			self.onPartyChanged = onPartyChanged
			self.onMoveCustomTeam = onMoveCustomTeam
			self._memberUser = .init(id: member.id)
			self._summary = .init(id: member.id)
		}
		
		private var canMoveCustomTeam: Bool {
			onMoveCustomTeam != nil
				&& party.state == .customGameSetup
				&& (isSelfOwner || member.id == userID)
		}
		
		var body: some View {
			let iconSize = 48.0
			
			HStack(spacing: 12) {
				PlayerCardImage.small(member.identity.cardID)
					.frame(width: iconSize, height: iconSize)
					.mask(RoundedRectangle(cornerRadius: 10, style: .continuous))
				
				VStack(alignment: .leading, spacing: 2) {
					if let memberUser {
						HStack(spacing: 0) {
							Text(memberUser.gameName)
								.font(.headline.weight(.semibold))
							Text("#\(memberUser.tagLine)")
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
						.lineLimit(1)
						.minimumScaleFactor(0.8)
					} else {
						Text("Member", comment: "Party Box: shown when member's name is not yet loaded")
							.font(.headline)
							.foregroundStyle(.secondary)
					}
					
					if party.isCustomGame {
						Text(customRoleSubtitle)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					} else if member.isReady {
						Text("Ready", comment: "Party Box")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					} else {
						Text("Not Ready", comment: "Party Box")
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.secondary)
					}
				}
				
				Spacer(minLength: 8)
				
				if member.id == userID {
					HStack(spacing: 8) {
						if canMoveCustomTeam {
							customTeamMenuButton
						}
						if !party.isCustomGame {
							if isSettingReady {
								ProgressView()
							} else {
								Toggle(String(localized: "Ready", comment: "accessibility label"), isOn: Binding(
									get: { member.isReady },
									set: { setReady(to: $0) }
								))
								.labelsHidden()
								.tint(Color.accentColor)
							}
						}
					}
				} else {
					HStack(spacing: 8) {
						RankInfoView(summary: summary, size: 36)
						
						Menu {
							Button {
								onViewProfile()
							} label: {
								Label("View Profile", systemImage: "person.crop.circle")
							}
							
							if canMoveCustomTeam {
								customTeamMenuItems
							}
							
							if isSelfOwner && (party.state == .default || party.state == .customGameSetup) {
								Button {
									makeLeader()
								} label: {
									Label("Make Party Leader", systemImage: "crown")
								}
								
								Button(role: .destructive) {
									kickMember()
								} label: {
									Label("Remove from Party", systemImage: "person.badge.minus")
								}
							}
						} label: {
							Group {
								if isRunningAction {
									ProgressView()
								} else {
									Image(systemName: "ellipsis.circle")
										.font(.title3)
										.foregroundStyle(.secondary)
								}
							}
							.frame(width: 28, height: 28)
						}
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background {
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.fill(Color.tertiaryGroupedBackground)
					.overlay(
						RoundedRectangle(cornerRadius: 14, style: .continuous)
							.strokeBorder(.primary.opacity(0.05), lineWidth: 1)
					)
					.overlay {
						if member.isOwner {
							Image(systemName: "crown")
								.font(.system(size: 52, weight: .light))
								.foregroundStyle(.primary.opacity(0.08))
								.offset(x: 6)
								.allowsHitTesting(false)
						}
					}
					.clipped()
			}
			.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			.contextMenu {
				if canMoveCustomTeam {
					customTeamMenuItems
				}
				
				if member.id != userID {
					Button {
						onViewProfile()
					} label: {
						Label("View Profile", systemImage: "person.crop.circle")
					}
					
					if isSelfOwner && (party.state == .default || party.state == .customGameSetup) {
						Button {
							makeLeader()
						} label: {
							Label("Make Party Leader", systemImage: "crown")
						}
						
						Button(role: .destructive) {
							kickMember()
						} label: {
							Label("Remove from Party", systemImage: "person.badge.minus")
						}
					}
				}
			}
			.withLocalData($memberUser, id: member.id, shouldAutoUpdate: false)
			.withLocalData($summary, id: member.id, shouldAutoUpdate: member.id != userID)
		}
		
		private var customRoleSubtitle: LocalizedStringKey {
			switch party.customGameData?.membership.team(for: member.id) {
			case .teamOne: return "Attackers"
			case .teamTwo: return "Defenders"
			case .spectate: return "Spectator"
			case .teamOneCoaches: return "Attackers Coach"
			case .teamTwoCoaches: return "Defenders Coach"
			case nil: return "Unassigned"
			}
		}
		
		private var customTeamMenuButton: some View {
			Menu {
				customTeamMenuItems
			} label: {
				Image(systemName: "arrow.left.arrow.right.circle.fill")
					.font(.title3)
					.foregroundStyle(Color.accentColor)
			}
		}
		
		@ViewBuilder
		private var customTeamMenuItems: some View {
			if let onMoveCustomTeam {
				Button { onMoveCustomTeam(.teamOne) } label: {
					Label("Move to Attackers", systemImage: "flame.fill")
				}
				Button { onMoveCustomTeam(.teamTwo) } label: {
					Label("Move to Defenders", systemImage: "shield.fill")
				}
				Button { onMoveCustomTeam(.spectate) } label: {
					Label("Move to Spectators", systemImage: "eye.fill")
				}
				if party.customGameData?.settings.gameRules?.tournamentModeEnabled == true {
					Button { onMoveCustomTeam(.teamOneCoaches) } label: {
						Label("Attackers Coach", systemImage: "person.badge.shield.checkmark")
					}
					Button { onMoveCustomTeam(.teamTwoCoaches) } label: {
						Label("Defenders Coach", systemImage: "person.badge.shield.checkmark")
					}
				}
			}
		}
		
		func setReady(to isReady: Bool) {
			Task {
				isSettingReady = true
				defer { isSettingReady = false }
				await load {
					party = try await $0.setReady(to: isReady, in: party.id)
				}
			}
		}
		
		private func makeLeader() {
			Task {
				isRunningAction = true
				defer { isRunningAction = false }
				await load {
					party = try await $0.transferPartyOwner(to: member.id, in: party.id)
				}
			}
		}
		
		private func kickMember() {
			Task {
				isRunningAction = true
				defer { isRunningAction = false }
				await load {
					try await $0.removePlayerFromParty(member.id)
				}
				await onPartyChanged()
			}
		}
	}
	
	private struct RequestPlayerRow: View {
		let request: Party.JoinRequest
		let isProcessing: Bool
		let onDecline: () -> Void
		
		@LocalData var requesterUser: User?
		
		init(request: Party.JoinRequest, isProcessing: Bool, onDecline: @escaping () -> Void) {
			self.request = request
			self.isProcessing = isProcessing
			self.onDecline = onDecline
			self._requesterUser = .init(id: request.requestedBy)
		}
		
		var body: some View {
			HStack(spacing: 10) {
				Image(systemName: "person.badge.clock")
					.foregroundStyle(Color.accentColor)
				
				VStack(alignment: .leading, spacing: 1) {
					Text(requesterUser?.name ?? "Player")
						.font(.subheadline.weight(.medium))
						.lineLimit(1)
					Text("Wants to join")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				if isProcessing {
					ProgressView()
				} else {
					Button {
						onDecline()
					} label: {
						Image(systemName: "xmark")
							.font(.caption.weight(.bold))
							.foregroundStyle(.secondary)
							.frame(width: 28, height: 28)
							.background(Color.secondaryGroupedBackground, in: Circle())
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.withLocalData($requesterUser, id: request.requestedBy, shouldAutoUpdate: false)
		}
	}
	
	private struct IncomingInviteRow: View {
		let request: Party.JoinRequest
		let isProcessing: Bool
		let onAccept: () -> Void
		let onDecline: () -> Void
		
		@LocalData var inviterUser: User?
		
		init(
			request: Party.JoinRequest,
			isProcessing: Bool,
			onAccept: @escaping () -> Void,
			onDecline: @escaping () -> Void
		) {
			self.request = request
			self.isProcessing = isProcessing
			self.onAccept = onAccept
			self.onDecline = onDecline
			self._inviterUser = .init(id: request.requestedBy)
		}
		
		var body: some View {
			HStack(spacing: 10) {
				Image(systemName: "envelope.open.fill")
					.foregroundStyle(Color.accentColor)
				
				VStack(alignment: .leading, spacing: 1) {
					Text(inviterUser?.name ?? "Party Invite")
						.font(.subheadline.weight(.medium))
						.lineLimit(1)
					Text("Invited you to join their party")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				if isProcessing {
					ProgressView()
				} else {
					HStack(spacing: 6) {
						Button {
							onDecline()
						} label: {
							Image(systemName: "xmark")
								.font(.caption.weight(.bold))
								.foregroundStyle(.secondary)
								.frame(width: 28, height: 28)
								.background(Color.secondaryGroupedBackground, in: Circle())
						}
						.buttonStyle(.plain)
						
						Button {
							onAccept()
						} label: {
							Image(systemName: "checkmark")
								.font(.caption.weight(.bold))
								.foregroundStyle(.white)
								.frame(width: 28, height: 28)
								.background(Color.accentColor, in: Circle())
						}
						.buttonStyle(.plain)
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.withLocalData($inviterUser, id: request.requestedBy, shouldAutoUpdate: false)
		}
	}
}

#if DEBUG
struct PartyInfoBox_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			previewBox {
				PartyInfoBox(
					userID: PreviewData.userID,
					party: .constant(PreviewData.party),
					shouldAutoShow: .constant(false)
				)
				.padding(14)
			}
			
			previewBox {
				PartyInfoBox(
					userID: PreviewData.userID,
					party: .constant(PreviewData.party <- {
						$0.members[0].isReady = false
						$0.members[1].isReady = true
						$0.queueEntryTime = .init(timeIntervalSinceNow: -35)
					}),
					shouldAutoShow: .constant(true)
				)
				.padding(14)
			}
		}
	}
	
	static func previewBox<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
		RefreshableBox(title: "Party", isExpanded: .constant(true)) {
			content()
		} refresh: { _ in }
		.forPreviews()
	}
}
#endif
