import SwiftUI
import ValorantAPI

struct MatchDuelsTabView: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedTeamID: Team.ID
	
	@State private var selectedMatchup: MatchAnalytics.DuelMatchup?
	
	var body: some View {
		if let matrix = analytics.duelMatrix(for: focusedTeamID) {
			VStack(alignment: .leading, spacing: 14) {
				highlightCarousel(matrix: matrix)
				
				Text("Duel Matrix")
					.font(.headline)
					.padding(.horizontal, 4)
				
				matrixGrid(matrix: matrix)
				
				HStack(spacing: 6) {
					Image(systemName: "hand.tap")
					Text("Tap a matchup to see the full duel breakdown.")
				}
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
				
				summaryTotalsCard(matrix: matrix)
			}
			.sheet(item: $selectedMatchup) { matchup in
				NavigationView {
					DuelBreakdownSheet(data: data, matchup: matchup)
				}
			}
		} else {
			Text("Head-to-head duel matrix is available in 2-team round matches.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity)
				.padding(24)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	// MARK: - Highlight Cards
	
	private func highlightCarousel(matrix: MatchAnalytics.DuelMatrixData) -> some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 10) {
				if let top = matrix.topRivalry {
					highlightCard(icon: "flame.fill", title: "TOP RIVALRY", matchup: top)
				}
				if let mismatch = matrix.biggestMismatch {
					highlightCard(icon: "arrow.up.right", title: "BIGGEST MISMATCH", matchup: mismatch)
				}
				if let traded = matrix.mostTraded {
					highlightCard(icon: "arrow.triangle.2.circlepath", title: "MOST TRADED", matchup: traded)
				}
			}
		}
	}
	
	private func highlightCard(
		icon: String,
		title: String,
		matchup: MatchAnalytics.DuelMatchup
	) -> some View {
		Button {
			selectedMatchup = matchup
		} label: {
			VStack(spacing: 10) {
				HStack(spacing: 5) {
					Image(systemName: icon)
					Text(title)
				}
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
				
				HStack(spacing: 10) {
					agentBadge(player: matchup.allyPlayer, size: 32)
					
					VStack(spacing: 1) {
						Text("\(matchup.allyKills) : \(matchup.enemyKills)")
							.font(.headline.bold().monospacedDigit())
							.foregroundStyle(.primary)
						Text("\(matchup.totalDuels) duels")
							.font(.caption2.monospacedDigit())
							.foregroundStyle(.secondary)
					}
					
					agentBadge(player: matchup.enemyPlayer, size: 32)
				}
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 12)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		}
		.buttonStyle(.plain)
	}
	
	// MARK: - Matrix Grid
	
	private func matrixGrid(matrix: MatchAnalytics.DuelMatrixData) -> some View {
		VStack(spacing: 6) {
			// Column headers (Enemy players)
			HStack(spacing: 6) {
				Color.clear
					.frame(width: 42, height: 42)
				
				ForEach(matrix.enemyPlayers) { enemy in
					agentBadge(player: enemy, size: 42)
						.frame(maxWidth: .infinity)
				}
			}
			
			// Rows (Ally players)
			ForEach(matrix.allyPlayers) { ally in
				HStack(spacing: 6) {
					agentBadge(player: ally, size: 42)
						.frame(width: 42, height: 42)
					
					ForEach(matrix.enemyPlayers) { enemy in
						let key = MatchAnalytics.DuelPairKey(allyID: ally.id, enemyID: enemy.id)
						if let matchup = matrix.cells[key] {
							matrixCell(matchup)
								.frame(maxWidth: .infinity)
						}
					}
				}
			}
		}
		.padding(12)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func matrixCell(_ matchup: MatchAnalytics.DuelMatchup) -> some View {
		let a = matchup.allyKills
		let e = matchup.enemyKills
		let bg: Color = {
			if a > e { return Color.green.opacity(0.22) }
			if e > a { return Color.valorantRed.opacity(0.22) }
			return Color.tertiaryGroupedBackground
		}()
		let stroke: Color = {
			if a > e { return Color.green.opacity(0.35) }
			if e > a { return Color.valorantRed.opacity(0.35) }
			return Color.secondary.opacity(0.2)
		}()
		let leftColor: Color = a > e ? .green : (e > a ? .primary : .primary)
		let rightColor: Color = e > a ? Color.valorantRed : (a > e ? .secondary : .primary)
		
		return Button {
			selectedMatchup = matchup
		} label: {
			HStack(spacing: 2) {
				Text("\(a)")
					.foregroundStyle(leftColor)
				Text(":")
					.foregroundStyle(.secondary)
				Text("\(e)")
					.foregroundStyle(rightColor)
			}
			.font(.subheadline.bold().monospacedDigit())
			.frame(maxWidth: .infinity, minHeight: 48)
			.background(bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.stroke(stroke, lineWidth: 1)
			)
		}
		.buttonStyle(.plain)
	}
	
	// MARK: - Totals Card
	
	private func summaryTotalsCard(matrix: MatchAnalytics.DuelMatrixData) -> some View {
		let pct = Int(round(matrix.allyDuelWinRate * Double(100)))
		return HStack(spacing: 0) {
			VStack(spacing: 4) {
				Text("TOTAL DUELS")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
				Text("\(matrix.totalDuels)")
					.font(.title3.bold().monospacedDigit())
			}
			.frame(maxWidth: .infinity)
			
			VStack(spacing: 4) {
				Text("FIRST BLOODS")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
				Text("\(matrix.allyFirstBloods)")
					.font(.title3.bold().monospacedDigit())
			}
			.frame(maxWidth: .infinity)
			
			VStack(spacing: 4) {
				Text("WIN RATE")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
				Text("\(pct) %")
					.font(.title3.bold().monospacedDigit())
					.foregroundStyle(pct >= 50 ? Color.green : Color.valorantRed)
			}
			.frame(maxWidth: .infinity)
		}
		.padding(.vertical, 14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	@ViewBuilder
	private func agentBadge(player: Player, size: CGFloat) -> some View {
		Group {
			if let agentID = player.agentID {
				AgentImage.icon(
					agentID,
					teamID: player.teamID,
					isOVariant: data.isGauntletOVariant(for: player)
				)
			} else {
				Image(systemName: "person.fill")
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: size, height: size)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
		.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
	}
}

private struct DuelBreakdownSheet: View {
	let data: MatchViewData
	let matchup: MatchAnalytics.DuelMatchup
	
	@Environment(\.dismiss) private var dismiss
	@Environment(\.assets) private var assets
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				HStack(spacing: 16) {
					VStack(spacing: 6) {
						agentPortrait(matchup.allyPlayer)
						Text(matchup.allyPlayer.gameName.isEmpty ? "Ally" : matchup.allyPlayer.gameName)
							.font(.subheadline.weight(.bold))
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity)
					
					VStack(spacing: 2) {
						Text("\(matchup.allyKills) : \(matchup.enemyKills)")
							.font(.title.bold().monospacedDigit())
						Text("\(matchup.totalDuels) duels")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					
					VStack(spacing: 6) {
						agentPortrait(matchup.enemyPlayer)
						Text(matchup.enemyPlayer.gameName.isEmpty ? "Enemy" : matchup.enemyPlayer.gameName)
							.font(.subheadline.weight(.bold))
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity)
				}
				.padding(16)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				
				VStack(spacing: 10) {
					statCompareRow("Kills", left: "\(matchup.allyKills)", right: "\(matchup.enemyKills)")
					statCompareRow("First Bloods", left: "\(matchup.allyFirstBloods)", right: "\(matchup.enemyFirstBloods)")
					statCompareRow("Damage Dealt", left: "\(matchup.allyDamage)", right: "\(matchup.enemyDamage)")
					statCompareRow("Headshots", left: "\(matchup.allyHeadshots)", right: "\(matchup.enemyHeadshots)")
				}
				.padding(16)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				
				VStack(alignment: .leading, spacing: 10) {
					Text("Round Timeline")
						.font(.headline)
					
					if matchup.events.isEmpty {
						Text("No kills occurred between these two players.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					} else {
						ForEach(matchup.events) { event in
							HStack(spacing: 10) {
								Text("R\(event.roundNumber + 1)")
									.font(.caption.bold().monospacedDigit())
									.foregroundStyle(.white)
									.frame(width: 34, height: 24)
									.background(
										event.killerIsAlly ? Color.green : Color.valorantRed,
										in: RoundedRectangle(cornerRadius: 6, style: .continuous)
									)
								
								Text(event.killerIsAlly
									? "\(matchup.allyPlayer.gameName) eliminated \(matchup.enemyPlayer.gameName)"
									: "\(matchup.enemyPlayer.gameName) eliminated \(matchup.allyPlayer.gameName)")
									.font(.caption.weight(.medium))
									.lineLimit(1)
								
								Spacer()
								
								if let weaponID = event.weaponID {
									WeaponImage.killStreamIcon(weaponID)
										.frame(width: 36, height: 14)
										.foregroundStyle(.secondary)
								}
								
								if event.isFirstBlood {
									Text("FB")
										.font(.caption2.bold())
										.foregroundStyle(.orange)
								}
							}
							.padding(.vertical, 4)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
			}
			.padding(16)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Duel Breakdown")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Done") { dismiss() }
			}
		}
	}
	
	private func statCompareRow(_ title: String, left: String, right: String) -> some View {
		HStack {
			Text(left)
				.font(.subheadline.weight(.bold).monospacedDigit())
				.frame(width: 60, alignment: .leading)
			Spacer()
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
			Spacer()
			Text(right)
				.font(.subheadline.weight(.bold).monospacedDigit())
				.frame(width: 60, alignment: .trailing)
		}
	}
	
	@ViewBuilder
	private func agentPortrait(_ player: Player) -> some View {
		if let agentID = player.agentID {
			AgentImage.icon(
				agentID,
				teamID: player.teamID,
				isOVariant: data.isGauntletOVariant(for: player)
			)
			.frame(width: 52, height: 52)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
			.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
		}
	}
}
