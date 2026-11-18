import SwiftUI
import ValorantAPI

/// Per-player combat score comparison for a finished match.
struct MatchPerformanceView: View {
	let data: MatchViewData
	@Binding var highlight: PlayerHighlightInfo
	
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	
	private var teams: [Team] {
		data.details.teams
			.sorted { $0.pointCount < $1.pointCount }
			.movingToFront { $0.id == data.myself?.teamID }
	}
	
	private var maxACS: Int {
		data.details.players.compactMap { acs(for: $0) }.max() ?? 0
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			VStack(alignment: .leading, spacing: 3) {
				Text("Average Combat Score", comment: "Match Details: performance tab title")
					.font(.system(.subheadline, design: .rounded).weight(.bold))
					.foregroundColor(.white)
				
				Text("Combat score per round for every player in this match.", comment: "Match Details: performance tab subtitle")
					.font(.system(.caption, design: .rounded))
					.foregroundColor(ReconTheme.secondary)
			}
			
			ForEach(teams, id: \.id) { team in
				teamCard(team)
			}
		}
		.padding(.horizontal)
	}
	
	private func teamCard(_ team: Team) -> some View {
		let accent = data.relativeColor(of: team.id) ?? .valorantBlue
		let players = data.details.players
			.filter { $0.teamID == team.id }
			.sorted { (acs(for: $0) ?? 0) > (acs(for: $1) ?? 0) }
		
		return VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				RoundedRectangle(cornerRadius: 2, style: .continuous)
					.fill(accent)
					.frame(width: 3, height: 14)
				
				teamName(team)
					.font(.system(.subheadline, design: .rounded).weight(.bold))
					.foregroundColor(.white)
				
				Spacer(minLength: 6)
				
				Text(verbatim: "\(team.pointCount)")
					.font(.system(.subheadline, design: .rounded).weight(.bold))
					.monospacedDigit()
					.foregroundColor(accent)
			}
			
			ForEach(players) { player in
				row(for: player, accent: accent)
			}
		}
		.padding(12)
		.background(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(Color.white.opacity(0.045))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.stroke(ReconTheme.border, lineWidth: 1)
		)
	}
	
	private func row(for player: Player, accent: Color) -> some View {
		let isMyself = player.id == data.myself?.id
		let score = acs(for: player)
		let fraction = maxACS > 0 ? CGFloat(score ?? 0) / CGFloat(maxACS) : 0
		
		return HStack(spacing: 8) {
			ScoreboardAgentIcon(agentID: player.agentID, accent: accent, size: 26)
			
			Group {
				if shouldAnonymize(player.id) {
					Text("Player", comment: "Scoreboard: anonymized player name")
						.foregroundColor(ReconTheme.secondary)
				} else {
					Text(player.gameName)
						.foregroundColor(.white)
				}
			}
			.font(.system(.caption, design: .rounded).weight(isMyself ? .bold : .medium))
			.lineLimit(1)
			.frame(width: 78, alignment: .leading)
			
			GeometryReader { geometry in
				ZStack(alignment: .leading) {
					Capsule()
						.fill(Color.white.opacity(0.07))
					
					Capsule()
						.fill(accent.opacity(isMyself ? 1 : 0.8))
						.frame(width: max(4, geometry.size.width * fraction))
				}
			}
			.frame(height: 8)
			
			Text(verbatim: score.map { "\($0)" } ?? "–")
				.font(.system(.caption, design: .rounded).weight(.bold))
				.monospacedDigit()
				.foregroundColor(isMyself ? .white : .white.opacity(0.85))
				.frame(width: 30, alignment: .trailing)
		}
		.opacity(highlight.shouldFade(player.id) ? 0.45 : 1)
		.contentShape(Rectangle())
		.onTapGesture {
			highlight.switchHighlight(to: player)
		}
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
	
	private func acs(for player: Player) -> Int? {
		guard let stats = player.stats, stats.roundsPlayed > 0 else { return nil }
		return stats.score / stats.roundsPlayed
	}
}

#if DEBUG
struct MatchPerformanceView_Previews: PreviewProvider {
	static var previews: some View {
		MatchPerformanceView(data: PreviewData.singleMatchData, highlight: .constant(.init()))
			.padding(.vertical)
			.preferredColorScheme(.dark)
	}
}
#endif
