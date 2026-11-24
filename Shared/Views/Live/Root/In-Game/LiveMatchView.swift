import SwiftUI
import ValorantAPI
import UIKit

@MainActor
struct LiveMatchView: View {
	let gameInfo: LiveGameInfo
	let userID: User.ID
	
	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				hero
				
				SpikePlantTimer()
				
				playerList
			}
		}
		.navigationTitle("Live Match")
		.navigationBarTitleDisplayMode(.inline)
	}
	
	@ViewBuilder
	private var hero: some View {
		ZStack {
			MapImage.splash(gameInfo.mapID)
				.aspectRatio(contentMode: .fill)
				.frame(height: 200)
				.clipped()
				.overlay(MapImage.Label(mapID: gameInfo.mapID).padding(6))
			
			VStack(spacing: 10) {
				gameInfo.queueLabel
					.font(.body.weight(.medium))
					.foregroundStyle(.secondary)
			}
			.padding()
			.background(Material.thin)
			.cornerRadius(8)
			.shadow(radius: 10)
		}
	}
	
	@ViewBuilder
	private var playerList: some View {
		if let ownPlayer = gameInfo.players.firstElement(withID: userID) {
			let teams = Dictionary(grouping: gameInfo.players, by: \.teamID)
			let allyTeam = teams[ownPlayer.teamID] ?? []
			let enemyTeams = teams
				.filter { $0.key != ownPlayer.teamID }
				.sorted(on: \.key.description)
			let teamColors = Color.assignedTeamColors(
				for: [ownPlayer.teamID] + enemyTeams.map(\.key),
				ownTeamID: ownPlayer.teamID
			)
			
			VStack(spacing: 10) {
				ForEach(Array(allyTeam.enumerated()), id: \.element.id) { index, player in
					PlayerView(
						player: player,
						ownPlayer: ownPlayer,
						teamColor: teamColors[player.teamID] ?? .valorantBlue,
						isOVariant: index % 2 == 0
					)
				}
				
				ForEach(enemyTeams, id: \.key) { teamID, team in
					Divider()
						.padding(.vertical, 5)
					
					ForEach(Array(team.enumerated()), id: \.element.id) { index, player in
						PlayerView(
							player: player,
							ownPlayer: ownPlayer,
							teamColor: teamColors[player.teamID] ?? .valorantRed,
							isOVariant: index % 2 == 0
						)
					}
				}
			}
			.padding()
		}
	}
	
	struct PlayerView: View {
		let player: LiveGameInfo.PlayerInfo
		let ownPlayer: LiveGameInfo.PlayerInfo
		var teamColor: Color? = nil
		var isOVariant = true
		
		@LocalData var playerUser: User?
		@LocalData var summary: CareerSummary?
		@Environment(\.assets) private var assets
		@Environment(\.shouldAnonymize) private var shouldAnonymize
		
		init(
			player: LiveGameInfo.PlayerInfo,
			ownPlayer: LiveGameInfo.PlayerInfo,
			teamColor: Color? = nil,
			isOVariant: Bool = true
		) {
			self.player = player
			self.ownPlayer = ownPlayer
			self.teamColor = teamColor
			self.isOVariant = isOVariant
			self._playerUser = .init(id: player.id)
			self._summary = .init(id: player.id)
		}
		
		var body: some View {
			let isAlly = player.teamID == ownPlayer.teamID
			let isSelf = player.id == ownPlayer.id
			let resolvedTeamColor: Color = teamColor ?? (isAlly ? .valorantBlue : .valorantRed)
			let relativeColor = isSelf ? .valorantSelf : resolvedTeamColor
			let iconSize = 48.0
			
			HStack {
				if let agentID = player.agentID {
					AgentImage.icon(
						agentID,
						outlineRadius: 1.5,
						teamID: player.teamID,
						isOVariant: isOVariant
					)
						.frame(width: iconSize, height: iconSize)
						.mask(Circle())
						.background(Circle().fill(relativeColor).opacity(0.5).padding(2))
						.padding(2)
						.overlay(Circle().strokeBorder(relativeColor, lineWidth: 2))
				}
				
				VStack(alignment: .leading, spacing: 4) {
					if !shouldAnonymize(player.id), let playerUser {
						HStack {
							Text(playerUser.gameName)
							Text("#\(playerUser.tagLine)")
								.foregroundStyle(.secondary)
						}
					}
					
					if let agentID = player.agentID {
						let agentName = assets?.agents[agentID]?.displayName
						Text(agentName ?? "Unknown Agent!")
							.fontWeight(.semibold)
					}
				}
				
				Spacer()
				
				if !isSelf {
					TransparentNavigationLink {
						MatchListView(userID: player.id)
					} label: {
						Image(systemName: "person.crop.circle.fill")
							.padding(.horizontal, 4)
					}
				}
				
				RankInfoView(summary: summary, size: iconSize)
			}
			.accentColor(relativeColor)
			.withLocalData($playerUser, id: player.id)
			.withLocalData($summary, id: player.id, shouldAutoUpdate: true)
		}
	}
}

