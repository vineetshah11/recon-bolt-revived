import SwiftUI
import ValorantAPI

struct ScoreboardView: View {
	let data: MatchViewData
	@Binding var highlight: PlayerHighlightInfo
	
	@Environment(\.valorantLoad) private var load
	
	private var teams: [Team] {
		data.details.teams
			.sorted { $0.pointCount < $1.pointCount }
			.movingToFront { $0.id == data.myself?.teamID }
	}
	
	var body: some View {
		VStack(spacing: 14) {
			ForEach(teams, id: \.id) { team in
				teamSection(team)
			}
			
			AsyncButton(action: fetchRanks) {
				Label("Update Ranks", systemImage: "arrow.clockwise")
					.font(.system(.footnote, design: .rounded).weight(.semibold))
					.foregroundColor(.white)
					.padding(.vertical, 11)
					.frame(maxWidth: .infinity)
					.background(
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.fill(Color.white.opacity(0.07))
					)
			}
			.buttonStyle(.plain)
		}
		.padding(.horizontal)
	}
	
	private func teamSection(_ team: Team) -> some View {
		let accent = data.relativeColor(of: team.id) ?? .valorantBlue
		let players = sortedPlayers(in: team)
		
		return VStack(spacing: 0) {
			teamHeader(team, accent: accent)
			
			VStack(spacing: 4) {
				ForEach(players) { player in
					ScoreboardRowView(player: player, data: data, accent: accent, highlight: $highlight)
				}
			}
			.padding(.horizontal, 6)
			.padding(.bottom, 6)
		}
		.background(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(Color.white.opacity(0.045))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.stroke(ReconTheme.border, lineWidth: 1)
		)
	}
	
	private func teamHeader(_ team: Team, accent: Color) -> some View {
		HStack(spacing: 8) {
			RoundedRectangle(cornerRadius: 2, style: .continuous)
				.fill(accent)
				.frame(width: 3, height: 14)
			
			teamName(team)
				.font(.system(.subheadline, design: .rounded).weight(.bold))
				.foregroundColor(.white)
			
			Spacer(minLength: 6)
			
			if team.won {
				Text("Win", comment: "Scoreboard: team result pill")
					.font(.system(.caption2, design: .rounded).weight(.heavy))
					.textCase(.uppercase)
					.foregroundColor(.white)
					.padding(.horizontal, 7)
					.padding(.vertical, 3)
					.background(Capsule().fill(accent))
			}
			
			Text(verbatim: "\(team.pointCount)")
				.font(.system(.subheadline, design: .rounded).weight(.bold))
				.monospacedDigit()
				.foregroundColor(accent)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
	}
	
	@ViewBuilder
	private func teamName(_ team: Team) -> some View {
		if team.id == data.myself?.teamID {
			Text("Your Team", comment: "Scoreboard: section header")
		} else if data.myself != nil {
			Text("Enemy Team", comment: "Scoreboard: section header")
		} else {
			Text("Team", comment: "Scoreboard: section header when the tracked player could not be identified")
		}
	}
	
	private func sortedPlayers(in team: Team) -> [Player] {
		data.details.players
			.filter { $0.teamID == team.id }
			.sorted { $0.score > $1.score }
	}
	
	private func fetchRanks() async {
		await load {
			for playerID in data.players.keys {
				try await $0.fetchCareerSummary(for: playerID)
			}
		}
	}
}

struct ScoreboardRowView: View {
	private static let partyLetters = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
		.map { String(UnicodeScalar($0)!) }
	
	let player: Player
	let data: MatchViewData
	var accent: Color
	@Binding var highlight: PlayerHighlightInfo
	
	@LocalData var summary: CareerSummary?
	
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	
	private var isMyself: Bool {
		player.id == data.myself?.id
	}
	
	private var acs: Int? {
		guard let stats = player.stats, stats.roundsPlayed > 0 else { return nil }
		return stats.score / stats.roundsPlayed
	}
	
	private var partyLetter: String? {
		guard let index = data.parties.firstIndex(of: player.partyID) else { return nil }
		guard Self.partyLetters.indices.contains(index) else { return nil }
		return Self.partyLetters[index]
	}
	
