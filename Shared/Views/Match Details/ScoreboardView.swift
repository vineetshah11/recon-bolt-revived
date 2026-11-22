import SwiftUI
import ValorantAPI

enum MatchScoreboardSort: String, CaseIterable, Identifiable {
	case score = "Performance Score"
	case kast = "KAST"
	case adr = "ADR"
	case deaths = "Deaths"
	case kills = "Kills"
	case acs = "ACS"
	
	var id: String { rawValue }
}

struct ScoreboardView: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedPlayerID: Player.ID
	var groupedByTeam: Bool = true
	var isCompact: Bool = false
	var sort: MatchScoreboardSort = .acs
	var resolvedUsers: [Player.ID: User] = [:]
	@Binding var highlight: PlayerHighlightInfo
	var onSelectFocus: ((Player.ID) -> Void)? = nil
	
	@Environment(\.valorantLoad) private var load
	@State private var expandedPlayers: Set<Player.ID> = []
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			if data.isMultiTeam {
				multiTeamSections
			} else if groupedByTeam {
				teamSections
			} else {
				combinedSection
			}
		}
	}
	
	@ViewBuilder
	private var teamSections: some View {
		let focusTeamID = data.players[focusedPlayerID]?.teamID ?? data.myself?.teamID
		let orderedTeams = data.details.teams.sorted { lhs, rhs in
			if lhs.id == focusTeamID { return true }
			if rhs.id == focusTeamID { return false }
			return lhs.won && !rhs.won
		}
		
		ForEach(orderedTeams) { team in
			let teamPlayers = sortedPlayers(data.details.players.filter { $0.teamID == team.id })
			let isOwnTeam = team.id == focusTeamID
			let headerTitle = isOwnTeam ? "YOUR TEAM" : "ENEMY TEAM"
			
			VStack(alignment: .leading, spacing: 8) {
				Text(headerTitle)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 4)
				
				ForEach(teamPlayers) { player in
					ScoreboardRowView(
						player: player,
						data: data,
						analytics: analytics,
						isFocused: player.id == focusedPlayerID,
						isCompact: isCompact,
						isExpanded: expandedPlayers.contains(player.id),
						resolvedUsers: resolvedUsers,
						highlight: $highlight,
						onToggleExpand: { toggleExpand(player.id) },
						onFocus: { onSelectFocus?(player.id) }
					)
				}
			}
		}
	}
	
	@ViewBuilder
	private var combinedSection: some View {
		let allSorted = sortedPlayers(data.details.players.filter { $0.teamID != .neutral })
		VStack(spacing: 8) {
			ForEach(allSorted) { player in
				ScoreboardRowView(
					player: player,
					data: data,
					analytics: analytics,
					isFocused: player.id == focusedPlayerID,
					isCompact: isCompact,
					isExpanded: expandedPlayers.contains(player.id),
					resolvedUsers: resolvedUsers,
					highlight: $highlight,
					onToggleExpand: { toggleExpand(player.id) },
					onFocus: { onSelectFocus?(player.id) }
				)
			}
		}
	}
	
	@ViewBuilder
	private var multiTeamSections: some View {
		let playersByTeam = Dictionary(grouping: data.details.players, by: \.teamID)
		let hasGroupedTeams = playersByTeam.values.contains { $0.count > 1 }
		
		if !hasGroupedTeams || !groupedByTeam {
			let sorted = sortedPlayers(data.details.players.filter { $0.teamID != .neutral })
			ForEach(sorted) { player in
				let placement = data.placement(of: player.teamID).map(PlacementFormatter.ordinal)
				ScoreboardRowView(
					player: player,
					data: data,
					analytics: analytics,
					placement: placement,
					isFocused: player.id == focusedPlayerID,
					isCompact: isCompact,
					isExpanded: expandedPlayers.contains(player.id),
					resolvedUsers: resolvedUsers,
					highlight: $highlight,
					onToggleExpand: { toggleExpand(player.id) },
					onFocus: { onSelectFocus?(player.id) }
				)
			}
		} else {
			ForEach(Array(data.rankedTeams.enumerated()), id: \.element.id) { index, team in
				let teamPlayers = sortedPlayers(playersByTeam[team.id] ?? [])
				let placementRank = team.placement ?? (index + 1)
				let placement = PlacementFormatter.ordinal(placementRank)
				let teamColor = data.relativeColor(of: team.id) ?? .valorantRed
				
				VStack(alignment: .leading, spacing: 8) {
					HStack(spacing: 8) {
						Text(placement.uppercased())
							.font(.caption.weight(.bold))
							.foregroundStyle(teamColor)
						
						if let mascotAsset = team.id.gauntletMascotAssetName {
							Image.bundledAsset(mascotAsset)
								.resizable()
								.scaledToFit()
								.frame(width: 18, height: 18)
						}
						
						if let teamName = team.id.gauntletDisplayName {
							Text(teamName)
								.font(.caption.weight(.semibold))
								.foregroundStyle(teamColor)
						}
						
						if team.id == focusedTeamID {
							Text("YOUR TEAM")
								.font(.caption2.weight(.bold))
								.foregroundStyle(Color.valorantSelf)
						}
						
						Spacer()
						
						if team.pointCount > 0 {
							Text("\(team.pointCount) pts")
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
						} else if let health = team.health, health.starting > 0 {
							Text("\(health.ending)/\(health.starting) HP")
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
						}
					}
					.padding(.horizontal, 4)
					.padding(.top, index == 0 ? 0 : 4)
					
					ForEach(teamPlayers) { player in
						ScoreboardRowView(
							player: player,
							data: data,
							analytics: analytics,
							isFocused: player.id == focusedPlayerID,
							isCompact: isCompact,
							isExpanded: expandedPlayers.contains(player.id),
							resolvedUsers: resolvedUsers,
							highlight: $highlight,
							onToggleExpand: { toggleExpand(player.id) },
							onFocus: { onSelectFocus?(player.id) }
						)
					}
				}
			}
		}
	}
	
	private var focusedTeamID: Team.ID? {
		data.players[focusedPlayerID]?.teamID ?? data.myself?.teamID
	}
	
	private func toggleExpand(_ id: Player.ID) {
		withAnimation(.easeInOut(duration: 0.2)) {
			if expandedPlayers.contains(id) {
				expandedPlayers.remove(id)
			} else {
				expandedPlayers.insert(id)
			}
		}
	}
	
	private func sortedPlayers(_ players: [Player]) -> [Player] {
		players.sorted { lhs, rhs in
			let l = analytics.byPlayer[lhs.id]
			let r = analytics.byPlayer[rhs.id]
			switch sort {
			case .score:
				let lv = l?.performanceScore ?? 0
				let rv = r?.performanceScore ?? 0
				if lv != rv { return lv > rv }
			case .kast:
				let lv = l?.kastPercent ?? 0
				let rv = r?.kastPercent ?? 0
				if abs(lv - rv) > 0.01 { return lv > rv }
			case .adr:
				let lv = l?.adr ?? 0
				let rv = r?.adr ?? 0
				if abs(lv - rv) > 0.01 { return lv > rv }
			case .deaths:
				let lv = l?.deaths ?? 0
				let rv = r?.deaths ?? 0
				if lv != rv { return lv < rv }
			case .kills:
				let lv = l?.kills ?? 0
				let rv = r?.kills ?? 0
				if lv != rv { return lv > rv }
			case .acs:
				let lv = l?.acs ?? Double(lhs.score)
				let rv = r?.acs ?? Double(rhs.score)
				if abs(lv - rv) > 0.01 { return lv > rv }
			}
			return lhs.score > rhs.score
		}
	}
}