private struct SpikePlantTimer: View {
	private enum Stage: Equatable {
		case idle
		case normal
		case sevenSeconds
		case threeSeconds
		case detonated
		
		static let alerts: [Stage] = [.sevenSeconds, .threeSeconds]
		
		var threshold: TimeInterval {
			switch self {
			case .sevenSeconds: return 7.0
			case .threeSeconds: return 3.5
			default: return 0
			}
		}
		
		var isAlerting: Bool {
			switch self {
			case .sevenSeconds, .threeSeconds: return true
			default: return false
			}
		}
		
		var badgeText: LocalizedStringKey? {
			switch self {
			case .sevenSeconds: return "7s left"
			case .threeSeconds: return "3s left"
			default: return nil
			}
		}
	}
	
	private static let duration: TimeInterval = 45
	private static let detonationLinger: TimeInterval = 3
	
	@State private var plantedAt: Date?
	@State private var stage = Stage.idle
	@State private var isPulsing = false
	
	/// reuses the Live tab's existing haptic switch instead of adding a new setting
	@AppStorage("vibrateOnMatchFound") private var canUseHaptics = true
	
	private var endsAt: Date? {
		plantedAt?.addingTimeInterval(Self.duration)
	}
	
	private var tint: Color {
		switch stage {
		case .sevenSeconds: return .orange
		case .threeSeconds, .detonated: return .valorantRed
		default: return AppSettings.defaultAccentColor
		}
	}
	
