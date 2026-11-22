import SwiftUI
import ValorantAPI

struct SeasonGoalsView: View {
	@EnvironmentObject private var goalStore: SeasonGoalStore
	@EnvironmentObject private var accountManager: AccountManager
	@Environment(\.seasons) private var seasons
	@Environment(\.assets) private var assets
	
	@LocalData var summary: CareerSummary?
	@LocalData var matchList: MatchList?
	
	@State private var showingSetup = false
	
	private var userID: User.ID? {
		accountManager.activeAccount?.id
	}
	
	var body: some View {
		let currentAct = seasons?.currentAct()
		let goals = goalStore.goals(for: userID, seasonID: nil)
		let cachedMatches: [MatchDetails] = {
			guard let matchList else { return [] }
			return matchList.matches.prefix(40).compactMap {
				LocalDataProvider.shared.matchDetailsManager.loadedObject(for: $0.id)
			}
		}()
		
		List {
			if let currentAct {
				Section {
					HStack {
						Text("Active Season")
							.foregroundStyle(.secondary)
						Spacer()
						Text(currentAct.nameWithEpisode)
							.font(.subheadline.weight(.semibold))
					}
				}
			}
			
			if goals.isEmpty {
				Section {
					VStack(spacing: 10) {
						Image(systemName: "target")
							.font(.largeTitle)
							.foregroundStyle(Color.valorantRed)
						Text("No Season Goals Set")
							.font(.headline)
						Text("Set a target rank, win rate, matches played, K/D, or headshot percentage goal for this Act.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 20)
				}
			} else {
				Section("Your Goals (\(goals.count))") {
					ForEach(goals) { goal in
						let eval = userID.map { uid in
							SeasonGoalStore.evaluate(
								goal,
								userID: uid,
								summary: summary,
								matches: cachedMatches,
								assets: assets,
								currentAct: currentAct
							)
						}
						
						VStack(alignment: .leading, spacing: 8) {
							HStack {
								Image(systemName: goal.kind.iconName)
									.foregroundStyle(eval?.isCompleted == true ? Color.green : Color.valorantRed)
								Text(goal.kind.title)
									.font(.headline)
								Spacer()
								if eval?.isCompleted == true {
									Label("Done", systemImage: "checkmark.seal.fill")
										.font(.caption.bold())
										.foregroundStyle(.green)
								}
							}
							
							if let eval {
								GeometryReader { geo in
									ZStack(alignment: .leading) {
										Capsule().fill(Color.secondary.opacity(0.2))
										Capsule()
											.fill(eval.isCompleted ? Color.green : Color.valorantRed)
											.frame(width: max(6, geo.size.width * CGFloat(eval.progress)))
									}
								}
								.frame(height: 6)
								
								HStack {
									Text("Current: \(eval.currentValueText)")
									Spacer()
									Text("Goal: \(eval.targetValueText)")
								}
								.font(.caption.monospacedDigit())
								.foregroundStyle(.secondary)
							}
						}
						.padding(.vertical, 4)
						.swipeActions(edge: .trailing) {
							Button(role: .destructive) {
								goalStore.delete(id: goal.id)
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
				}
			}
		}
		.navigationTitle("Season Goals")
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					showingSetup = true
				} label: {
					Image(systemName: "plus")
				}
			}
		}
		.sheet(isPresented: $showingSetup) {
			NavigationStack {
				SeasonGoalSetupView(accountID: userID, seasonID: currentAct?.id)
			}
		}
		.modifier(GoalLocalDataBinder(userID: userID, summary: $summary, matchList: $matchList))
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

struct SeasonGoalSetupView: View {
	enum GoalCategory: String, CaseIterable, Identifiable {
		case rank = "Target Rank"
		case winRate = "Win Rate %"
		case matches = "Matches Played"
		case kd = "K/D Ratio"
		case headshot = "Headshot %"
		
		var id: String { rawValue }
	}
	
	var accountID: User.ID?
	var seasonID: Season.ID?
	
	@EnvironmentObject private var goalStore: SeasonGoalStore
	@Environment(\.seasons) private var seasons
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var category: GoalCategory = .rank
	@State private var selectedTier: Int = 18 // Platinum I / Diamond I area
	@State private var targetRR: Int = 0
	@State private var targetWinRate: Double = 55
	@State private var targetMatches: Int = 50
	@State private var targetKD: Double = 1.2
	@State private var targetHS: Double = 25
	
	var body: some View {
		Form {
			Section("Goal Type") {
				Picker("Type", selection: $category) {
					ForEach(GoalCategory.allCases) { item in
						Text(item.rawValue).tag(item)
					}
				}
			}
			
			Section("Target") {
				switch category {
				case .rank:
					let tiers = (seasons?.currentTiers()?.tiers.values.filter { $0.number >= 3 } ?? [])
						.sorted { $0.number < $1.number }
					if !tiers.isEmpty {
						Picker("Rank", selection: $selectedTier) {
							ForEach(tiers, id: \.number) { tier in
								Text(tier.name).tag(tier.number)
							}
						}
					} else {
						Stepper("Tier: \(selectedTier)", value: $selectedTier, in: 3...27)
					}
					Stepper("RR: \(targetRR)", value: $targetRR, in: 0...1000, step: 10)
					
				case .winRate:
					Stepper(
						String(format: "Target Win Rate: %.0f%%", targetWinRate),
						value: $targetWinRate,
						in: Double(30)...Double(100),
						step: Double(5)
					)
					
				case .matches:
					Stepper("Matches: \(targetMatches)", value: $targetMatches, in: 5...500, step: 5)
					
				case .kd:
					Stepper(
						String(format: "Target K/D: %.2f", targetKD),
						value: $targetKD,
						in: Double(0.5)...Double(3.0),
						step: Double(0.1)
					)
					
				case .headshot:
					Stepper(
						String(format: "Target Headshot: %.0f%%", targetHS),
						value: $targetHS,
						in: Double(10)...Double(60),
						step: Double(2)
					)
				}
			}
		}
		.navigationTitle("New Season Goal")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") { dismiss() }
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Add") {
					let kind: SeasonGoal.Kind
					switch category {
					case .rank: kind = .targetRank(tier: selectedTier, rr: targetRR)
					case .winRate: kind = .winRate(percent: targetWinRate)
					case .matches: kind = .matchesPlayed(count: targetMatches)
					case .kd: kind = .kdRatio(target: targetKD)
					case .headshot: kind = .headshotRate(percent: targetHS)
					}
					goalStore.addGoal(accountID: accountID, seasonID: seasonID, kind: kind)
					dismiss()
				}
			}
		}
		.onAppear {
			if let tiers = seasons?.currentTiers()?.tiers.values,
			   !tiers.contains(where: { $0.number == selectedTier }),
			   let mid = tiers.sorted(by: { $0.number < $1.number }).dropFirst(10).first {
				selectedTier = mid.number
			}
		}
	}
}
