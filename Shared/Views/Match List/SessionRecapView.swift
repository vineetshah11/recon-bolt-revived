import SwiftUI
import ValorantAPI

struct SessionRecapView: View {
	var userID: User.ID
	var sessions: [PlaySession]
	
	@LocalData var user: User?
	@LocalData var identity: Player.Identity?
	
	@Environment(\.assets) private var assets
	@EnvironmentObject private var imageManager: ImageManager
	
	@State private var selectedIndex = 0
	@State private var sharingSession: PlaySession?
	
	init(userID: User.ID, sessions: [PlaySession]) {
		self.userID = userID
		self.sessions = sessions
		self._user = .init(id: userID)
		self._identity = .init(id: userID)
	}
	
	private var activeSession: PlaySession? {
		guard !sessions.isEmpty else { return nil }
		let clamped = min(max(0, selectedIndex), sessions.count - 1)
		return sessions[clamped]
	}
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				if sessions.isEmpty {
					VStack(spacing: 10) {
						Image(systemName: "clock.badge.checkmark")
							.font(.system(size: 38, weight: .light))
							.foregroundStyle(.secondary)
						Text("No Session Activity Yet")
							.font(.headline.weight(.bold))
						Text("Open recent matches to cache their details and generate play-session recaps.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}
					.frame(maxWidth: .infinity)
					.padding(28)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
				} else {
					if sessions.count > 1 {
						sessionSelectorBar
					}
					
					if let session = activeSession {
						SessionRecapCard(
							session: session,
							user: user,
							cardID: identity?.cardID,
							assets: assets
						)
						
						Button {
							sharingSession = session
						} label: {
							Label("Share Session Recap", systemImage: "square.and.arrow.up")
								.font(.headline)
								.foregroundStyle(.white)
								.frame(maxWidth: .infinity)
								.padding(.vertical, 14)
								.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
						}
						.buttonStyle(.plain)
						
						matchesSection(for: session)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Session Recap")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			if let session = activeSession {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button {
						sharingSession = session
					} label: {
						Image(systemName: "square.and.arrow.up")
							.foregroundStyle(Color.accentColor)
					}
				}
			}
		}
		.sheet(item: $sharingSession) { session in
			SessionRecapShareSheet(
				session: session,
				user: user,
				cardID: identity?.cardID
			)
		}
		.withLocalData($user, id: userID)
		.withLocalData($identity, id: userID)
	}
	
	private var sessionSelectorBar: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
					let isSelected = min(selectedIndex, sessions.count - 1) == index
					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							selectedIndex = index
						}
					} label: {
						VStack(alignment: .leading, spacing: 2) {
							Text(session.startTime.formatted(.dateTime.day().month(.abbreviated)))
								.font(.caption.weight(.bold))
							Text("\(session.items.count) \(session.items.count == 1 ? "match" : "matches") · \(session.wins)W-\(session.losses)L")
								.font(.caption2.monospacedDigit())
								.foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
						}
						.padding(.horizontal, 12)
						.padding(.vertical, 8)
						.background(
							isSelected ? Color.accentColor : Color.secondaryGroupedBackground,
							in: RoundedRectangle(cornerRadius: 12, style: .continuous)
						)
						.foregroundStyle(isSelected ? .white : .primary)
					}
					.buttonStyle(.plain)
				}
			}
		}
	}
	
	private func matchesSection(for session: PlaySession) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("MATCHES IN SESSION")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			VStack(spacing: 0) {
				ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
					let match = item.details
					let player = match.players.firstElement(withID: userID)
					let winner = match.teams.first(where: \.won)
					let won = winner?.id == player?.teamID
					let isDraw = winner == nil
					
					NavigationLink {
						MatchDetailsContainer(matchID: match.id, userID: userID)
					} label: {
						HStack(spacing: 10) {
							if let player, let agentID = player.agentID {
								let isOVariant = Team.ID.isGauntletOVariant(
									for: player.id,
									teamID: player.teamID,
									in: match.players
								)
								AgentImage.icon(agentID, teamID: player.teamID, isOVariant: isOVariant)
									.frame(width: 36, height: 36)
									.background(Color.tertiaryGroupedBackground)
									.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
							}
							
							VStack(alignment: .leading, spacing: 2) {
								HStack(spacing: 6) {
									Text(assets?.maps[match.matchInfo.mapID]?.displayName ?? "Map")
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(.primary)
									match.matchInfo.queueLabel
										.font(.caption2)
										.foregroundStyle(.secondary)
								}
								
								if let s = player?.stats {
									let acs = s.roundsPlayed > 0 ? s.score / s.roundsPlayed : 0
									Text("\(s.kills) / \(s.deaths) / \(s.assists) · \(acs) ACS")
										.font(.caption.monospacedDigit())
										.foregroundStyle(.secondary)
								}
							}
							
							Spacer()
							
							if let upd = item.update, upd.isRanked {
								Text(upd.ratingEarned >= 0 ? "+\(upd.ratingEarned) RR" : "\(upd.ratingEarned) RR")
									.font(.caption.bold().monospacedDigit())
									.foregroundStyle(upd.ratingEarned >= 0 ? Color.green : Color.valorantRed)
							} else {
								Text(isDraw ? "DRAW" : (won ? "WIN" : "LOSS"))
									.font(.caption2.bold())
									.foregroundStyle(isDraw ? Color.secondary : (won ? Color.green : Color.valorantRed))
							}
							
							Image(systemName: "chevron.right")
								.font(.caption2.weight(.semibold))
								.foregroundStyle(.secondary)
						}
						.padding(14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					
					if index < session.items.count - 1 {
						Divider().opacity(0.22).padding(.leading, 60)
					}
				}
			}
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
}