	var body: some View {
		VStack(spacing: 8) {
			if plantedAt == nil {
				idleRow
			} else if stage == .detonated {
				detonatedRow
			} else {
				runningRow
			}
			
			if plantedAt == nil {
				Text("Tap the moment you plant — local 45-second countdown, not live game data.")
					.font(.caption2)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.task(id: plantedAt) { await runAlerts() }
		.task(id: stage) { await dismissDetonationAfterAWhile() }
	}
	
	private var idleRow: some View {
		Button(action: plant) {
			HStack(spacing: 12) {
				spikeGlyph
				
				Text("Spike Planted")
					.font(.headline)
				
				Spacer(minLength: 0)
				
				Text("45s")
					.font(.subheadline.weight(.semibold))
					.monospacedDigit()
					.padding(.horizontal, 10)
					.padding(.vertical, 4)
					.background(Capsule().fill(AppSettings.defaultAccentColor.opacity(0.15)))
			}
			.padding(14)
			.background { rowBackground(tint: tint) }
			.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Start 45 second spike timer")
	}
	
	private var runningRow: some View {
		TimelineView(.animation(minimumInterval: 1 / 4)) { context in
			let remaining = remainingTime(at: context.date)
			
			HStack(spacing: 10) {
				Button(action: plant) {
					HStack(spacing: 12) {
						spikeGlyph
						
						VStack(alignment: .leading, spacing: 6) {
							HStack(spacing: 8) {
								Text(Self.timeLabel(remaining))
									.font(.title3.weight(.semibold))
									.monospacedDigit()
								
								badge
							}
							
							progressBar(fraction: remaining / Self.duration)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Restart spike timer")
				
				Button(action: cancel) {
					Image(systemName: "xmark.circle.fill")
						.font(.title3)
						.foregroundStyle(.secondary)
						.padding(4)
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Cancel spike timer")
			}
			.padding(14)
			.background { rowBackground(tint: tint) }
		}
	}
	
	private var detonatedRow: some View {
		Button(action: dismissDetonation) {
			HStack(spacing: 12) {
				blastLayer
				
				spikeGlyph(color: .white)
				
				Text("Detonated")
					.font(.headline)
					.foregroundStyle(.white)
				
				Spacer(minLength: 0)
				
				Image(systemName: "xmark")
					.foregroundStyle(.white.opacity(0.8))
			}
			.padding(14)
			.background {
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.fill(Color.valorantRed)
			}
			.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Spike detonated, tap to dismiss")
	}
	
	private var spikeGlyph: some View {
		spikeGlyph(color: tint)
	}

	private func spikeGlyph(color: Color) -> some View {
		Image.bundledAsset("Spike Icon", renderingMode: .template)
			.resizable()
			.scaledToFit()
			.frame(width: 22, height: 22)
			.foregroundStyle(color)
	}

		@State private var blastRotation: Double = 0
	
	private var blastLayer: some View {
		ZStack {
			for i in 0..<12 {
				let baseAngle = (2 * .pi / Double(12)) * Double(i)
				let length: CGFloat = 28

				Path { path in
					path.move(to: .zero)
					path.addLine(to: CGPoint(x: cos(baseAngle) * length, y: sin(baseAngle) * length))
				}
					.stroke(
						AngularGradient(
							gradient: Gradient(colors: [.white, .valorantRed.opacity(0)]),
							center: .start)
							.opacity(0.9),
							lineWidth: 3
					)
					.rotationEffect(.radians(baseAngle))
					.frame(width: 60, height: 60)
				}
		}
		.scaleEffect(0.4)
		.opacity(0.9)
		.rotationEffect(.radians(blastRotation))
		.animation(
			.interactiveSpring(response: 0.4, dampingFraction: 0.5)
			.repeatForever(autoreverses: false),
			value: blastRotation
	)
	}

	@ViewBuilder
	private var badge: some View {
		if let badgeText = stage.badgeText {
			Text(badgeText)
				.font(.caption.weight(.bold))
				.foregroundStyle(.white)
				.padding(.horizontal, 7)
				.padding(.vertical, 2)
				.background(Capsule().fill(tint))
				.transition(.scale.combined(with: .opacity))
		}
	}
	
	private func progressBar(fraction: Double) -> some View {
		GeometryReader { geometry in
			ZStack(alignment: .leading) {
				Capsule()
					.fill(Color.secondary.opacity(0.2))
				
				Capsule()
					.fill(tint)
					.frame(width: max(0, geometry.size.width * min(1, fraction)))
			}
		}
		.frame(height: 4)
	}
	
	private func rowBackground(tint: Color) -> some View {
		RoundedRectangle(cornerRadius: 14, style: .continuous)
			.fill(tint.opacity(0.1))
			.overlay {
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.strokeBorder(tint, lineWidth: 1.5)
					.opacity(stage.isAlerting ? (isPulsing ? 1 : 0.25) : 0.4)
			}
	}
	
	private func remainingTime(at date: Date) -> TimeInterval {
		guard let endsAt else { return 0 }
		return max(0, endsAt.timeIntervalSince(date))
	}
	
	private static func timeLabel(_ remaining: TimeInterval) -> String {
		let clipped = max(0, remaining)
		if clipped < 10 {
			return String(format: "%.1fs", clipped)
		}
		let total = Int(clipped.rounded(.up))
		return String(format: "%d:%02d", total / 60, total % 60)
	}
	
	private func plant() {
		withAnimation(.default) { isPulsing = false }
		stage = .normal
		plantedAt = .now
	}
	
	private func cancel() {
		plantedAt = nil
		withAnimation(.default) {
			isPulsing = false
			stage = .idle
		}
	}
	
	private func dismissDetonation() {
		plantedAt = nil
		withAnimation(.default) {
			isPulsing = false
			stage = .idle
			blastRotation = 0
		}
	}
	
	private func fireDetonation() {
		blastRotation = 360
		guard canUseHaptics else { return }
		let generator = UIImpactFeedbackGenerator(style: .heavy)
		generator.prepare()
		generator.impactOccurred()
	}
	
	/// fires the two alerts and then the detonation, all derived from the plant date so nothing drifts
	private func runAlerts() async {
		guard let plantedAt else { return }
		let end = plantedAt.addingTimeInterval(Self.duration)
		
		for alert in Stage.alerts {
			let delay = end.addingTimeInterval(-alert.threshold).timeIntervalSinceNow
			if delay > 0 {
				try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
			}
			guard !Task.isCancelled, self.plantedAt == plantedAt else { return }
			
			withAnimation(.easeInOut(duration: 0.2)) { stage = alert }
			startPulsing()
			fireHaptic(alert)
		}
		
		let delay = end.timeIntervalSinceNow
		if delay > 0 {
			try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
		}
		guard !Task.isCancelled, self.plantedAt == plantedAt else { return }
		
		withAnimation(.default) { stage = .detonated }
		fireDetonation()
	}
	
	private func dismissDetonationAfterAWhile() async {
		guard stage == .detonated else { return }
		try? await Task.sleep(nanoseconds: UInt64(Self.detonationLinger * 1_000_000_000))
		guard !Task.isCancelled, stage == .detonated else { return }
		dismissDetonation()
	}
	
	private func startPulsing() {
		isPulsing = false
		withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
			isPulsing = true
		}
	}
	
	private func fireHaptic(_ stage: Stage) {
		guard canUseHaptics else { return }
		let generator = UINotificationFeedbackGenerator()
		generator.prepare()
		switch stage {
		case .sevenSeconds:
			generator.notificationOccurred(.warning)
		case .threeSeconds:
			generator.notificationOccurred(.error)
		default:
			break
		}
	}
}

extension EnvironmentValues {
	var anonymization: AnonymizationMode {
		get { self[AnonymizationModeKey.self] }
		set { self[AnonymizationModeKey.self] = newValue }
	}
	
	var shouldAnonymize: (Player.ID) -> Bool {
		anonymization.shouldAnonymize(_:)
	}
	
	private enum AnonymizationModeKey: EnvironmentKey {
		static let defaultValue = AnonymizationMode.none
	}
}

extension View {
	func anonymizing(additionally mode: AnonymizationMode) -> some View {
		transformEnvironment(\.anonymization) { $0 = $0.merging(mode) }
	}
}

enum AnonymizationMode {
	case all
	case some(Set<Player.ID>)
	case none
	
	func merging(_ other: Self) -> Self {
		switch (self, other) {
		case (.all, _), (_, .all):
			return .all
		case (.none, let other), (let other, .none):
			return other
		case (.some(let p1), .some(let p2)):
			return .some(p1.union(p2))
		}
	}
	
	func shouldAnonymize(_ player: Player.ID) -> Bool {
		false
	}
}

#if DEBUG
struct LiveMatchView_Previews: PreviewProvider {
	static var previews: some View {
		LiveMatchView(
			gameInfo: PreviewData.liveGameInfo,
			userID: PreviewData.userID
		)
		.withToolbar()
	}
}
#endif