struct ScoreboardRowView: View {
	let player: Player
	let data: MatchViewData
	let analytics: MatchAnalytics
	var placement: String? = nil
	var isFocused: Bool = false
	var isCompact: Bool = false
	var isExpanded: Bool = false
	var resolvedUsers: [Player.ID: User] = [:]
	@Binding var highlight: PlayerHighlightInfo
	var onToggleExpand: () -> Void = {}
	var onFocus: () -> Void = {}
	
	@LocalData var playerUser: User?
	@LocalData var summary: CareerSummary?
	
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	@Environment(\.seasons) private var seasons
	@Environment(\.valorantLoad) private var load
	@State private var agentMasteryLevel: Int?
	@State private var didAttemptMasteryLoad = false
	
	private static let partyPalette: [Color] = [
		Color.orange,
		Color.purple,
		Color.cyan,
		Color.pink,
		Color.mint,
	]
	
	init(
		player: Player,
		data: MatchViewData,
		analytics: MatchAnalytics,
		placement: String? = nil,
		isFocused: Bool = false,
		isCompact: Bool = false,
		isExpanded: Bool = false,
		resolvedUsers: [Player.ID: User] = [:],
		highlight: Binding<PlayerHighlightInfo>,
		onToggleExpand: @escaping () -> Void = {},
		onFocus: @escaping () -> Void = {}
	) {
		self.player = player
		self.data = data
		self.analytics = analytics
		self.placement = placement
		self.isFocused = isFocused
		self.isCompact = isCompact
		self.isExpanded = isExpanded
		self.resolvedUsers = resolvedUsers
		self._highlight = highlight
		self.onToggleExpand = onToggleExpand
		self.onFocus = onFocus
		self._playerUser = .init(id: player.id)
		self._summary = .init(id: player.id)
	}
	
