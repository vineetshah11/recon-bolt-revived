import SwiftUI
import ValorantAPI
import HandyOperators

struct MatchHeroBanner: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedPlayer: Player
	
	@Environment(\.assets) private var assets
	
	private static let heroDateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "dd/MM/yy · HH:mm"
		return f
	}()
	
	private static let durationFormatter: DateComponentsFormatter = {
		let f = DateComponentsFormatter()
		f.unitsStyle = .abbreviated
		f.allowedUnits = [.hour, .minute, .second]
		f.maximumUnitCount = 2
		return f
	}()
	
	var body: some View {
		let matchInfo = data.details.matchInfo
		let mapName = assets?.maps[matchInfo.mapID]?.displayName ?? "Map"
		let subtitle = analytics.serverDisplayName ?? mapName
		let lengthText = Self.durationFormatter.string(from: matchInfo.gameLength) ?? ""
		
		VStack(spacing: 0) {
			HStack(alignment: .center, spacing: 10) {
				GameModeImage(id: matchInfo.modeID)
					.frame(width: 28, height: 28)
					.foregroundStyle(.secondary)
				
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 5) {
						Image(systemName: "desktopcomputer")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
						matchInfo.queueLabel
							.font(.subheadline.weight(.bold))
							.lineLimit(1)
					}
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				VStack(alignment: .trailing, spacing: 2) {
					Text(Self.heroDateFormatter.string(from: matchInfo.gameStart))
						.font(.caption.weight(.medium).monospacedDigit())
						.foregroundStyle(.secondary)
					Text(lengthText)
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 12)
			
			Color.clear
				.frame(height: 88)
				.frame(maxWidth: .infinity)
				.background {
					MapImage.wideImage(matchInfo.mapID)
						.scaledToFill()
				}
				.clipped()
				.overlay {
					heroScoreBadge
						.padding(.horizontal, 16)
						.padding(.vertical, 8)
						.background(.ultraThinMaterial, in: Capsule())
						.shadow(color: .black.opacity(0.35), radius: 8, y: 2)
				}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
		.contextMenu {
			Button {
				UIPasteboard.general.string = data.details.id.description
			} label: {
				Label("Copy Match ID", systemImage: "square.on.square")
			}
		}
	}
	
	@ViewBuilder
	private var heroScoreBadge: some View {
		if let ownTeam = data.details.teams.first(where: { $0.id == focusedPlayer.teamID }),
		   let enemyTeam = data.details.teams.first(where: { $0.id != focusedPlayer.teamID }),
		   data.details.teams.count == 2 {
			HStack(spacing: 6) {
				Text("\(ownTeam.roundsWon)")
					.foregroundStyle(Color.valorantBlue)
				Text("–")
					.foregroundStyle(.secondary)
				Text("\(enemyTeam.roundsWon)")
					.foregroundStyle(Color.valorantRed)
			}
			.font(.title3.bold().monospacedDigit())
		} else {
			ScoreSummaryView(
				teams: data.details.teams,
				players: data.details.players,
				ownTeamID: focusedPlayer.teamID
			)
			.font(.title3.bold().monospacedDigit())
		}
	}
}

