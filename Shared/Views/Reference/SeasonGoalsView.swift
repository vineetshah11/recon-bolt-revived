import SwiftUI
import ValorantAPI

struct SeasonGoalsView: View {
	@EnvironmentObject private var goalStore: SeasonGoalStore
	@EnvironmentObject private var accountManager: AccountManager
	@Environment(\.seasons) private var seasons
	@Environment(\.assets) private var assets
	
	@LocalData var summary: CareerSummary?
	@LocalData var matchList: MatchList?
	
	@State private var showingPickerSheet = false
	@State private var showingRemoveAlert = false
	@State private var showAllDivisions = false
	
	private var userID: User.ID? {
		accountManager.activeAccount?.id
	}
	
	var body: some View {
		let currentAct = seasons?.currentAct()
		let activeGoal = userID.flatMap { goalStore.goal(for: $0, actID: currentAct?.id) }
		
		ScrollView {
			VStack(spacing: 14) {
				if let userID, let activeGoal {
					let trajectory = SeasonGoalStore.compute(
						goal: activeGoal,
						summary: summary,
						matchList: matchList,
						currentAct: currentAct,
						seasons: seasons
					)
					
					if trajectory.isPreviousAct {
						previousActBanner(currentAct: currentAct)
					}
					
					if trajectory.gamesNeededForRating > 0 && trajectory.currentTier < 3 {
						placementsNoticeCard(gamesNeeded: trajectory.gamesNeededForRating)
					}
					
					heroCard(goal: activeGoal, trajectory: trajectory, currentAct: currentAct)
					statsSummaryCard(goal: activeGoal, trajectory: trajectory)
					climbCard(trajectory: trajectory, currentAct: currentAct)
					projectionsCard(trajectory: trajectory, currentAct: currentAct)
					
					if !trajectory.recentChanges.isEmpty {
						recentHistoryCard(trajectory: trajectory)
					}
					
					let lowestImm = SeasonGoalStore.lowestImmortalTier(in: seasons?.currentTiers())
					if activeGoal.targetTier > lowestImm {
						Text("Immortal+ milestones use standard 100 / 200 RR steps and a 450 RR baseline for Radiant.")
							.font(.caption)
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 4)
					}
				} else if let userID {
					let rank = SeasonGoalStore.currentRank(summary: summary, matchList: matchList, act: currentAct)
					SeasonGoalPickerContent(
						accountID: userID,
						currentAct: currentAct,
						currentTier: rank.tier,
						currentRR: rank.rr,
						initialTargetTier: defaultTargetTier(above: rank.tier),
						isSheet: false,
						onSaved: {}
					)
				} else {
					signedOutCard
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Season Goals")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if let userID, let activeGoal {
				ToolbarItem(placement: .primaryAction) {
					Menu {
						Button {
							showingPickerSheet = true
						} label: {
							Label("Change Target Rank", systemImage: "arrow.triangle.2.circlepath")
						}
						
						Button {
							goalStore.toggleShowOnProfile(id: activeGoal.id)
						} label: {
							if activeGoal.showsOnProfile {
								Label("Shown on Profile", systemImage: "checkmark")
							} else {
								Label("Show on Profile", systemImage: "person.crop.square")
							}
						}
						
						Divider()
						
						Button(role: .destructive) {
							showingRemoveAlert = true
						} label: {
							Label("Remove Goal", systemImage: "trash")
						}
					} label: {
						Image(systemName: "ellipsis.circle")
					}
				}
				
				ToolbarItem(placement: .primaryAction) {
					EmptyView().id(userID)
				}
			}
		}
		.sheet(isPresented: $showingPickerSheet) {
			if let userID {
				let rank = SeasonGoalStore.currentRank(summary: summary, matchList: matchList, act: currentAct)
				NavigationView {
					ScrollView {
						SeasonGoalPickerContent(
							accountID: userID,
							currentAct: currentAct,
							currentTier: rank.tier,
							currentRR: rank.rr,
							initialTargetTier: activeGoal?.targetTier ?? defaultTargetTier(above: rank.tier),
							isSheet: true,
							onSaved: { showingPickerSheet = false }
						)
						.padding(16)
					}
					.background(Color.groupedBackground)
					.navigationTitle("Edit Season Goal")
					.navigationBarTitleDisplayMode(.inline)
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button("Cancel") { showingPickerSheet = false }
						}
					}
				}
			}
		}
		.alert("Remove Season Goal?", isPresented: $showingRemoveAlert) {
			Button("Remove", role: .destructive) {
				if let id = activeGoal?.id {
					goalStore.removeGoal(id: id)
				}
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Your saved progress baseline for this act will be cleared.")
		}
		.modifier(GoalLocalDataBinder(userID: userID, summary: $summary, matchList: $matchList))
	}
	
	private func defaultTargetTier(above currentTier: Int) -> Int {
		let sorted = (seasons?.currentTiers()?.tiers.values.filter { $0.number >= 3 }.map(\.number).sorted()) ?? Array(3...27)
		if let next = sorted.first(where: { $0 >= max(15, currentTier + 2) }) {
			return next
		}
		return sorted.last ?? 24
	}
	
	private func tierColor(for tier: Int) -> Color {
		let info = seasons?.currentTierInfo(number: tier)
		return info?.backgroundColor?.opaque() ?? info?.color?.opaque() ?? Color.accentColor
	}
	
	private var signedOutCard: some View {
		VStack(spacing: 12) {
			Image(systemName: "person.crop.circle.badge.exclamationmark")
				.font(.largeTitle)
				.foregroundStyle(Color.accentColor)
			Text("Not Signed In")
				.font(.headline)
			Text("Sign in to set a rank goal for the current act.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(24)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func previousActBanner(currentAct: Act?) -> some View {
		HStack(spacing: 12) {
			Image(systemName: "clock.arrow.circlepath")
				.font(.title3)
				.foregroundStyle(.orange)
			VStack(alignment: .leading, spacing: 2) {
				Text("Goal From Previous Act")
					.font(.subheadline.weight(.semibold))
				Text("Update your goal for \(currentAct?.shortDisplayLabel ?? "the current act").")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Button("Update") {
				showingPickerSheet = true
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.small)
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func placementsNoticeCard(gamesNeeded: Int) -> some View {
		HStack(spacing: 10) {
			Image(systemName: "info.circle.fill")
				.foregroundStyle(Color.accentColor)
			Text("Complete \(gamesNeeded) more placement \(gamesNeeded == 1 ? "match" : "matches") to lock your starting rank for this act.")
				.font(.caption)
				.foregroundStyle(.secondary)
			Spacer()
		}
		.padding(12)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	
	private func heroCard(goal: SeasonGoal, trajectory: SeasonGoalTrajectory, currentAct: Act?) -> some View {
		let rankColor = tierColor(for: goal.targetTier)
		let actTitle = currentAct?.shortDisplayLabel ?? "CURRENT ACT"
		let endText = currentAct?.timeSpan.end.formatted(.dateTime.day().month(.abbreviated)) ?? "—"
		let setText = goal.createdAt.formatted(.dateTime.day().month(.abbreviated))
		
		return VStack(spacing: 0) {
			HStack(alignment: .center, spacing: 14) {
				VStack(alignment: .leading, spacing: 6) {
					Text("GOAL · \(actTitle)")
						.font(.caption.weight(.bold))
						.foregroundStyle(.white.opacity(0.75))
					
					Text(trajectory.targetTierName.uppercased())
						.font(.title.weight(.heavy))
						.foregroundStyle(.white)
						.lineLimit(1)
						.minimumScaleFactor(0.75)
					
					HStack(spacing: 6) {
						Image(systemName: "hourglass")
							.font(.subheadline.weight(.semibold))
						Text("\(trajectory.daysLeft) \(trajectory.daysLeft == 1 ? "day" : "days") left")
							.font(.headline.weight(.bold).monospacedDigit())
					}
					.foregroundStyle(.white)
					
					Text("Act ends \(endText) · Goal set \(setText)")
						.font(.caption)
						.foregroundStyle(.white.opacity(0.75))
				}
				
				Spacer(minLength: 8)
				
				SeasonGoalRingIcon(
					tier: goal.targetTier,
					progress: trajectory.progress,
					ringColor: .white,
					size: 84
				)
			}
			.padding(18)
			
			statusStrip(trajectory: trajectory)
		}
		.background(
			LinearGradient(
				colors: [
					rankColor.opacity(0.55),
					rankColor.opacity(0.28),
					Color.secondaryGroupedBackground,
				],
				startPoint: .topTrailing,
				endPoint: .bottomLeading
			)
		)
		.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.stroke(rankColor.opacity(0.35), lineWidth: 1)
		)
	}
	
	@ViewBuilder
	private func statusStrip(trajectory: SeasonGoalTrajectory) -> some View {
		let info: (icon: String, color: Color, title: String, subtitle: String) = {
			switch trajectory.status {
			case .reached:
				return (
					"checkmark.seal.fill",
					.green,
					"Goal Reached",
					"You hit \(trajectory.targetTierName)!"
				)
			case .onTrack(let date):
				let d = date.formatted(.dateTime.day().month(.abbreviated))
				return (
					"calendar.badge.checkmark",
					.green,
					"On Track",
					"At this pace you'd reach it around \(d)."
				)
			case .behindPace(let date):
				let sub: String = {
					if let date {
						return "At this pace you'd reach it around \(date.formatted(.dateTime.day().month(.abbreviated)))."
					}
					return "Pick up your pace slightly to hit the goal before the act ends."
				}()
				return ("exclamationmark.triangle.fill", .orange, "Behind Pace", sub)
			case .negativePace:
				return (
					"exclamationmark.triangle.fill",
					.orange,
					"Behind Pace",
					"You're not gaining RR on average right now. Turn the trend around and the projection will update."
				)
			case .needsMoreData(let played, let needed):
				return (
					"chart.line.uptrend.xyaxis",
					.secondary,
					"Needs More Matches",
					"Play \(max(1, needed - played)) more ranked \(needed - played == 1 ? "match" : "matches") this act to project a finish date."
				)
			}
		}()
		
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: info.icon)
				.font(.body.weight(.semibold))
				.foregroundStyle(info.color)
				.padding(.top, 1)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(info.title)
					.font(.subheadline.weight(.bold))
					.foregroundStyle(info.color)
				Text(info.subtitle)
					.font(.caption)
					.foregroundStyle(.white.opacity(0.85))
			}
			Spacer()
		}
		.padding(.horizontal, 18)
		.padding(.vertical, 12)
		.background(Color.black.opacity(0.28))
	}
	
	private func statsSummaryCard(goal: SeasonGoal, trajectory: SeasonGoalTrajectory) -> some View {
		let setShort = goal.createdAt.formatted(.dateTime.day().month(.abbreviated))
		let pct = Int(round(trajectory.progress * Double(100)))
		let sinceText = trajectory.rrSinceSet >= 0 ? "+\(trajectory.rrSinceSet)" : "\(trajectory.rrSinceSet)"
		
		return HStack(spacing: 0) {
			statColumn(title: "To Go", value: "\(trajectory.rrToGo)", subtitle: "RR", valueColor: .primary)
			Divider().frame(height: 46).opacity(0.35)
			statColumn(title: "Progress", value: "\(pct) %", subtitle: "since \(setShort)", valueColor: .primary)
			Divider().frame(height: 46).opacity(0.35)
			statColumn(
				title: "Since Set",
				value: sinceText,
				subtitle: "RR",
				valueColor: trajectory.rrSinceSet > 0 ? .green : trajectory.rrSinceSet < 0 ? .red : .primary
			)
		}
		.padding(.vertical, 14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func statColumn(title: String, value: String, subtitle: String, valueColor: Color) -> some View {
		VStack(spacing: 4) {
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.title2.bold().monospacedDigit())
				.foregroundStyle(valueColor)
			Text(subtitle)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
	}
	
	private func climbCard(trajectory: SeasonGoalTrajectory, currentAct: Act?) -> some View {
		let rankColor = tierColor(for: trajectory.targetTier)
		
		return VStack(alignment: .leading, spacing: 14) {
			HStack {
				Text("The Climb")
					.font(.headline)
				Spacer()
				Text("\(trajectory.currentTierName.uppercased())  \(trajectory.currentRR) RR")
					.font(.subheadline.weight(.semibold).monospacedDigit())
					.foregroundStyle(.secondary)
			}
			
			if !trajectory.divisions.isEmpty {
				HStack(spacing: 8) {
					CompetitiveTierImage(tier: trajectory.startDivisionTier, act: currentAct)
						.frame(width: 24, height: 24)
					
					HStack(spacing: 4) {
						ForEach(trajectory.divisions) { step in
							GeometryReader { geo in
								ZStack(alignment: .leading) {
									Capsule()
										.fill(Color.secondary.opacity(0.22))
									if step.fillFraction > 0 {
										Capsule()
											.fill(rankColor)
											.frame(width: max(6, geo.size.width * CGFloat(step.fillFraction)))
									}
								}
							}
							.frame(height: 7)
						}
					}
					
					CompetitiveTierImage(tier: trajectory.targetTier, act: currentAct)
						.frame(width: 24, height: 24)
				}
			}
			
			if let next = trajectory.nextDivision {
				HStack(spacing: 12) {
					CompetitiveTierImage(tier: next.tier, act: currentAct)
						.frame(width: 32, height: 32)
					
					VStack(alignment: .leading, spacing: 2) {
						Text("NEXT DIVISION")
							.font(.caption2.weight(.semibold))
							.foregroundStyle(.secondary)
						Text(next.name.uppercased())
							.font(.subheadline.weight(.bold))
						Text("\(next.rrToGo) RR to go")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					}
					
					Spacer()
					
					if trajectory.divisions.count > 1 {
						Button {
							withAnimation(.easeInOut(duration: 0.2)) {
								showAllDivisions.toggle()
							}
						} label: {
							HStack(spacing: 4) {
								Text(showAllDivisions ? "Hide" : "All")
								Image(systemName: showAllDivisions ? "chevron.up" : "chevron.down")
							}
							.font(.caption.weight(.semibold))
							.foregroundStyle(Color.accentColor)
						}
						.buttonStyle(.plain)
					}
				}
			}
			
			if showAllDivisions && !trajectory.divisions.isEmpty {
				Divider().opacity(0.35)
				VStack(spacing: 8) {
					ForEach(trajectory.divisions) { step in
						HStack(spacing: 10) {
							CompetitiveTierImage(tier: step.tier, act: currentAct)
								.frame(width: 24, height: 24)
							Text(step.name)
								.font(.subheadline.weight(.medium))
							Spacer()
							if step.isCompleted {
								Label("Reached", systemImage: "checkmark.circle.fill")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.green)
							} else {
								Text("\(step.rrToReach) RR to go")
									.font(.caption.monospacedDigit())
									.foregroundStyle(.secondary)
							}
						}
					}
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func projectionsCard(trajectory: SeasonGoalTrajectory, currentAct: Act?) -> some View {
		let avgText = trajectory.avgRRPerMatch >= 0
			? String(format: "+%.1f RR", trajectory.avgRRPerMatch)
			: String(format: "%.1f RR", trajectory.avgRRPerMatch)
		let wrText = String(format: "%.0f%% (%dW–%dL)", trajectory.winRate * Double(100), trajectory.wins, trajectory.losses)
		let gainLossText = String(format: "+%.0f / -%.0f RR", trajectory.avgGain, trajectory.avgLoss)
		let matchesLeftText = trajectory.matchesLeft.map { "\($0)" } ?? "—"
		let reqPaceText = trajectory.requiredMatchesPerDay.map { String(format: "%.1f / day", $0) } ?? "—"
		let reqWRText = trajectory.requiredWinRate.map { String(format: "%.0f%%", $0 * Double(100)) } ?? "—"
		
		return VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Trajectory & Pace")
					.font(.headline)
				Spacer()
				Text("\(trajectory.matchesPlayed) ranked")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}
			
			LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
				metricTile(
					title: "Avg RR / Match",
					value: trajectory.matchesPlayed > 0 ? avgText : "—",
					valueColor: trajectory.avgRRPerMatch > 0 ? .green : trajectory.avgRRPerMatch < 0 ? .red : .primary
				)
				metricTile(
					title: "Win Rate",
					value: trajectory.wins + trajectory.losses > 0 ? wrText : "—"
				)
				metricTile(
					title: "Avg Win / Loss",
					value: trajectory.wins + trajectory.losses > 0 ? gainLossText : "—"
				)
				metricTile(
					title: "Est. Matches Left",
					value: matchesLeftText
				)
				metricTile(
					title: "Required Pace",
					value: reqPaceText,
					subtitle: trajectory.matchesPlayed > 0 ? String(format: "Playing %.1f / day", trajectory.matchesPerDay) : nil
				)
				metricTile(
					title: "Required Win Rate",
					value: reqWRText
				)
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func metricTile(title: String, value: String, subtitle: String? = nil, valueColor: Color = .primary) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.subheadline.bold().monospacedDigit())
				.foregroundStyle(valueColor)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
			if let subtitle {
				Text(subtitle)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	
	private func recentHistoryCard(trajectory: SeasonGoalTrajectory) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Text("Recent RR History")
					.font(.headline)
				Spacer()
				if trajectory.currentStreak != 0 {
					let isWin = trajectory.currentStreak > 0
					let label = "\(abs(trajectory.currentStreak))\(isWin ? "W" : "L") Streak"
					Text(label)
						.font(.caption.bold())
						.foregroundStyle(isWin ? Color.green : Color.red)
						.padding(.horizontal, 8)
						.padding(.vertical, 3)
						.background((isWin ? Color.green : Color.red).opacity(0.15), in: Capsule())
				}
			}
			
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					ForEach(Array(trajectory.recentChanges.enumerated()), id: \.offset) { _, delta in
						Text(delta > 0 ? "+\(delta)" : "\(delta)")
							.font(.caption.bold().monospacedDigit())
							.foregroundStyle(delta > 0 ? Color.green : delta < 0 ? Color.red : .secondary)
							.padding(.horizontal, 10)
							.padding(.vertical, 6)
							.background(
								(delta > 0 ? Color.green : delta < 0 ? Color.red : Color.secondary).opacity(0.14),
								in: Capsule()
							)
					}
				}
			}
		}
		.padding(16)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
}

struct SeasonGoalRingIcon: View {
	var tier: Int
	var progress: Double
	var ringColor: Color = .white
	var size: CGFloat = 84
	
	@Environment(\.seasons) private var seasons
	
	var body: some View {
		let clamped = min(1, max(0, CGFloat(progress)))
		let lineWidth = max(4, size * 0.08)
		
		ZStack {
			Circle()
				.stroke(ringColor.opacity(0.22), lineWidth: lineWidth)
			
			Circle()
				.trim(from: 0, to: clamped)
				.stroke(
					ringColor,
					style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
				)
				.rotationEffect(.degrees(-90))
			
			CompetitiveTierImage(tier: tier, act: seasons?.currentAct())
				.padding(size * 0.2)
		}
		.frame(width: size, height: size)
	}
}

/// Compact Season Goal card rendered on Career Profile when `showsOnProfile == true`.
struct SeasonGoalProgressModule: View {
	var goal: SeasonGoal
	var trajectory: SeasonGoalTrajectory
	var currentAct: Act?
	
	var body: some View {
		NavigationLink {
			SeasonGoalsView()
		} label: {
			HStack(spacing: 12) {
				SeasonGoalRingIcon(
					tier: goal.targetTier,
					progress: trajectory.progress,
					ringColor: .accentColor,
					size: 46
				)
				
				VStack(alignment: .leading, spacing: 3) {
					HStack(spacing: 6) {
						Text("Season Goal")
							.font(.subheadline.weight(.semibold))
						Text("· \(trajectory.targetTierName)")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(Color.accentColor)
					}
					
					Text(subtitleText)
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		}
		.buttonStyle(.plain)
	}
	
	private var subtitleText: String {
		let pct = Int(round(trajectory.progress * Double(100)))
		switch trajectory.status {
		case .reached:
			return "Goal reached! (\(pct)%)"
		case .onTrack:
			return "\(trajectory.rrToGo) RR to go · \(pct)% · On Track"
		case .behindPace, .negativePace:
			return "\(trajectory.rrToGo) RR to go · \(pct)% · Behind Pace"
		case .needsMoreData:
			return "\(trajectory.rrToGo) RR to go · \(pct)%"
		}
	}
}

private struct SeasonGoalPickerContent: View {
	var accountID: User.ID
	var currentAct: Act?
	var currentTier: Int
	var currentRR: Int
	var initialTargetTier: Int
	var isSheet: Bool
	var onSaved: () -> Void
	
	@EnvironmentObject private var goalStore: SeasonGoalStore
	@Environment(\.seasons) private var seasons
	@State private var selectedTier: Int = 18
	@State private var initializedSelection = false
	
	var body: some View {
		let tiersCollection = seasons?.currentTiers()
		let allTiers = (tiersCollection?.tiers.values
			.filter { $0.number >= 3 }
			.sorted { $0.number < $1.number }) ?? []
		let candidateTiers = allTiers.filter { $0.number > currentTier }
		let displayTiers = candidateTiers.isEmpty ? allTiers : candidateTiers
		
		VStack(alignment: .leading, spacing: 16) {
			if !isSheet {
				VStack(alignment: .leading, spacing: 8) {
					if let currentAct {
						Text(currentAct.shortDisplayLabel)
							.font(.caption.weight(.bold))
							.foregroundStyle(Color.accentColor)
					}
					Text("Set a Season Goal")
						.font(.title2.bold())
					Text("Pick the rank you want to reach before the act ends. Recon Bolt projects whether you're on track from your ranked history.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
			}
			
			// Current Rank pill
			HStack(spacing: 12) {
				CompetitiveTierImage(tier: currentTier, act: currentAct)
					.frame(width: 36, height: 36)
				VStack(alignment: .leading, spacing: 2) {
					Text("CURRENT RANK")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(.secondary)
					let rankName = tiersCollection?.tier(currentTier)?.name ?? (currentTier == 0 ? "Unranked" : "Tier \(currentTier)")
					Text(currentTier >= 3 ? "\(rankName) · \(currentRR) RR" : rankName)
						.font(.subheadline.weight(.bold))
				}
				Spacer()
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			
			Text("TARGET RANK")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			if displayTiers.isEmpty {
				Text("Season rank tiers are still loading.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.padding()
			} else {
				LazyVStack(spacing: 8) {
					ForEach(displayTiers.reversed(), id: \.number) { tier in
						let isSelected = selectedTier == tier.number
						let curElo = SeasonGoalStore.elo(tier: currentTier, rr: currentRR, tiers: tiersCollection)
						let tgtElo = SeasonGoalStore.targetThresholdElo(for: tier.number, tiers: tiersCollection)
						let needed = max(0, tgtElo - curElo)
						
						Button {
							selectedTier = tier.number
						} label: {
							HStack(spacing: 12) {
								CompetitiveTierImage(tierInfo: tier)
									.frame(width: 34, height: 34)
								
								VStack(alignment: .leading, spacing: 2) {
									Text(tier.name)
										.font(.body.weight(.semibold))
										.foregroundStyle(.primary)
									if currentTier >= 3 && needed > 0 {
										Text("+\(needed) RR")
											.font(.caption.monospacedDigit())
											.foregroundStyle(.secondary)
									}
								}
								
								Spacer()
								
								Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
									.font(.title3)
									.foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
							}
							.padding(.horizontal, 14)
							.padding(.vertical, 10)
							.background(
								isSelected ? Color.accentColor.opacity(0.14) : Color.secondaryGroupedBackground,
								in: RoundedRectangle(cornerRadius: 14, style: .continuous)
							)
							.overlay(
								RoundedRectangle(cornerRadius: 14, style: .continuous)
									.stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
							)
						}
						.buttonStyle(.plain)
					}
				}
			}
			
			Button {
				goalStore.setGoal(
					accountID: accountID,
					actID: currentAct?.id,
					targetTier: selectedTier,
					currentTier: currentTier,
					currentRR: currentRR,
					tiers: tiersCollection
				)
				onSaved()
			} label: {
				Text("Set Season Goal")
					.font(.headline)
					.foregroundStyle(.white)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 14)
					.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.buttonStyle(.plain)
			.disabled(displayTiers.isEmpty)
		}
		.onAppear {
			guard !initializedSelection else { return }
			initializedSelection = true
			if displayTiers.contains(where: { $0.number == initialTargetTier }) {
				selectedTier = initialTargetTier
			} else if let mid = displayTiers.dropFirst(min(2, max(0, displayTiers.count - 1))).first {
				selectedTier = mid.number
			} else if let first = displayTiers.first {
				selectedTier = first.number
			}
		}
	}
}

private struct GoalLocalDataBinder: ViewModifier {
	var userID: User.ID?
	var summary: LocalData<CareerSummary>
	var matchList: LocalData<MatchList>
	
	func body(content: Content) -> some View {
		if let userID {
			content
				.withLocalData(summary, id: userID, shouldAutoUpdate: true)
				.withLocalData(matchList, id: userID, shouldAutoUpdate: true)
		} else {
			content
		}
	}
}
