import SwiftUI
import ValorantAPI

struct MatchDuelsTabView: View {
	let data: MatchViewData
	let analytics: MatchAnalytics
	let focusedTeamID: Team.ID
	var resolvedUsers: [Player.ID: User] = [:]
	
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
		NavigationLink {
			DuelHistoryView(data: data, matchup: matchup, resolvedUsers: resolvedUsers)
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
		
		return NavigationLink {
			DuelHistoryView(data: data, matchup: matchup, resolvedUsers: resolvedUsers)
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

private struct DuelHistoryView: View {
	let data: MatchViewData
	let matchup: MatchAnalytics.DuelMatchup
	var resolvedUsers: [Player.ID: User] = [:]
	
	@State private var expandedEventIDs: Set<String> = []
	@Environment(\.assets) private var assets
	
	var body: some View {
		VStack(spacing: 0) {
			pinnedHeader
			
			ScrollView {
				LazyVStack(spacing: 12) {
					if matchup.events.isEmpty {
						Text("No duels occurred between these two players.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity)
							.padding(24)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
					} else {
						ForEach(matchup.events) { event in
							DuelEventCard(
								event: event,
								isExpanded: expandedEventIDs.contains(event.id),
								onToggle: {
									withAnimation(.easeInOut(duration: 0.2)) {
										if expandedEventIDs.contains(event.id) {
											expandedEventIDs.remove(event.id)
										} else {
											expandedEventIDs.insert(event.id)
										}
									}
								}
							)
						}
					}
				}
				.padding(16)
			}
		}
		.background(Color.groupedBackground)
		.navigationTitle("Duel History")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear {
			if matchup.events.count == 1, let only = matchup.events.first {
				expandedEventIDs.insert(only.id)
			}
		}
	}
	
	private var pinnedHeader: some View {
		let allyName = matchup.allyPlayer.resolvedDisplayName(using: resolvedUsers)
		let enemyName = matchup.enemyPlayer.resolvedDisplayName(using: resolvedUsers)
		let allyAgentName = matchup.allyPlayer.agentID.flatMap { assets?.agents[$0]?.displayName }
		let enemyAgentName = matchup.enemyPlayer.agentID.flatMap { assets?.agents[$0]?.displayName }
		let decided = matchup.allyKills + matchup.enemyKills
		let winRatePct = Int(round(matchup.duelWinRate * Double(100)))
		
		return VStack(spacing: 0) {
			HStack(spacing: 12) {
				HStack(spacing: 10) {
					agentPortrait(matchup.allyPlayer, size: 42)
					
					VStack(alignment: .leading, spacing: 2) {
						Text(allyName)
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.primary)
							.lineLimit(1)
						if let allyAgentName {
							Text(allyAgentName)
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				
				Text("VS")
					.font(.subheadline.weight(.bold))
					.foregroundStyle(.secondary)
				
				HStack(spacing: 10) {
					VStack(alignment: .trailing, spacing: 2) {
						Text(enemyName)
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.primary)
							.lineLimit(1)
						if let enemyAgentName {
							Text(enemyAgentName)
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					}
					
					agentPortrait(matchup.enemyPlayer, size: 42)
				}
				.frame(maxWidth: .infinity, alignment: .trailing)
			}
			.padding(.horizontal, 16)
			.padding(.top, 10)
			.padding(.bottom, 12)
			
			HStack(spacing: 0) {
				kpiColumn(title: "Total Duels", value: "\(matchup.events.count)", valueColor: .primary)
				kpiDivider
				kpiColumn(title: "Kills", value: "\(matchup.allyKills)", valueColor: .primary)
				kpiDivider
				kpiColumn(title: "Deaths", value: "\(matchup.enemyKills)", valueColor: .primary)
				kpiDivider
				kpiColumn(title: "Assists", value: "\(matchup.allyAssists)", valueColor: .primary)
				kpiDivider
				kpiColumn(
					title: "Win Rate",
					value: decided > 0 ? "\(winRatePct) %" : "—",
					valueColor: decided > 0 ? (winRatePct >= 50 ? .green : Color.valorantRed) : .secondary
				)
			}
			.padding(.bottom, 12)
			
			Divider().opacity(0.25)
		}
		.background(Color.secondaryGroupedBackground)
	}
	
	private var kpiDivider: some View {
		Divider()
			.frame(height: 28)
			.opacity(0.28)
	}
	
	private func kpiColumn(title: String, value: String, valueColor: Color) -> some View {
		VStack(spacing: 4) {
			Text(title)
				.font(.caption2)
				.foregroundStyle(.secondary)
				.lineLimit(1)
			Text(value)
				.font(.headline.weight(.bold).monospacedDigit())
				.foregroundStyle(valueColor)
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity)
	}
	
	@ViewBuilder
	private func agentPortrait(_ player: Player, size: CGFloat) -> some View {
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
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
		.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
	}
}

private struct DuelEventCard: View {
	let event: MatchAnalytics.DuelKillEvent
	let isExpanded: Bool
	let onToggle: () -> Void
	
	@Environment(\.assets) private var assets
	
	private var outcomeColor: Color {
		switch event.outcome {
		case .kill: return .green
		case .death: return Color.valorantRed
		case .assist: return Color.valorantBlue
		}
	}
	
	private var outcomeSymbol: String {
		switch event.outcome {
		case .kill: return "checkmark.circle.fill"
		case .death: return "xmark.circle.fill"
		case .assist: return "plus.circle.fill"
		}
	}
	
	private var outcomeLabel: String {
		switch event.outcome {
		case .kill: return "Kill"
		case .death: return "Death"
		case .assist: return "Assist"
		}
	}
	
	var body: some View {
		VStack(spacing: 0) {
			Button(action: onToggle) {
				HStack(alignment: .center, spacing: 10) {
					VStack(alignment: .leading, spacing: 4) {
						Text("ROUND")
							.font(.caption2.weight(.semibold))
							.foregroundStyle(.secondary)
						HStack(spacing: 5) {
							Text("\(event.roundNumber + 1)")
								.font(.subheadline.weight(.bold).monospacedDigit())
								.foregroundStyle(.primary)
							Image(systemName: outcomeSymbol)
								.font(.caption.weight(.bold))
								.foregroundStyle(outcomeColor)
						}
					}
					.frame(minWidth: 66, alignment: .leading)
					
					VStack(alignment: .center, spacing: 4) {
						Text("WEAPON")
							.font(.caption2.weight(.semibold))
							.foregroundStyle(.secondary)
						weaponLabel(weaponID: event.allyWeaponID, fallbackName: event.allyWeaponFallbackName)
					}
					.frame(maxWidth: .infinity)
					
					VStack(alignment: .trailing, spacing: 4) {
						Text("DAMAGE")
							.font(.caption2.weight(.semibold))
							.foregroundStyle(.secondary)
						HStack(spacing: 4) {
							if event.isFirstBlood {
								Image(systemName: "bolt.fill")
									.font(.caption2)
									.foregroundStyle(.orange)
							}
							Text("\(event.damageDealt)")
								.font(.subheadline.weight(.bold).monospacedDigit())
								.foregroundStyle(outcomeColor)
						}
					}
					.frame(minWidth: 66, alignment: .trailing)
					
					Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
						.padding(.leading, 4)
				}
				.padding(14)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			
			if isExpanded {
				expandedBreakdown
					.padding(.horizontal, 12)
					.padding(.bottom, 12)
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private var expandedBreakdown: some View {
		VStack(spacing: 0) {
			breakdownRow(title: "OUTCOME") {
				HStack(spacing: 6) {
					Text(outcomeLabel)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(outcomeColor)
					Image(systemName: outcomeSymbol)
						.font(.subheadline)
						.foregroundStyle(outcomeColor)
				}
			}
			
			rowDivider
			
			breakdownRow(title: "YOUR WEAPON") {
				HStack(spacing: 6) {
					weaponLabel(weaponID: event.allyWeaponID, fallbackName: event.allyWeaponFallbackName)
					ValorantShieldBadge(armorID: event.allyArmorID)
				}
			}
			
			rowDivider
			
			breakdownRow(title: "DAMAGE DEALT") {
				HStack(spacing: 10) {
					HitBodySilhouetteView(
						headshots: event.dealtHeadshots,
						bodyshots: event.dealtBodyshots,
						legshots: event.dealtLegshots
					)
					Text("\(event.damageDealt)")
						.font(.subheadline.weight(.bold).monospacedDigit())
						.foregroundStyle(event.damageDealt > 0 ? Color.green : .secondary)
						.frame(minWidth: 34, alignment: .trailing)
				}
			}
			
			rowDivider
			
			breakdownRow(title: "RANGE") {
				Text(event.rangeMeters.map { String(format: "%.1fm", $0) } ?? "—")
					.font(.subheadline.weight(.semibold).monospacedDigit())
					.foregroundStyle(event.rangeMeters != nil ? .primary : .secondary)
			}
			
			rowDivider
			
			breakdownRow(title: "DAMAGE RECEIVED") {
				HStack(spacing: 10) {
					HitBodySilhouetteView(
						headshots: event.receivedHeadshots,
						bodyshots: event.receivedBodyshots,
						legshots: event.receivedLegshots
					)
					Text("\(event.damageReceived)")
						.font(.subheadline.weight(.bold).monospacedDigit())
						.foregroundStyle(event.damageReceived > 0 ? Color.valorantRed : .secondary)
						.frame(minWidth: 34, alignment: .trailing)
				}
			}
			
			rowDivider
			
			breakdownRow(title: "OPPONENT WEAPON") {
				HStack(spacing: 6) {
					weaponLabel(weaponID: event.enemyWeaponID, fallbackName: event.enemyWeaponFallbackName)
					ValorantShieldBadge(armorID: event.enemyArmorID)
				}
			}
			
			rowDivider
			
			breakdownRow(title: "ROUND") {
				HStack(spacing: 6) {
					Text("\(event.roundNumber + 1)")
						.font(.subheadline.weight(.bold).monospacedDigit())
						.foregroundStyle(.primary)
					Image(systemName: event.allyWonRound ? "checkmark.circle.fill" : "xmark.circle.fill")
						.font(.subheadline)
						.foregroundStyle(event.allyWonRound ? Color.green : Color.valorantRed)
				}
			}
		}
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	
	private var rowDivider: some View {
		Divider()
			.opacity(0.2)
			.padding(.horizontal, 14)
	}
	
	private func breakdownRow<Trailing: View>(title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
		HStack(spacing: 10) {
			Text(title)
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
			Spacer(minLength: 8)
			trailing()
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
	}
	
	@ViewBuilder
	private func weaponLabel(weaponID: Weapon.ID?, fallbackName: String?) -> some View {
		if let weaponID {
			let name = assets?.weapons[weaponID]?.displayName
				?? (weaponID == .melee ? "Melee" : fallbackName)
				?? "Weapon"
			HStack(spacing: 6) {
				WeaponImage.killStreamIcon(weaponID)
					.scaledToFit()
					.frame(maxWidth: 44, maxHeight: 14)
					.foregroundStyle(.primary)
				Text(name)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(1)
			}
		} else if let fallbackName, !fallbackName.isEmpty {
			Text(fallbackName)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.primary)
				.lineLimit(1)
		} else {
			Text("—")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
		}
	}
}

private struct HitBodySilhouetteView: View {
	let headshots: Int
	let bodyshots: Int
	let legshots: Int
	
	var body: some View {
		HStack(spacing: 6) {
			VStack(alignment: .trailing, spacing: 2) {
				zoneCount(headshots)
				zoneCount(bodyshots)
				zoneCount(legshots)
			}
			
			VStack(spacing: 1.5) {
				Circle()
					.fill(headshots > 0 ? Color.primary : Color.secondary.opacity(0.28))
					.frame(width: 5.5, height: 5.5)
				
				BodyTorsoShape()
					.fill(bodyshots > 0 ? Color.primary : Color.secondary.opacity(0.28))
					.frame(width: 14, height: 13)
				
				BodyLegsShape()
					.fill(legshots > 0 ? Color.primary : Color.secondary.opacity(0.28))
					.frame(width: 10, height: 13)
			}
		}
	}
	
	private func zoneCount(_ count: Int) -> some View {
		Text("\(count)")
			.font(.system(size: 10, weight: .bold).monospacedDigit())
			.foregroundStyle(count > 0 ? Color.primary : Color.secondary.opacity(0.4))
	}
}

private struct BodyTorsoShape: Shape {
	func path(in rect: CGRect) -> Path {
		var p = Path()
		let w = rect.width
		let h = rect.height
		// Shoulders & arms + tapered torso
		p.move(to: CGPoint(x: w * 0.22, y: h * 0.04))
		p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.04))
		p.addQuadCurve(to: CGPoint(x: w * 0.98, y: h * 0.28), control: CGPoint(x: w * 0.94, y: h * 0.08))
		p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.78))
		p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.78))
		p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.36))
		p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.98))
		p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.98))
		p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.36))
		p.addLine(to: CGPoint(x: w * 0.24, y: h * 0.78))
		p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.78))
		p.addLine(to: CGPoint(x: w * 0.02, y: h * 0.28))
		p.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.04), control: CGPoint(x: w * 0.06, y: h * 0.08))
		p.closeSubpath()
		return p
	}
}