struct MatchSummaryTabView: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedPlayer: Player
	var resolvedUsers: [Player.ID: User] = [:]
	
	@LocalData var focusedSummary: CareerSummary?
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@State private var showScoreInfo = false
	@State private var showBreakdown = false
	@State private var expandedMetrics: Set<String> = []
	
	init(
		data: MatchViewData,
		analytics: MatchAnalytics,
		focusedPlayer: Player,
		resolvedUsers: [Player.ID: User] = [:]
	) {
		self.data = data
		self.analytics = analytics
		self.focusedPlayer = focusedPlayer
		self.resolvedUsers = resolvedUsers
		self._focusedSummary = .init(id: focusedPlayer.id)
	}
	
	var body: some View {
		let stats = analytics.byPlayer[focusedPlayer.id]
		let comparison = analytics.lobbyComparison(for: focusedPlayer.id)
		
		VStack(spacing: 16) {
			focusedPlayerCard
			
			if let stats {
				performanceScoreCard(stats: stats)
				
				if let comparison {
					vsLobbyCard(stats: stats, comparison: comparison)
				}
				
				if !data.isMultiTeam && !data.details.roundResults.isEmpty {
					halvesSection(stats: stats)
				}
				
				let matchAccolades = AccoladesCalculator.accolades(
					for: focusedPlayer.id,
					in: data.details,
					analytics: analytics
				)
				if !matchAccolades.isEmpty {
					accoladesSection(accolades: matchAccolades)
				}
				
				if !stats.highlights.isEmpty {
					highlightsSection(highlights: stats.highlights)
				}
			}
		}
		.withLocalData($focusedSummary, id: focusedPlayer.id)
		.alert("Performance Score", isPresented: $showScoreInfo) {
			Button("OK", role: .cancel) {}
		} message: {
			Text("Combines Fight Impact (ACS, K/D, ADR, First Bloods, Multi-kills, Clutches) and Support (KAST, Assists, Trades, Spike objectives) on a 0–500 curve where 250 is average and 420+ is Masterful.")
		}
	}
	
	// MARK: - Focused Player Card
	
	private var focusedPlayerCard: some View {
		let resolvedTier: Int = {
			if focusedPlayer.competitiveTier >= 3 { return focusedPlayer.competitiveTier }
			let currentAct = seasons?.currentAct()?.id
			if let tier = currentAct.flatMap({ focusedSummary?.competitiveInfo?.bySeason?[$0]?.competitiveTier }), tier >= 3 {
				return tier
			}
			if let latest = focusedSummary?.latestUpdate?.tierAfterUpdate, latest >= 3 {
				return latest
			}
			return focusedPlayer.competitiveTier
		}()
		let tierName = seasons?.currentTierInfo(number: resolvedTier)?.name
			?? (resolvedTier == 0 ? "UNRANKED" : "TIER \(resolvedTier)")
		
		let ownTeam = data.details.teams.first(where: { $0.id == focusedPlayer.teamID })
		let enemyTeam = data.details.teams.first(where: { $0.id != focusedPlayer.teamID })
		let isMatchMVP = analytics.matchMVPID == focusedPlayer.id
		let isTeamMVP = analytics.teamMVPByTeam[focusedPlayer.teamID] == focusedPlayer.id
		
		return HStack(spacing: 12) {
			Group {
				if let agentID = focusedPlayer.agentID {
					AgentImage.icon(
						agentID,
						teamID: focusedPlayer.teamID,
						isOVariant: data.isGauntletOVariant(for: focusedPlayer)
					)
				} else {
					Image(systemName: "person.fill")
						.foregroundStyle(.secondary)
				}
			}
			.frame(width: 44, height: 44)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
			.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			
			VStack(alignment: .leading, spacing: 3) {
				let name = focusedPlayer.resolvedDisplayName(using: resolvedUsers)
				let tag = focusedPlayer.resolvedTagLine(using: resolvedUsers)
				HStack(spacing: 0) {
					Text(name)
						.font(.headline)
						.lineLimit(1)
					if !tag.isEmpty {
						Text("#\(tag)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				
				HStack(spacing: 5) {
					CompetitiveTierImage(tier: resolvedTier, time: data.details.matchInfo.gameStart)
						.frame(width: 16, height: 16)
					Text(tierName.uppercased())
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
			}
			
			Spacer()
			
			VStack(alignment: .trailing, spacing: 2) {
				if let ownTeam, data.details.teams.count == 2 {
					let anyWon = data.details.teams.contains(where: \.won)
					let title = !anyWon ? "DRAW" : (ownTeam.won ? "VICTORY" : "DEFEAT")
					let color: Color = !anyWon ? .secondary : (ownTeam.won ? .green : Color.valorantRed)
					Text(title)
						.font(.caption.weight(.heavy))
						.foregroundStyle(color)
					if let enemyTeam {
						Text("\(ownTeam.roundsWon) – \(enemyTeam.roundsWon)")
							.font(.subheadline.weight(.bold).monospacedDigit())
					}
				} else if let placement = data.placement(of: focusedPlayer.teamID) {
					Text(PlacementFormatter.ordinal(placement).uppercased())
						.font(.caption.weight(.heavy))
						.foregroundStyle(placement == 1 ? .green : .secondary)
				}
				
				if isMatchMVP {
					Label("MATCH MVP", systemImage: "crown.fill")
						.font(.caption2.weight(.bold))
						.foregroundStyle(.yellow)
				} else if isTeamMVP {
					Label("TEAM MVP", systemImage: "crown.fill")
						.font(.caption2.weight(.bold))
						.foregroundStyle(.secondary)
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	// MARK: - Performance Score
	
	private func performanceScoreCard(stats: MatchAnalytics.PlayerMatchAnalytics) -> some View {
		let score = stats.performanceScore
		let pointsToMasterful = max(0, 420 - score)
		
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("PERFORMANCE SCORE")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
				Spacer()
				Button {
					showScoreInfo = true
				} label: {
					Image(systemName: "info.circle")
						.font(.subheadline)
						.foregroundStyle(Color.accentColor)
				}
				.buttonStyle(.plain)
			}
			.padding(.horizontal, 4)
			
			VStack(alignment: .leading, spacing: 14) {
				Text("\(score)")
					.font(.system(size: 36, weight: .bold).monospacedDigit())
				
				PerformanceBellCurveView(score: score)
					.frame(height: 112)
				
				VStack(alignment: .leading, spacing: 5) {
					if pointsToMasterful > 0 {
						Text("\(pointsToMasterful) points to Masterful")
							.font(.caption.weight(.medium))
							.foregroundStyle(.secondary)
					} else {
						Text("Masterful performance!")
							.font(.caption.weight(.semibold))
							.foregroundStyle(Color.valorantBlue)
					}
					
					HStack(spacing: 6) {
						RoundedRectangle(cornerRadius: 2, style: .continuous)
							.fill(Color.valorantBlue)
							.frame(width: 9, height: 9)
						Text("Masterful from 420")
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
				}
				
				Divider().opacity(0.3)
				
				subScoreRow(title: "Fights", value: stats.fightsScore)
				subScoreRow(title: "Support", value: stats.supportScore)
				
				Divider().opacity(0.3)
				
				Button {
					withAnimation(.easeInOut(duration: 0.2)) {
						showBreakdown.toggle()
					}
				} label: {
					HStack {
						Text("Breakdown")
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.primary)
						Spacer()
						Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				
				if showBreakdown {
					VStack(spacing: 8) {
						ForEach(stats.breakdownItems) { item in
							HStack {
								VStack(alignment: .leading, spacing: 1) {
									Text(item.title)
										.font(.caption.weight(.medium))
									Text(item.detail)
										.font(.caption2)
										.foregroundStyle(.secondary)
								}
								Spacer()
								Text(item.value)
									.font(.subheadline.weight(.bold).monospacedDigit())
							}
							.padding(.vertical, 2)
						}
					}
					.padding(.top, 2)
				}
			}
			.padding(16)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	private func subScoreRow(title: String, value: Int) -> some View {
		HStack {
			Text(title)
				.font(.subheadline.weight(.medium))
			Spacer()
			Text("\(value)")
				.font(.headline.bold().monospacedDigit())
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
				} else {
					Image(systemName: "chevron.down")
						.foregroundStyle(Color.valorantRed)
				}
			}
			.font(.caption.bold())
			.frame(width: 18)
		}
	}
	
	// MARK: - VS Lobby Average
	
	private func vsLobbyCard(
		stats: MatchAnalytics.PlayerMatchAnalytics,
		comparison: MatchAnalytics.LobbyComparison
	) -> some View {
		let rows: [(key: String, title: String, mine: Double, avg: Double, formatted: String, avgFormatted: String, deltaFormatted: String, rank: Int)] = [
			(
				"perf", "Performance Score",
				Double(stats.performanceScore), comparison.avgPerformanceScore,
				"\(stats.performanceScore)",
				String(format: "%.0f", comparison.avgPerformanceScore),
				String(format: "%.0f", abs(Double(stats.performanceScore) - comparison.avgPerformanceScore)),
				comparison.perfRank
			),
			(
				"acs", "ACS",
				stats.acs, comparison.avgACS,
				String(format: "%.0f", stats.acs),
				String(format: "%.0f", comparison.avgACS),
				String(format: "%.0f", abs(stats.acs - comparison.avgACS)),
				comparison.acsRank
			),
			(
				"adr", "ADR",
				stats.adr, comparison.avgADR,
				String(format: "%.0f", stats.adr),
				String(format: "%.0f", comparison.avgADR),
				String(format: "%.0f", abs(stats.adr - comparison.avgADR)),
				comparison.adrRank
			),
			(
				"hs", "HS%",
				stats.hsPercent, comparison.avgHSPercent,
				String(format: "%.0f %%", stats.hsPercent),
				String(format: "%.0f %%", comparison.avgHSPercent),
				String(format: "%.0f %%", abs(stats.hsPercent - comparison.avgHSPercent)),
				comparison.hsRank
			),
			(
				"kast", "KAST",
				stats.kastPercent, comparison.avgKASTPercent,
				String(format: "%.0f %%", stats.kastPercent),
				String(format: "%.0f %%", comparison.avgKASTPercent),
				String(format: "%.0f %%", abs(stats.kastPercent - comparison.avgKASTPercent)),
				comparison.kastRank
			),
			(
				"kd", "K/D",
				stats.kd, comparison.avgKD,
				String(format: "%.2f", stats.kd),
				String(format: "%.2f", comparison.avgKD),
				String(format: "%.2f", abs(stats.kd - comparison.avgKD)),
				comparison.kdRank
			),
			(
				"fk", "FK / round",
				stats.fkPerRound, comparison.avgFKPerRound,
				String(format: "%.2f", stats.fkPerRound),
				String(format: "%.2f", comparison.avgFKPerRound),
				String(format: "%.2f", abs(stats.fkPerRound - comparison.avgFKPerRound)),
				comparison.fkRank
			),
		]
		
		return VStack(alignment: .leading, spacing: 8) {
			Text("VS LOBBY AVERAGE (N=\(comparison.otherCount))")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
					let isExpanded = expandedMetrics.contains(row.key)
					let isBetter = row.mine >= row.avg - 0.0001
					
					VStack(spacing: 8) {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								if isExpanded {
									expandedMetrics.remove(row.key)
								} else {
									expandedMetrics.insert(row.key)
								}
							}
						} label: {
							HStack(spacing: 10) {
								Text(row.title)
									.font(.subheadline.weight(.medium))
									.foregroundStyle(.primary)
								
								Spacer()
								
								VStack(alignment: .trailing, spacing: 1) {
									Text(row.formatted)
										.font(.subheadline.weight(.bold).monospacedDigit())
										.foregroundStyle(.primary)
									HStack(spacing: 2) {
										Image(systemName: isBetter ? "arrow.up" : "arrow.down")
										Text(row.deltaFormatted)
									}
									.font(.caption2.weight(.semibold).monospacedDigit())
									.foregroundStyle(isBetter ? Color.green : Color.valorantRed)
								}
								
								Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
									.font(.caption2.weight(.semibold))
									.foregroundStyle(.secondary)
							}
							.padding(.vertical, 10)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						
						if isExpanded {
							VStack(spacing: 6) {
								HStack {
									Text("Lobby average: \(row.avgFormatted)")
									Spacer()
									Text("Rank #\(row.rank) of \(comparison.totalPlayers)")
								}
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
								
								let maxVal = max(0.01, max(row.mine, row.avg) * 1.15)
								GeometryReader { geo in
									ZStack(alignment: .leading) {
										Capsule().fill(Color.secondary.opacity(0.18))
										Capsule()
											.fill(isBetter ? Color.green : Color.valorantRed)
											.frame(width: max(6, geo.size.width * CGFloat(min(1, row.mine / maxVal))))
										Rectangle()
											.fill(Color.white.opacity(0.75))
											.frame(width: 2, height: 10)
											.offset(x: max(0, min(geo.size.width - 2, geo.size.width * CGFloat(row.avg / maxVal))))
									}
								}
								.frame(height: 6)
							}
							.padding(.bottom, 10)
						}
					}
					.padding(.horizontal, 16)
					
					if index < rows.count - 1 {
						Divider()
							.opacity(0.25)
							.padding(.leading, 16)
					}
				}
			}
			.padding(.vertical, 4)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}
	
	// MARK: - Halves
	
	private func halvesSection(stats: MatchAnalytics.PlayerMatchAnalytics) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("HALVES")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			HStack(spacing: 12) {
				halfCard(title: "ATK", half: stats.attackHalf)
				halfCard(title: "DEF", half: stats.defenseHalf)
			}
		}
	}
	
	private func halfCard(title: String, half: MatchAnalytics.HalfStats) -> some View {
		VStack(spacing: 10) {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			
			HStack(alignment: .firstTextBaseline, spacing: 2) {
				Text("\(half.roundsWon)")
					.font(.title.bold().monospacedDigit())
				Text("/\(half.roundsPlayed)")
					.font(.subheadline.monospacedDigit())
					.foregroundStyle(.secondary)
			}
			
			Divider().opacity(0.3)
			
			VStack(spacing: 6) {
				halfStatRow("Kills", half.kills)
				halfStatRow("Deaths", half.deaths)
				halfStatRow("Assists", half.assists)
				halfStatRow("Spike Plants", half.plants)
				halfStatRow("Defuses", half.defuses)
				halfStatRow("First Bloods", half.firstBloods)
				halfStatRow("First Deaths", half.firstDeaths)
			}
		}
		.frame(maxWidth: .infinity)
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func halfStatRow(_ label: String, _ value: Int) -> some View {
		HStack {
			Text(label)
				.font(.caption)
				.foregroundStyle(.secondary)
			Spacer()
			Text("\(value)")
				.font(.caption.weight(.bold).monospacedDigit())
		}
	}
	
	// MARK: - Accolades
	
	private func accoladesSection(accolades: [AccoladeMatchItem]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("ACCOLADES")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			HighlightFlowLayout(spacing: 8) {
				ForEach(accolades) { item in
					AccoladePillView(item: item, showNewBest: false)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
	
	// MARK: - Match Highlights
	
	private func highlightsSection(highlights: [MatchAnalytics.MatchHighlight]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("MATCH HIGHLIGHTS")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			HighlightFlowLayout(spacing: 8) {
				ForEach(highlights) { item in
					let tint: Color = item.isNegative
						? Color.valorantRed
						: Color(red: 0.78, green: 0.67, blue: 0.34)
					Text(item.label)
						.font(.caption2.weight(.bold).monospacedDigit())
						.foregroundStyle(tint)
						.padding(.horizontal, 10)
						.padding(.vertical, 6)
						.background(tint.opacity(0.14), in: Capsule())
						.overlay(
							Capsule().stroke(tint.opacity(0.28), lineWidth: 1)
						)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

// MARK: - Gaussian Bell Curve for Performance Score

private struct PerformanceBellCurveView: View {
	let score: Int
	
	private func gaussianY(_ x: CGFloat) -> CGFloat {
		let mean: CGFloat = 250
		let sigma: CGFloat = 86
		let z = (x - mean) / sigma
		return exp(-0.5 * z * z)
	}
	
	var body: some View {
		GeometryReader { geo in
			let plotHeight = max(24, geo.size.height - 22)
			let width = geo.size.width
			let scoreX = CGFloat(min(500, max(0, score)))
			let px = width * (scoreX / 500)
			let py = plotHeight * (1 - gaussianY(scoreX) * 0.86)
			
			VStack(spacing: 6) {
				ZStack(alignment: .topLeading) {
					// Shaded green performance zone (330...420)
					curveAreaPath(width: width, height: plotHeight, startX: 330, endX: 420)
						.fill(Color.green.opacity(0.45))
					
					// Shaded teal Masterful zone (420...500)
					curveAreaPath(width: width, height: plotHeight, startX: 420, endX: 500)
						.fill(Color.valorantBlue.opacity(0.55))
					
					// Midpoint dashed line at 250
					Path { p in
						let midX = width * 0.5
						let midTop = plotHeight * (1 - gaussianY(250) * 0.86)
						p.move(to: CGPoint(x: midX, y: midTop))
						p.addLine(to: CGPoint(x: midX, y: plotHeight))
					}
					.stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
					
					// Bell curve outline
					curveStrokePath(width: width, height: plotHeight)
						.stroke(Color.secondary.opacity(0.75), lineWidth: 1.8)
					
					// Bottom baseline
					Path { p in
						p.move(to: CGPoint(x: 0, y: plotHeight))
						p.addLine(to: CGPoint(x: width, y: plotHeight))
					}
					.stroke(Color.secondary.opacity(0.3), lineWidth: 1)
					
					// Active player marker stem + dot + score callout
					Path { p in
						p.move(to: CGPoint(x: px, y: py))
						p.addLine(to: CGPoint(x: px, y: plotHeight))
					}
					.stroke(Color.white, lineWidth: 2)
					
					Circle()
						.fill(Color.white)
						.frame(width: 8, height: 8)
						.shadow(color: .black.opacity(0.4), radius: 2)
						.position(x: px, y: py)
					
					Text("\(score)")
						.font(.caption.weight(.bold).monospacedDigit())
						.position(x: min(max(px, 18), width - 18), y: max(8, py - 14))
				}
				.frame(height: plotHeight)
				
				// X-axis labels matching 0, 250, 330, 420, 500 positions
				ZStack(alignment: .leading) {
					axisLabel("0", x: 0, width: width, alignment: .leading)
					axisLabel("250", x: 250, width: width, alignment: .center)
					axisLabel("330", x: 330, width: width, alignment: .center)
					axisLabel("420", x: 420, width: width, alignment: .center)
					axisLabel("500", x: 500, width: width, alignment: .trailing)
				}
				.frame(height: 14)
			}
		}
	}
	
	private func curveStrokePath(width: CGFloat, height: CGFloat) -> Path {
		Path { p in
			let steps = 80
			for i in 0...steps {
				let xVal = CGFloat(i) / CGFloat(steps) * 500
				let px = width * (xVal / 500)
				let py = height * (1 - gaussianY(xVal) * 0.86)
				if i == 0 {
					p.move(to: CGPoint(x: px, y: py))
				} else {
					p.addLine(to: CGPoint(x: px, y: py))
				}
			}
		}
	}
	
	private func curveAreaPath(width: CGFloat, height: CGFloat, startX: CGFloat, endX: CGFloat) -> Path {
		Path { p in
			let steps = 32
			p.move(to: CGPoint(x: width * (startX / 500), y: height))
			for i in 0...steps {
				let xVal = startX + (CGFloat(i) / CGFloat(steps)) * (endX - startX)
				let px = width * (xVal / 500)
				let py = height * (1 - gaussianY(xVal) * 0.86)
				p.addLine(to: CGPoint(x: px, y: py))
			}
			p.addLine(to: CGPoint(x: width * (endX / 500), y: height))
			p.closeSubpath()
		}
	}
	
	@ViewBuilder
	private func axisLabel(_ text: String, x: CGFloat, width: CGFloat, alignment: Alignment) -> some View {
		let posX: CGFloat = {
			if alignment == .leading { return 12 }
			if alignment == .trailing { return width - 14 }
			return width * (x / 500)
		}()
		Text(text)
			.font(.caption2.monospacedDigit())
			.foregroundStyle(.secondary)
			.position(x: posX, y: 7)
	}
}

// MARK: - Wrapping Flow Layout (iOS 16+)

struct HighlightFlowLayout: Layout {
	var spacing: CGFloat = 8
	
	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let maxWidth = proposal.width ?? .infinity
		var x: CGFloat = 0
		var y: CGFloat = 0
		var lineHeight: CGFloat = 0
		
		for sub in subviews {
			let size = sub.sizeThatFits(.unspecified)
			if x > 0 && x + size.width > maxWidth {
				x = 0
				y += lineHeight + spacing
				lineHeight = 0
			}
			lineHeight = max(lineHeight, size.height)
			x += size.width + spacing
		}
		return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + lineHeight)
	}
	
	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var x = bounds.minX
		var y = bounds.minY
		var lineHeight: CGFloat = 0
		
		for sub in subviews {
			let size = sub.sizeThatFits(.unspecified)
			if x > bounds.minX && x + size.width > bounds.maxX {
				x = bounds.minX
				y += lineHeight + spacing
				lineHeight = 0
			}
			sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
			lineHeight = max(lineHeight, size.height)
			x += size.width + spacing
		}
	}
}
