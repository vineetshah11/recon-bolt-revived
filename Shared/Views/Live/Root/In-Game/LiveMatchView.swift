import SwiftUI
import ValorantAPI
import UIKit
import ImageIO

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
			case normal
			case sevenSeconds
			case threeSeconds
			
			static let alerts: [Stage] = [.sevenSeconds, .threeSeconds]
			
			/// seconds left at which this stage starts
			var threshold: TimeInterval {
				switch self {
				case .sevenSeconds: return 7
				case .threeSeconds: return 3.5
				default: return 0
				}
			}
			
			var isAlerting: Bool {
				self == .sevenSeconds || self == .threeSeconds
			}
			
			var badgeText: LocalizedStringKey? {
				switch self {
				case .sevenSeconds: return "7s left"
				case .threeSeconds: return "3.5s left"
				default: return nil
				}
			}
			
			/// the stage the countdown is in at this many seconds left
			static func at(_ remaining: TimeInterval) -> Self {
				if remaining <= 3.5 { return .threeSeconds }
				if remaining <= 7 { return .sevenSeconds }
				return .normal
			}
			
			var tint: Color {
				switch self {
				case .sevenSeconds: return .orange
				case .threeSeconds: return .valorantRed
				default: return AppSettings.defaultAccentColor
				}
			}
		}
		
		private static let duration: TimeInterval = 45
		private static let detonationLinger: TimeInterval = 3
		/// fire the haptics a touch early so they land on the mark instead of a few frames after it
		private static let alertLead: TimeInterval = 0.2
		private static let glyphSize: CGFloat = 52
		
		@State private var plantedAt: Date?
		@State private var isDetonated = false
		
		/// reuses the Live tab's existing haptic switch instead of adding a new setting
		@AppStorage("vibrateOnMatchFound") private var canUseHaptics = true
		
		private var endsAt: Date? {
			plantedAt?.addingTimeInterval(Self.duration)
		}
		
		var body: some View {
			VStack(spacing: 8) {
				if plantedAt == nil {
					idleRow
				} else if isDetonated {
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
			.task(id: isDetonated) { await dismissDetonationAfterAWhile() }
		}
		
		private var idleRow: some View {
			Button(action: plant) {
				HStack(spacing: 12) {
					spikeGlyph(color: Stage.normal.tint)
					
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
				.background { rowBackground(tint: Stage.normal.tint, borderOpacity: 0.4) }
				.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Start 45 second spike timer")
		}
		
		private var runningRow: some View {
			TimelineView(.animation(minimumInterval: 1 / 30)) { context in
				let remaining = remainingTime(at: context.date)
				let stage = Stage.at(remaining)
				
				HStack(spacing: 10) {
					Button(action: plant) {
						HStack(spacing: 12) {
							spikeGlyph(color: stage.tint)
							
							VStack(alignment: .leading, spacing: 6) {
								HStack(spacing: 8) {
									Text(Self.timeLabel(remaining))
										.font(.title3.weight(.semibold))
										.monospacedDigit()
									
									badge(for: stage)
								}
								
								progressBar(fraction: remaining / Self.duration, tint: stage.tint)
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
				.background {
					rowBackground(
						tint: stage.tint,
						borderOpacity: stage.isAlerting
							? 0.55 + 0.45 * (sin(context.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
							: 0.4
					)
				}
			}
		}
		
		private var detonatedRow: some View {
			Button(action: dismissDetonation) {
				HStack(spacing: 12) {
					detonationLayer
					
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
				.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
				.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Spike detonated, tap to dismiss")
		}
		
		private var detonationLayer: some View {
			DetonationGIFView()
				.frame(width: Self.glyphSize, height: Self.glyphSize)
				.clipped()
		}
		
		private func spikeGlyph(color: Color) -> some View {
			Image.bundledAsset("Spike Icon", renderingMode: .template)
				.resizable()
				.scaledToFit()
				.frame(width: 22, height: 22)
				.foregroundStyle(color)
		}
		
		@ViewBuilder
		private func badge(for stage: Stage) -> some View {
			if let text = stage.badgeText {
				Text(text)
					.font(.caption.weight(.bold))
					.foregroundStyle(.white)
					.padding(.horizontal, 7)
					.padding(.vertical, 2)
					.background(Capsule().fill(stage.tint))
					.transition(.scale.combined(with: .opacity))
			}
		}
		
		private func progressBar(fraction: Double, tint: Color) -> some View {
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
		
		private func rowBackground(tint: Color, borderOpacity: Double) -> some View {
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.fill(tint.opacity(0.1))
				.overlay {
					RoundedRectangle(cornerRadius: 14, style: .continuous)
						.strokeBorder(tint, lineWidth: 1.5)
						.opacity(borderOpacity)
				}
		}
		
		private func remainingTime(at date: Date) -> TimeInterval {
			guard let endsAt else { return 0 }
			return max(0, endsAt.timeIntervalSince(date))
		}
		
		/// always tenths while under 10s, otherwise M:SS. Rounded to the nearest displayed tick so the label
		/// is monotone and does not appear to stutter when the timeline recomputes.
		private static func timeLabel(_ remaining: TimeInterval) -> String {
			let clipped = max(0, remaining)
			if clipped < 10 {
				// round to one decimal so 9.95+ -> 10.0 already counts as the next tick.
				return String(format: "%.1fs", max(0, (clipped * 10.0).rounded(.toNearestOrAwayFromZero) / 10.0))
			}
			let total = Int(clipped.rounded(.awayFromZero))
			return String(format: "%d:%02d", total / 60, total % 60)
		}
		
		private func plant() {
			isDetonated = false
			plantedAt = .now
		}
		
		private func cancel() {
			plantedAt = nil
			isDetonated = false
		}
		
		private func dismissDetonation() {
			plantedAt = nil
			isDetonated = false
		}
		
		private func fireDetonation() {
			guard canUseHaptics else { return }
			let generator = UIImpactFeedbackGenerator(style: .heavy)
			generator.prepare()
			generator.impactOccurred()
		}
		
		/// fires the two haptics on the 7s and 3.5s marks, then flips to the detonated row at hard zero.
		/// the badge text comes from the countdown itself, so it is always on screen when the haptic lands.
		private func runAlerts() async {
			guard let plantedAt else { return }
			let end = plantedAt.addingTimeInterval(Self.duration)
			
			for alert in Stage.alerts {
				let trigger = end.addingTimeInterval(-alert.threshold - Self.alertLead)
				let ready = trigger.timeIntervalSinceNow
				if ready > 0 {
					try? await Task.sleep(nanoseconds: UInt64(ready * 1_000_000_000))
				}
				guard !Task.isCancelled, self.plantedAt == plantedAt else { return }
				
				fireHaptic(alert)
			}
			
			let timeToEnd = end.timeIntervalSinceNow
			if timeToEnd > 0 {
				try? await Task.sleep(nanoseconds: UInt64(timeToEnd * 1_000_000_000))
			}
			guard !Task.isCancelled, self.plantedAt == plantedAt else { return }
			
			fireDetonation()
			withAnimation(.default) { isDetonated = true }
		}
		
		private func dismissDetonationAfterAWhile() async {
			guard isDetonated else { return }
			try? await Task.sleep(nanoseconds: UInt64(Self.detonationLinger * 1_000_000_000))
			guard !Task.isCancelled, isDetonated else { return }
			dismissDetonation()
		}
		
		private func fireHaptic(_ stage: Stage) {
			guard canUseHaptics else { return }
			let notification = UINotificationFeedbackGenerator()
			notification.prepare()
			switch stage {
			case .sevenSeconds:
				let impact = UIImpactFeedbackGenerator(style: .light)
				impact.prepare()
				impact.impactOccurred()
				notification.notificationOccurred(.warning)
			case .threeSeconds:
				let impact = UIImpactFeedbackGenerator(style: .medium)
				impact.prepare()
				impact.impactOccurred()
				notification.notificationOccurred(.error)
			case .normal:
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

/// plays the bundled blast GIF once, sized to the detonated row's slot.
private struct DetonationGIFView: UIViewRepresentable {
	func makeUIView(context: Context) -> UIImageView {
		let view = FittedGIFView()
		view.contentMode = .scaleAspectFit
		view.clipsToBounds = true
		view.backgroundColor = .clear
		
		guard
			let url = Bundle.module.url(forResource: "BundledAssets/DetonationImage", withExtension: "gif")
				?? Bundle.module.url(forResource: "DetonationImage", withExtension: "gif"),
			let data = try? Data(contentsOf: url),
			let source = CGImageSourceCreateWithData(data as CFData, nil)
		else { return view }
		
		var frames: [UIImage] = []
		var duration: TimeInterval = 0
		for index in 0..<CGImageSourceGetCount(source) {
			guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
			frames.append(UIImage(cgImage: frame))
			duration += Self.frameDuration(of: source, at: index)
		}
		
		view.animationImages = frames
		view.animationDuration = max(duration, 0.1)
		view.animationRepeatCount = 1
		view.startAnimating()
		return view
	}
	
	func updateUIView(_ uiView: UIImageView, context: Context) {}
	
	private static func frameDuration(of source: CGImageSource, at index: Int) -> TimeInterval {
		let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
		let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
		let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
			?? gif?[kCGImagePropertyGIFDelayTime] as? Double
			?? 0.1
		return delay > 0.01 ? delay : 0.1
	}
}

/// SwiftUI sizes a representable from its intrinsic size, and the GIF's frames are much bigger
/// than the row slot — pin the intrinsic size so the blast fits inside the row instead of
/// stretching it.
private final class FittedGIFView: UIImageView {
	override var intrinsicContentSize: CGSize {
		CGSize(width: 52, height: 52)
	}
}