private struct BodyLegsShape: Shape {
	func path(in rect: CGRect) -> Path {
		var p = Path()
		let w = rect.width
		let h = rect.height
		// Left leg
		p.move(to: CGPoint(x: w * 0.14, y: 0))
		p.addLine(to: CGPoint(x: w * 0.44, y: 0))
		p.addLine(to: CGPoint(x: w * 0.40, y: h))
		p.addLine(to: CGPoint(x: w * 0.18, y: h))
		p.closeSubpath()
		// Right leg
		p.move(to: CGPoint(x: w * 0.56, y: 0))
		p.addLine(to: CGPoint(x: w * 0.86, y: 0))
		p.addLine(to: CGPoint(x: w * 0.82, y: h))
		p.addLine(to: CGPoint(x: w * 0.60, y: h))
		p.closeSubpath()
		return p
	}
}

private struct ValorantShieldBadge: View {
	let armorID: Armor.ID?
	
	private enum ShieldKind {
		case heavy, light, regen
	}
	
	private var kind: ShieldKind? {
		guard let raw = armorID?.description.lowercased() else { return nil }
		switch raw {
		case "822bcab2-40a2-324e-c137-e09195ad7692": return .heavy
		case "4dec83d5-4902-9ab3-bed6-a7a390761157": return .light
		case "b1b9086d-41bd-a516-5d29-e3b34a6f1644": return .regen
		default: return nil
		}
	}
	