	var body: some View {
		let pStats = analytics.byPlayer[player.id]
		let leadColor = leadingAccentColor
		let trailColor = trailingPartyColor
		
		HStack(spacing: 0) {
			Rectangle()
				.fill(leadColor)
				.frame(width: 4)
			
			VStack(spacing: 10) {
				if isCompact {
					compactHeader(stats: pStats)
				} else {
					standardHeader
					metricsStrip(stats: pStats)
				}
				
				if isExpanded, let pStats {
					Divider().opacity(0.28)
					expandedDetails(stats: pStats)
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.contentShape(Rectangle())
			.onTapGesture {
				onToggleExpand()
			}
			
			Rectangle()
				.fill(trailColor)
				.frame(width: 4)
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
		.withLocalData($playerUser, id: player.id)
		.withLocalData($summary, id: player.id)
		.task(id: isExpanded) {
			guard isExpanded, !didAttemptMasteryLoad, let agentID = player.agentID else { return }
			didAttemptMasteryLoad = true
			await load { client in
				if let mastery = try? await client.getAgentMastery(userID: player.id),
				   let entry = mastery.entry(for: agentID) {
					let lifetime = max(
						entry.flourish?.longLevel ?? 0,
						entry.trackProgressList.first?.trackLevel ?? 0,
						entry.flourish?.shortLevel ?? 0
					)
					if lifetime > 0 {
						agentMasteryLevel = lifetime
					}
				}
			}
		}
	}
	
	private var leadingAccentColor: Color {
		if player.id == data.myself?.id { return .yellow }
		return data.relativeColor(of: player.teamID) ?? .valorantBlue
	}
	
	private var trailingPartyColor: Color {
		if let partyIdx = data.parties.firstIndex(of: player.partyID) {
			return Self.partyPalette[partyIdx % Self.partyPalette.count]
		}
		return leadingAccentColor.opacity(0.6)
	}
	
	private var resolvedName: String {
		if shouldAnonymize(player.id) { return "Player" }
		if !player.gameName.isEmpty { return player.gameName }
		if let u = resolvedUsers[player.id], !u.gameName.isEmpty { return u.gameName }
		if let u = playerUser, !u.gameName.isEmpty { return u.gameName }
		return player.resolvedDisplayName(using: resolvedUsers)
	}
	
	private var resolvedTag: String {
		if shouldAnonymize(player.id) { return "" }
		if !player.tagLine.isEmpty { return player.tagLine }
		if let u = resolvedUsers[player.id], !u.tagLine.isEmpty { return u.tagLine }
		if let u = playerUser, !u.tagLine.isEmpty { return u.tagLine }
		return player.resolvedTagLine(using: resolvedUsers)
	}
	
	private var resolvedTier: Int {
		if player.competitiveTier >= 3 { return player.competitiveTier }
		if let currentAct = seasons?.currentAct()?.id,
		   let tier = summary?.competitiveInfo?.bySeason?[currentAct]?.competitiveTier,
		   tier >= 3 {
			return tier
		}
		if let latest = summary?.latestUpdate?.tierAfterUpdate, latest >= 3 {
			return latest
		}
		return player.competitiveTier
	}
	
	private var standardHeader: some View {
		HStack(spacing: 10) {
			if let placement {
				Text(placement)
					.font(.caption2.bold())
					.foregroundStyle(.secondary)
					.frame(minWidth: 24)
			}
			
			agentAvatar(size: 38)
			
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 4) {
					if analytics.matchMVPID == player.id {
						Image(systemName: "crown.fill")
							.font(.caption.bold())
							.foregroundStyle(.yellow)
					} else if analytics.teamMVPByTeam[player.teamID] == player.id {
						Image(systemName: "crown.fill")
							.font(.caption2.bold())
							.foregroundStyle(.secondary)
					}
					
					Text(resolvedName)
						.font(.subheadline.weight(.bold))
						.lineLimit(1)
					
					if !resolvedTag.isEmpty {
						Text("#\(resolvedTag)")
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				
				rankLine
			}
			
			Spacer(minLength: 4)
			
			profileLinkBadge
			
			Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
		}
	}
	
	private func compactHeader(stats: MatchAnalytics.PlayerMatchAnalytics?) -> some View {
		HStack(spacing: 8) {
			agentAvatar(size: 36)
			
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 3) {
					if analytics.matchMVPID == player.id {
						Image(systemName: "crown.fill")
							.font(.caption2.bold())
							.foregroundStyle(.yellow)
					} else if analytics.teamMVPByTeam[player.teamID] == player.id {
						Image(systemName: "crown.fill")
							.font(.caption2.bold())
							.foregroundStyle(.secondary)
					}
					HStack(spacing: 0) {
						Text(resolvedName)
							.font(.subheadline.weight(.bold))
							.lineLimit(1)
						if !resolvedTag.isEmpty {
							Text("#\(resolvedTag)")
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
								.layoutPriority(-1)
						}
					}
				}
				if resolvedTier >= 3 {
					rankLine
				}
			}
			.frame(minWidth: 92, alignment: .leading)
			
			Spacer(minLength: 4)
			
			if let stats {
				VStack(spacing: 1) {
					Text("\(stats.kills) / \(stats.deaths) / \(stats.assists)")
						.font(.caption.weight(.bold).monospacedDigit())
						.lineLimit(1)
					Text("K/D/A")
						.font(.system(size: 9, weight: .semibold))
						.foregroundStyle(.secondary)
				}
				.frame(minWidth: 56)
				
				VStack(spacing: 1) {
					Text(stats.performanceScore > 0 ? "\(stats.performanceScore)" : "—")
						.font(.caption.weight(.bold).monospacedDigit())
					Text("SCORE")
						.font(.system(size: 9, weight: .semibold))
						.foregroundStyle(.secondary)
				}
				.frame(minWidth: 38)
				
				VStack(spacing: 1) {
					Text("\(Int(stats.acs.rounded()))")
						.font(.caption.weight(.bold).monospacedDigit())
					Text("ACS")
						.font(.system(size: 9, weight: .semibold))
						.foregroundStyle(.secondary)
				}
				.frame(minWidth: 32)
			}
			
			Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
		}
	}
	
	@ViewBuilder
	private var rankLine: some View {
		let curTier = resolvedTier
		let curInfo = seasons?.currentTierInfo(number: curTier)
		let curName = curInfo?.name ?? (curTier == 0 ? "UNRANKED" : "TIER \(curTier)")
		let peakInfo = summary?.peakRankInfo(seasons: seasons)
		
		HStack(spacing: 4) {
			if let peakInfo, peakInfo.number > curTier, curTier >= 3 {
				if let tri = peakInfo.rankTriangleUpwards {
					tri.view(shouldLoadImmediately: true)
						.frame(width: 11, height: 11)
				}
				Image(systemName: "arrow.right")
					.font(.system(size: 8, weight: .bold))
					.foregroundStyle(.secondary)
			}
			
			CompetitiveTierImage(tier: curTier, time: data.details.matchInfo.gameStart)
				.frame(width: 14, height: 14)
			
			Text(curName.uppercased())
				.font(.system(size: 10, weight: .semibold))
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}
	
	@ViewBuilder
	private func agentAvatar(size: CGFloat) -> some View {
		Group {
			if let agentID = player.agentID {
				AgentImage.icon(
					agentID,
					teamID: player.teamID,
					isOVariant: data.isGauntletOVariant(for: player)
				)
			} else {
				Image(systemName: "eye.fill")
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: size, height: size)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
		.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
	}
	
	private var profileLinkBadge: some View {
		TransparentNavigationLink {
			MatchListView(userID: player.id)
		} label: {
			ZStack {
				Circle()
					.fill(Color.accentColor)
					.frame(width: 24, height: 24)
				Image(systemName: "person.fill")
					.font(.system(size: 12, weight: .bold))
					.foregroundStyle(.white)
			}
		}
		.buttonStyle(.plain)
	}
	
	@ViewBuilder
	private func metricsStrip(stats: MatchAnalytics.PlayerMatchAnalytics?) -> some View {
		if let stats {
			let kdColor: Color = stats.kd >= 1.5 ? Color.valorantBlue : stats.kd < 0.9 ? Color.valorantRed : .primary
			HStack(spacing: 0) {
				metricColumn(
					value: String(format: "%.2f", stats.kd),
					label: "K/D",
					valueColor: kdColor
				)
				metricColumn(
					value: "\(stats.kills) / \(stats.deaths) / \(stats.assists)",
					label: "K/D/A",
					valueColor: .primary
				)
				metricColumn(
					value: stats.performanceScore > 0 ? "\(stats.performanceScore)" : "—",
					label: "SCORE",
					valueColor: .primary
				)
				metricColumn(
					value: "\(Int(stats.acs.rounded()))",
					label: "ACS",
					valueColor: .primary
				)
			}
		}
	}
	
	private func metricColumn(value: String, label: String, valueColor: Color) -> some View {
		VStack(spacing: 2) {
			Text(value)
				.font(.subheadline.weight(.bold).monospacedDigit())
				.foregroundStyle(valueColor)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
			Text(label)
				.font(.system(size: 10, weight: .semibold))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
	}
	
	private func expandedDetails(stats: MatchAnalytics.PlayerMatchAnalytics) -> some View {
		VStack(spacing: 10) {
			TransparentNavigationLink {
				MatchListView(userID: player.id)
			} label: {
				HStack(spacing: 8) {
					Image(systemName: "person.circle")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.secondary)
					Text("Open profile")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.primary)
					Spacer()
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 10)
				.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
			}
			.buttonStyle(.plain)
			
			VStack(spacing: 8) {
				expandedStatRow("ADR", value: "\(Int(stats.adr.rounded()))")
				expandedStatRow("Headshot Rate", value: "\(Int(stats.hsPercent.rounded())) %")
				expandedStatRow("KAST", value: "\(Int(stats.kastPercent.rounded())) %")
				expandedStatRow("First Bloods", value: "\(stats.firstBloods)")
				expandedStatRow("First Deaths", value: "\(stats.firstDeaths)")
			}
			
			Divider().opacity(0.28)
			
			VStack(spacing: 8) {
				HStack {
					Text("Performance Score")
						.font(.subheadline)
						.foregroundStyle(.secondary)
					Spacer()
					Text("\(stats.performanceScore)")
						.font(.subheadline.weight(.bold).monospacedDigit())
				}
				
				subScoreStatRow("Fights", value: stats.fightsScore)
				subScoreStatRow("Support", value: stats.supportScore)
			}
			
			Divider().opacity(0.28)
			
			let accountLevel = player.accountLevel ?? 0
			HStack {
				Text(agentMasteryLevel != nil || accountLevel <= 0 ? "Agent Mastery Level" : "Account Level")
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Spacer()
				if let mastery = agentMasteryLevel {
					Text("\(mastery)")
						.font(.subheadline.weight(.bold).monospacedDigit())
				} else if accountLevel > 0 {
					Text("\(accountLevel)")
						.font(.subheadline.weight(.bold).monospacedDigit())
				} else {
					Text(didAttemptMasteryLoad ? "—" : "...")
						.font(.subheadline.weight(.bold).monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
			
			if !isFocused {
				Button {
					onFocus()
				} label: {
					HStack {
						Label("Focus Player", systemImage: "scope")
							.font(.caption.weight(.semibold))
							.foregroundStyle(Color.accentColor)
						Spacer()
					}
					.padding(.top, 2)
				}
				.buttonStyle(.plain)
			}
		}
	}
	
	private func expandedStatRow(_ label: String, value: String) -> some View {
		HStack {
			Text(label)
				.font(.subheadline)
				.foregroundStyle(.secondary)
			Spacer()
			Text(value)
				.font(.subheadline.weight(.bold).monospacedDigit())
				.foregroundStyle(.primary)
		}
	}
	
	private func subScoreStatRow(_ label: String, value: Int) -> some View {
		HStack(spacing: 6) {
			Text(label)
				.font(.subheadline)
				.foregroundStyle(.secondary)
			Spacer()
			Text("\(value)")
				.font(.subheadline.weight(.bold).monospacedDigit())
			Group {
				if value >= 330 {
					Image(systemName: "chevron.up.2")
						.foregroundStyle(.green)
				} else if value >= 270 {
					Image(systemName: "chevron.up")
						.foregroundStyle(.green)
				} else if value >= 210 {
					Image(systemName: "minus")
						.foregroundStyle(.secondary)
				} else if value >= 170 {
					Image(systemName: "chevron.down")
						.foregroundStyle(Color.valorantRed)
				} else {
					Image(systemName: "chevron.down.2")
						.foregroundStyle(Color.valorantRed)
				}
			}
			.font(.caption.weight(.bold))
			.frame(width: 14)
		}
	}
}

#if DEBUG
struct ScoreboardView_Previews: PreviewProvider {
	static var previews: some View {
		let data = PreviewData.singleMatchData
		let analytics = MatchAnalytics(details: data.details)
		ScrollView {
			ScoreboardView(
				data: data,
				analytics: analytics,
				focusedPlayerID: data.myself?.id ?? data.details.players[0].id,
				highlight: .constant(.init())
			)
			.padding()
		}
		.background(Color.groupedBackground)
	}
}
#endif