// MARK: - Valpaw Hero Recap Card

private struct SessionRecapCard: View {
	let session: PlaySession
	let user: User?
	let cardID: PlayerCard.ID?
	let assets: AssetCollection?
	var preloadedCardImage: UIImage? = nil
	var preloadedAgentImage: UIImage? = nil
	
	var body: some View {
		ZStack(alignment: .topTrailing) {
			RadialGradient(
				colors: [Color.accentColor.opacity(0.18), Color.clear],
				center: .topTrailing,
				startRadius: 10,
				endRadius: 240
			)
			
			VStack(alignment: .leading, spacing: 18) {
				headerRow
				
				scoreBlock
				
				playerAndNetRRRow
				
				primaryMetricsStrip
				
				insightsStrip
				
				bottomRow
			}
			.padding(20)
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.stroke(Color.white.opacity(0.08), lineWidth: 1)
		)
		.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
	}
	
	private var headerRow: some View {
		HStack(alignment: .top) {
			VStack(alignment: .leading, spacing: 3) {
				Text("SESSION RECAP")
					.font(.system(size: 11, weight: .semibold))
					.tracking(0.8)
					.foregroundStyle(.secondary)
				
				Text(session.startTime.formatted(.dateTime.day().month(.wide)))
					.font(.title3.weight(.bold))
					.foregroundStyle(.primary)
				
				Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) – \(session.endTime.formatted(date: .omitted, time: .shortened))")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}
			
			Spacer()
			
			VStack(alignment: .trailing, spacing: 3) {
				Text("\(session.items.count) \(session.items.count == 1 ? "MATCH" : "MATCHES")")
					.font(.system(size: 11, weight: .bold).monospacedDigit())
					.foregroundStyle(.primary.opacity(0.85))
				
				Text(queueDisplayName.uppercased())
					.font(.system(size: 10, weight: .semibold))
					.foregroundStyle(.secondary)
			}
		}
	}
	
	private var queueDisplayName: String {
		if session.isMixedQueues { return "Mixed Queues" }
		if let q = session.primaryQueueID, let name = assets?.queues[q]?.name {
			return name
		}
		if let q = session.primaryQueueID {
			return q.rawValue.replacingOccurrences(of: "_", with: " ")
		}
		return "VALORANT"
	}
	
	private var scoreBlock: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack(alignment: .firstTextBaseline, spacing: 6) {
				Text("\(session.wins)")
					.font(.system(size: 46, weight: .bold).monospacedDigit())
					.foregroundStyle(.primary)
				Text("–")
					.font(.system(size: 38, weight: .light))
					.foregroundStyle(.secondary)
				Text("\(session.losses)")
					.font(.system(size: 46, weight: .bold).monospacedDigit())
					.foregroundStyle(.secondary)
				if session.draws > 0 {
					Text("– \(session.draws)")
						.font(.system(size: 28, weight: .semibold).monospacedDigit())
						.foregroundStyle(.secondary)
				}
			}
			