	var body: some View {
		switch kind {
		case .heavy:
			ZStack {
				ValorantShieldShape()
					.stroke(Color.primary, lineWidth: 1.4)
				ValorantShieldShape()
					.fill(Color.primary)
					.scaleEffect(0.62)
			}
			.frame(width: 14, height: 16)
		case .light:
			ZStack {
				ValorantShieldShape()
					.stroke(Color.primary.opacity(0.8), lineWidth: 1.4)
				ValorantShieldShape()
					.fill(Color.primary.opacity(0.38))
					.scaleEffect(0.62)
			}
			.frame(width: 14, height: 16)
		case .regen:
			ZStack {
				ValorantShieldShape()
					.stroke(Color.valorantBlue, lineWidth: 1.4)
				Image(systemName: "plus")
					.font(.system(size: 7, weight: .black))
					.foregroundStyle(Color.valorantBlue)
			}
			.frame(width: 14, height: 16)
		case nil:
			EmptyView()
		}
	}
}

private struct ValorantShieldShape: Shape {
	func path(in rect: CGRect) -> Path {
		var p = Path()
		let w = rect.width
		let h = rect.height
		p.move(to: CGPoint(x: w * 0.5, y: 0))
		p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.18))
		p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.68))
		p.addLine(to: CGPoint(x: w * 0.5, y: h))
		p.addLine(to: CGPoint(x: w * 0.12, y: h * 0.68))
		p.addLine(to: CGPoint(x: w * 0.04, y: h * 0.18))
		p.closeSubpath()
		return p
	}
}