	var body: some View {
		HStack(spacing: 8) {
			ScoreboardAgentIcon(agentID: player.agentID, accent: accent, size: 32)
			
			identity
			
			Spacer(minLength: 4)
			
			rankEmblem
			
			kda
			
			acsLabel
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 6)
		.background(
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(accent.opacity(isMyself ? 0.22 : 0.1))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.stroke(accent.opacity(isMyself ? 0.6 : 0), lineWidth: 1)
		)
		.opacity(highlight.shouldFade(player.id) ? 0.45 : 1)
		.contentShape(Rectangle())
		.onTapGesture {
			highlight.switchHighlight(to: player)
		}
		.withLocalData($summary, id: player.id)
	}
	
	private var identity: some View {
		VStack(alignment: .leading, spacing: 1) {
			Group {
				if shouldAnonymize(player.id) {
					Text("Player", comment: "Scoreboard: anonymized player name")
						.foregroundColor(ReconTheme.secondary)
				} else {
					Text(player.gameName)
						.foregroundColor(.white)
				}
			}
			.font(.system(.subheadline, design: .rounded).weight(isMyself ? .bold : .medium))
			.lineLimit(1)
			
			HStack(spacing: 5) {
				if let partyLetter {
					Text("Party \(partyLetter)", comment: "Scoreboard: party letter")
						.foregroundColor(accent.opacity(0.9))
				}
				
				Text(verbatim: "#\(player.tagLine)")
					.foregroundColor(ReconTheme.secondary)
			}
			.font(.system(.caption2, design: .rounded))
			.lineLimit(1)
		}
	}
	
	private var rankEmblem: some View {
		RankInfoView(
			summary: summary,
			size: 22,
			lineWidth: 1.5,
			shouldShowProgress: false,
			shouldFadeUnranked: true
		)
	}
	
	@ViewBuilder
	private var kda: some View {
		if let stats = player.stats {
			Text(verbatim: "\(stats.kills)/\(stats.deaths)/\(stats.assists)")
				.font(.system(.caption, design: .rounded).weight(.medium))
				.monospacedDigit()
				.foregroundColor(.white.opacity(0.85))
				.frame(width: 64, alignment: .trailing)
		} else {
			Text("–")
				.font(.system(.caption, design: .rounded))
				.foregroundColor(ReconTheme.secondary)
				.frame(width: 64, alignment: .trailing)
		}
	}
	
	@ViewBuilder
	private var acsLabel: some View {
		VStack(alignment: .trailing, spacing: 0) {
			if let acs {
				Text(verbatim: "\(acs)")
					.font(.system(.subheadline, design: .rounded).weight(.bold))
					.monospacedDigit()
					.foregroundColor(.white)
				
				Text("ACS", comment: "Scoreboard: average combat score column header")
					.font(.system(size: 8, weight: .semibold, design: .rounded))
					.foregroundColor(ReconTheme.secondary)
			} else {
				Text("–")
					.font(.system(.subheadline, design: .rounded))
					.foregroundColor(ReconTheme.secondary)
			}
		}
		.frame(width: 34, alignment: .trailing)
	}
}

/// Agent portrait in a rounded square, tinted with the team's color.
struct ScoreboardAgentIcon: View {
	let agentID: Agent.ID?
	var accent: Color
	var size: CGFloat = 32
	
	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
				.fill(accent.opacity(0.3))
			
			if let agentID {
				AgentImage.icon(agentID)
					.aspectRatio(contentMode: .fill)
					.frame(width: size, height: size)
					.clipped()
			} else {
				Image(systemName: "eye")
					.font(.system(size: size * 0.4, weight: .semibold))
					.foregroundColor(.white.opacity(0.7))
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
	}
}

extension ScoreboardRowView {
	init(player: Player, data: MatchViewData, highlight: Binding<PlayerHighlightInfo>) {
		self.init(
			player: player, data: data,
			accent: data.relativeColor(of: player) ?? .valorantBlue,
			highlight: highlight,
			summary: .init(id: player.id)
		)
	}
}

#if DEBUG
struct ScoreboardView_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			ScoreboardView(data: PreviewData.singleMatchData, highlight: .constant(.init()))
				.padding(.vertical)
				.preferredColorScheme(.dark)
			
			ScoreboardRowView(
				player: PreviewData.singleMatch.players[0],
				data: PreviewData.singleMatchData,
				highlight: .constant(.init())
			)
			.padding()
		}
		.fixedSize(horizontal: true, vertical: true)
		.previewLayout(.sizeThatFits)
	}
}
#endif