			Text("WINS – LOSSES")
				.font(.system(size: 10, weight: .semibold))
				.tracking(0.8)
				.foregroundStyle(.secondary)
		}
	}
	
	private var playerAndNetRRRow: some View {
		HStack(spacing: 12) {
			Group {
				if let preloadedCardImage {
					Image(uiImage: preloadedCardImage)
						.resizable()
						.scaledToFill()
				} else {
					PlayerCardImage.small(cardID)
				}
			}
			.frame(width: 44, height: 44)
			.background(Color.tertiaryGroupedBackground)
			.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			
			VStack(alignment: .leading, spacing: 1) {
				Text(user?.gameName ?? "Player")
					.font(.headline.weight(.bold))
					.foregroundStyle(.primary)
					.lineLimit(1)
				if let tag = user?.tagLine, !tag.isEmpty {
					Text("#\(tag)")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}
			
			Spacer()
			
			if session.hasRankedMatches || session.netRRDelta != 0 {
				VStack(alignment: .trailing, spacing: 2) {
					Text(session.netRRDelta >= 0 ? "+\(session.netRRDelta)" : "\(session.netRRDelta)")
						.font(.title3.weight(.bold).monospacedDigit())
						.foregroundStyle(session.netRRDelta >= 0 ? Color.green : Color.valorantRed)
					Text("NET RR")
						.font(.system(size: 10, weight: .semibold))
						.foregroundStyle(.secondary)
				}
			}
		}
	}
	
	private var primaryMetricsStrip: some View {
		HStack(spacing: 0) {
			metricCell("\(session.items.count)", label: "MATCHES")
			metricCell("\(Int(session.winRate.rounded())) %", label: "WIN RATE")
			metricCell("\(session.totalKills)/\(session.totalDeaths)/\(session.totalAssists)", label: "K/D/A")
			metricCell(String(format: "%.2f", session.kdRatio), label: "K/D")
		}
		.padding(.vertical, 12)
		.padding(.horizontal, 6)
		.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func metricCell(_ value: String, label: String) -> some View {
		VStack(spacing: 3) {
			Text(value)
				.font(.subheadline.weight(.bold).monospacedDigit())
				.foregroundStyle(.primary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
			Text(label)
				.font(.system(size: 9, weight: .semibold))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
	}
	
	private var insightsStrip: some View {
		VStack(spacing: 10) {
			HStack(spacing: 10) {
				if let topAgentID = session.topAgentID {
					HStack(spacing: 8) {
						Group {
							if let preloadedAgentImage {
								Image(uiImage: preloadedAgentImage)
									.resizable()
									.scaledToFill()
							} else {
								AgentImage.icon(topAgentID, teamID: nil)
							}
						}
						.frame(width: 28, height: 28)
						.background(Color.secondaryGroupedBackground)
						.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
						
						VStack(alignment: .leading, spacing: 1) {
							Text("TOP AGENT")
								.font(.system(size: 9, weight: .semibold))
								.foregroundStyle(.secondary)
							HStack(spacing: 4) {
								AgentLabel(agent: topAgentID)
									.font(.caption.weight(.bold))
									.lineLimit(1)
								Text("\(session.topAgentWins)W-\(max(0, session.topAgentMatches - session.topAgentWins))L")
									.font(.caption2.monospacedDigit())
									.foregroundStyle(.secondary)
							}
						}
						Spacer(minLength: 0)
					}
					.padding(10)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				
				if let topMapID = session.topMapID {
					HStack(spacing: 8) {
						Image(systemName: "map.fill")
							.font(.subheadline)
							.foregroundStyle(Color.accentColor)
							.frame(width: 24)
						
						VStack(alignment: .leading, spacing: 1) {
							Text("TOP MAP")
								.font(.system(size: 9, weight: .semibold))
								.foregroundStyle(.secondary)
							HStack(spacing: 4) {
								Text(assets?.maps[topMapID]?.displayName ?? topMapID.rawValue)
									.font(.caption.weight(.bold))
									.lineLimit(1)
								Text("\(session.topMapWins)W-\(max(0, session.topMapMatches - session.topMapWins))L")
									.font(.caption2.monospacedDigit())
									.foregroundStyle(.secondary)
							}
						}
						Spacer(minLength: 0)
					}
					.padding(10)
					.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
			}
			
			HStack {
				Text("ACS \(session.averageACS)")
				Spacer()
				Text("ADR \(session.averageADR)")
				Spacer()
				Text("HS \(String(format: "%.1f%%", session.headshotPercentage))")
			}
			.font(.caption.weight(.semibold).monospacedDigit())
			.foregroundStyle(.secondary)
			.padding(.horizontal, 6)
		}
	}
	
	private var bottomRow: some View {
		HStack(alignment: .bottom, spacing: 8) {
			if !session.highlights.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 6) {
						ForEach(session.highlights) { highlight in
							Text(highlight.pillText)
								.font(.system(size: 10, weight: .bold).monospacedDigit())
								.foregroundStyle(.primary.opacity(0.9))
								.padding(.horizontal, 10)
								.padding(.vertical, 5)
								.background(Color.tertiaryGroupedBackground, in: Capsule())
								.overlay(
									Capsule()
										.stroke(Color.white.opacity(0.12), lineWidth: 1)
								)
						}
					}
				}
			} else {
				Text("\(session.totalRounds) rounds played")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			
			Spacer(minLength: 4)
			
			Image(systemName: "shield.lefthalf.filled")
				.font(.caption.weight(.semibold))
				.foregroundStyle(Color.accentColor.opacity(0.85))
		}
	}
}

// MARK: - Share Session Recap Sheet

private struct SessionRecapShareSheet: View {
	let session: PlaySession
	let user: User?
	let cardID: PlayerCard.ID?
	
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var imageManager: ImageManager
	
	@State private var renderedImage: UIImage?
	@State private var isRendering = false
	@State private var preloadedCard: UIImage?
	@State private var preloadedAgent: UIImage?
	
	var body: some View {
		NavigationView {
			ScrollView {
				VStack(spacing: 16) {
					SessionRecapCard(
						session: session,
						user: user,
						cardID: cardID,
						assets: assets,
						preloadedCardImage: preloadedCard,
						preloadedAgentImage: preloadedAgent
					)
					
					if let renderedImage {
						ShareLink(
							item: Image(uiImage: renderedImage),
							preview: SharePreview("Session Recap", image: Image(uiImage: renderedImage))
						) {
							Label("Share Image", systemImage: "square.and.arrow.up")
								.font(.headline)
								.foregroundStyle(.white)
								.frame(maxWidth: .infinity)
								.padding(.vertical, 14)
								.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
					} else if isRendering {
						ProgressView("Rendering recap...")
					}
				}
				.padding(16)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Share Session Recap")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
			.task {
				await renderSnapshot()
			}
		}
	}
	
	@MainActor
	private func renderSnapshot() async {
		isRendering = true
		if let cardID, let cardAsset = assets?.playerCards[cardID]?.smallArt {
			if let cached = cardAsset.load() {
				preloadedCard = cached
			} else {
				_ = try? await cardAsset.ensureDownloaded()
				preloadedCard = cardAsset.load()
			}
		}
		if let aid = session.topAgentID, let agentAsset = assets?.agents[aid]?.displayIcon {
			if let cached = agentAsset.load() {
				preloadedAgent = cached
			} else {
				_ = try? await agentAsset.ensureDownloaded()
				preloadedAgent = agentAsset.load()
			}
		}
		
		let renderer = ImageRenderer(
			content: SessionRecapCard(
				session: session,
				user: user,
				cardID: cardID,
				assets: assets,
				preloadedCardImage: preloadedCard,
				preloadedAgentImage: preloadedAgent
			)
			.environment(\.assets, assets)
			.environmentObject(imageManager)
			.frame(width: 375)
			.padding(16)
			.background(Color.groupedBackground)
			.preferredColorScheme(.dark)
		)
		renderer.scale = 3.0
		renderedImage = renderer.uiImage
		isRendering = false
	}
}
