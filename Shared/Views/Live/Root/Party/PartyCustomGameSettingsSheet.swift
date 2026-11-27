import SwiftUI
import ValorantAPI

struct PartyCustomGameSettingsSheet: View {
	private struct MapOption: Identifiable, Equatable {
		var id: String { path }
		let path: String
		let name: String
	}
	
	private struct ModeOption: Identifiable, Equatable {
		var id: String { path }
		let path: String
		let name: String
	}
	
	private struct PingOption: Identifiable, Equatable {
		var id: String { ping.serverID }
		let ping: Party.Member.ServerPing
		let name: String
	}
	
	@Binding var party: Party
	let userID: User.ID
	var onPartyChanged: () async -> Void = {}
	
	@State private var settings: Party.CustomGameData.Settings
	@State private var rules: Party.CustomGameData.GameRules
	@State private var configs: CustomGameConfigs?
	@State private var cachedMapOptions: [MapOption] = []
	@State private var cachedModeOptions: [ModeOption] = []
	@State private var cachedPingOptions: [PingOption] = []
	@State private var isSaving = false
	@State private var isReturningToStandard = false
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	init(
		party: Binding<Party>,
		userID: User.ID,
		onPartyChanged: @escaping () async -> Void = {}
	) {
		self._party = party
		self.userID = userID
		self.onPartyChanged = onPartyChanged
		let current = party.wrappedValue.customGameData?.settings ?? .init()
		self._settings = State(initialValue: current)
		self._rules = State(initialValue: current.gameRules ?? .init())
	}
	
	private var isOwner: Bool {
		(party.members.firstElement(withID: userID) ?? party.members.first)?.isOwner == true
	}
	
	private var canEdit: Bool {
		isOwner && party.state == .customGameSetup && !isSaving && !isReturningToStandard
	}
	
	private var selfPings: [Party.Member.ServerPing] {
		(party.members.firstElement(withID: userID) ?? party.members.first)?.pings ?? []
	}
	
	private static let fallbackModes: [String] = [
		"/Game/GameModes/Bomb/BombGameMode.BombGameMode_C",
		"/Game/GameModes/_Development/Swiftplay_EndOfRoundCredits/Swiftplay_EoRCredits_GameMode.Swiftplay_EoRCredits_GameMode_C",
		"/Game/GameModes/QuickBomb/QuickBombGameMode.QuickBombGameMode_C",
		"/Game/GameModes/Deathmatch/DeathmatchGameMode.DeathmatchGameMode_C",
		"/Game/GameModes/GunGame/GunGameTeamsGameMode.GunGameTeamsGameMode_C",
		"/Game/GameModes/HURM/HURMGameMode.HURMGameMode_C",
		"/Game/GameModes/Skirmish/SkirmishGameMode.SkirmishGameMode_C",
	]
	
	private func computeSelectableModePaths() -> [String] {
		let modeFolders = assets?.modeFoldersByShortName ?? [:]
		let configModes = configs?.selectableModes(knownModeFoldersByShortName: modeFolders) ?? []
		var modes = configModes.isEmpty ? Self.fallbackModes : configModes
		if !settings.mode.isEmpty {
			let canonicalCurrent = CustomGameConfigs.canonicalModePath(
				for: settings.mode,
				knownModeFoldersByShortName: modeFolders
			)
			let currentShort = CustomGameConfigs.modeShortName(from: canonicalCurrent)
			if !modes.contains(where: { CustomGameConfigs.modeShortName(from: $0).caseInsensitiveCompare(currentShort) == .orderedSame }) {
				modes.insert(canonicalCurrent, at: 0)
			}
		}
		return modes
	}
	
	private func computeValidMapPaths(for modePath: String) -> [String] {
		let nonTacticalKnown = assets?.knownNonTacticalMapPathsLowercased ?? []
		let knownMapPaths = assets?.canonicalMapPathsByShortName ?? [:]
		if let configs, !configs.enabledMaps.isEmpty {
			return configs.validMaps(
				forMode: modePath,
				knownNonTacticalMapPaths: nonTacticalKnown,
				knownMapPathsByShortName: knownMapPaths
			)
		}
		let category = CustomGameConfigs.ModeCategory(modePath: modePath)
		guard let assetMaps = assets?.maps.values else { return [] }
		return assetMaps
			.map(\.id.rawValue)
			.filter { path in
				switch category {
				case .standard:
					return category.accepts(mapPath: path) && !nonTacticalKnown.contains(path.lowercased())
				default:
					return category.accepts(mapPath: path)
				}
			}
	}
	
	private func rebuildCachedOptions() {
		let validMaps = computeValidMapPaths(for: settings.mode)
		cachedMapOptions = validMaps
			.map { MapOption(path: $0, name: mapDisplayName($0)) }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		
		cachedModeOptions = computeSelectableModePaths()
			.map { ModeOption(path: $0, name: modeDisplayName($0)) }
		
		cachedPingOptions = selfPings
			.map { PingOption(ping: $0, name: serverDisplayName($0.serverID)) }
			.sorted { lhs, rhs in
				if lhs.ping.ping != rhs.ping.ping { return lhs.ping.ping < rhs.ping.ping }
				return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
			}
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					mapPreviewCard
					matchSetupCard
					gameRulesCard
					
					if isOwner {
						exitCustomLobbyButton
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 14)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Custom Game Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Button("Cancel") {
						dismiss()
					}
				}
				
				ToolbarItem(placement: .navigationBarTrailing) {
					Button {
						saveSettings()
					} label: {
						if isSaving {
							ProgressView()
								.tint(.white)
						} else {
							Image(systemName: "checkmark")
								.fontWeight(.semibold)
						}
					}
					.buttonStyle(.borderedProminent)
					.tint(Color.accentColor)
					.disabled(!canEdit)
				}
			}
			.onAppear {
				ensureValidMapForCurrentMode()
				rebuildCachedOptions()
			}
			.onChange(of: assets?.version) { _ in
				rebuildCachedOptions()
			}
			.onChange(of: settings.mode) { _ in
				rebuildCachedOptions()
			}
			.onChange(of: selfPings) { _ in
				rebuildCachedOptions()
			}
			.valorantLoadTask { client in
				let fetched = try await client.getCustomGameConfigs()
				configs = fetched
				ensureValidMapForCurrentMode()
				rebuildCachedOptions()
			}
		}
	}
	
	private var mapPreviewCard: some View {
		let mapID = resolvedMapInfo(for: settings.map)?.id
			?? MapID(
				settings.map.isEmpty
					? MapID.ascent.rawValue
					: CustomGameConfigs.canonicalMapPath(
						for: settings.map,
						knownMapPathsByShortName: assets?.canonicalMapPathsByShortName ?? [:]
					)
			)
		return ZStack(alignment: .bottomLeading) {
			MapImage.splash(mapID)
				.aspectRatio(contentMode: .fill)
				.frame(height: 120)
				.clipped()
				.overlay(
					LinearGradient(
						colors: [.black.opacity(0.15), .black.opacity(0.82)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
			
			VStack(alignment: .leading, spacing: 3) {
				Text("CUSTOM GAME")
					.font(.caption2.weight(.bold))
					.tracking(0.8)
					.foregroundStyle(Color.accentColor)
				
				Text(mapDisplayName(settings.map))
					.font(.title2.bold())
					.foregroundStyle(.white)
				
				Text("\(modeDisplayName(settings.mode)) · \(serverDisplayName(settings.gamePod))")
					.font(.caption)
					.foregroundStyle(.white.opacity(0.8))
			}
			.padding(14)
		}
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var matchSetupCard: some View {
		VStack(spacing: 0) {
			HStack(spacing: 14) {
				Image(systemName: "map")
					.font(.body.weight(.medium))
					.foregroundStyle(Color.accentColor)
					.frame(width: 24)
				
				Text("Map")
				
				Spacer()
				
				// Menu Map
				Menu {
					ForEach(cachedMapOptions) { option in
						Button {
							settings.map = option.path
						} label: {
							HStack {
								Text(option.name)
								if CustomGameConfigs.mapShortName(from: option.path)
									.caseInsensitiveCompare(CustomGameConfigs.mapShortName(from: settings.map)) == .orderedSame {
									Image(systemName: "checkmark")
								}
							}
						}
					}
				} label: {
					HStack(spacing: 6) {
						Text(mapDisplayName(settings.map))
						Image(systemName: "chevron.up.chevron.down")
							.font(.caption.weight(.semibold))
					}
					.foregroundStyle(Color.accentColor)
				}
				.disabled(!canEdit || cachedMapOptions.isEmpty)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			
			Divider()
				.padding(.leading, 54)
			
			HStack(spacing: 14) {
				Image(systemName: "flag.2.crossed")
					.font(.body.weight(.medium))
					.foregroundStyle(Color.accentColor)
					.frame(width: 24)
				
				Text("Mode")
				
				Spacer()
				
				// Menu Mode
				Menu {
					ForEach(cachedModeOptions) { option in
						Button {
							settings.mode = option.path
							ensureValidMapForCurrentMode()
							rebuildCachedOptions()
						} label: {
							HStack {
								Text(option.name)
								if CustomGameConfigs.modeShortName(from: option.path)
									.caseInsensitiveCompare(CustomGameConfigs.modeShortName(from: settings.mode)) == .orderedSame {
									Image(systemName: "checkmark")
								}
							}
						}
					}
				} label: {
					HStack(spacing: 6) {
						Text(modeDisplayName(settings.mode))
						Image(systemName: "chevron.up.chevron.down")
							.font(.caption.weight(.semibold))
					}
					.foregroundStyle(Color.accentColor)
				}
				.disabled(!canEdit)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			
			if !cachedPingOptions.isEmpty {
				Divider()
					.padding(.leading, 54)
				
				HStack(spacing: 14) {
					Image(systemName: "server.rack")
						.font(.body.weight(.medium))
						.foregroundStyle(Color.accentColor)
						.frame(width: 24)
					
					Text("Server")
					
					Spacer()
					
					Menu {
						ForEach(cachedPingOptions) { option in
							Button {
								settings.gamePod = option.ping.serverID
							} label: {
								HStack {
									Text("\(option.name) (\(option.ping.ping) ms)")
									if option.ping.serverID == settings.gamePod { Image(systemName: "checkmark") }
								}
							}
						}
					} label: {
						HStack(spacing: 6) {
							Text(serverDisplayName(settings.gamePod))
							Image(systemName: "chevron.up.chevron.down")
								.font(.caption.weight(.semibold))
						}
						.foregroundStyle(Color.accentColor)
					}
					.disabled(!canEdit)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 14)
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var gameRulesCard: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Game Options")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 6)
			
			VStack(spacing: 0) {
				ruleToggle(title: "Allow Cheats", icon: "wand.and.stars", isOn: $rules.allowCheats)
				Divider().padding(.leading, 54)
				ruleToggle(title: "Tournament Mode", icon: "trophy", isOn: $rules.tournamentModeEnabled)
				Divider().padding(.leading, 54)
				ruleToggle(title: "Overtime: Win by Two", icon: "arrow.triangle.2.circlepath", isOn: $rules.overtimeWinByTwo)
				Divider().padding(.leading, 54)
				ruleToggle(title: "Play Out All Rounds", icon: "repeat", isOn: $rules.playOutAllRoundsEnabled)
				Divider().padding(.leading, 54)
				ruleToggle(title: "Hide Match History", icon: "eye.slash", isOn: $rules.hideMatchHistory)
			}
			.disabled(!canEdit)
			.opacity(canEdit ? 1 : 0.65)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func ruleToggle(title: LocalizedStringKey, icon: String, isOn: Binding<Bool>) -> some View {
		Toggle(isOn: isOn) {
			HStack(spacing: 14) {
				Image(systemName: icon)
					.font(.body.weight(.medium))
					.foregroundStyle(Color.accentColor)
					.frame(width: 24)
				Text(title)
			}
		}
		.tint(Color.accentColor)
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
	}
	
	private var exitCustomLobbyButton: some View {
		Button {
			returnToStandardLobby()
		} label: {
			HStack {
				Spacer()
				if isReturningToStandard {
					ProgressView()
				} else {
					Label("Switch to Standard Queue", systemImage: "arrow.uturn.backward")
						.font(.body.weight(.semibold))
						.foregroundStyle(Color.accentColor)
				}
				Spacer()
			}
			.padding(.vertical, 14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.buttonStyle(.plain)
		.disabled(!canEdit)
	}
	
	private func resolvedMapInfo(for path: String) -> MapInfo? {
		assets?.mapInfo(for: path)
	}
	
	private func mapDisplayName(_ path: String) -> String {
		guard !path.isEmpty else { return String(localized: "Select Map") }
		if let info = resolvedMapInfo(for: path) {
			return info.displayName
		}
		return path.split(separator: "/").last.map(String.init) ?? path
	}
	
	private func modeDisplayName(_ path: String) -> String {
		assets?.customModeDisplayName(for: path)
			?? AssetCollection.fallbackCustomModeDisplayName(for: path)
	}
	
	private func serverDisplayName(_ podID: String) -> String {
		guard !podID.isEmpty else { return String(localized: "Default") }
		return assets?.serverDisplayName(for: podID)
			?? MatchAnalytics.parseServerName(from: podID)
			?? podID
	}

	private func canonicalize(_ target: inout Party.CustomGameData.Settings, fallbackToAscentIfEmpty: Bool) {
		let modeFolders = assets?.modeFoldersByShortName ?? [:]
		let mapLookup = assets?.canonicalMapPathsByShortName ?? [:]
		let modes = computeSelectableModePaths()
		if target.mode.isEmpty {
			target.mode = modes.first(where: {
				CustomGameConfigs.modeShortName(from: $0).caseInsensitiveCompare("BombGameMode") == .orderedSame
			}) ?? modes.first ?? Self.fallbackModes[0]
		} else {
			let currentModeShort = CustomGameConfigs.modeShortName(from: target.mode)
			if let canonicalMode = modes.first(where: {
				CustomGameConfigs.modeShortName(from: $0).caseInsensitiveCompare(currentModeShort) == .orderedSame
			}) {
				target.mode = canonicalMode
			} else {
				target.mode = CustomGameConfigs.canonicalModePath(
					for: target.mode,
					knownModeFoldersByShortName: modeFolders
				)
			}
		}
		
		let validMaps = computeValidMapPaths(for: target.mode)
		let currentMapShort = CustomGameConfigs.mapShortName(from: target.map)
		if let exactMatch = validMaps.first(where: {
			CustomGameConfigs.mapShortName(from: $0).caseInsensitiveCompare(currentMapShort) == .orderedSame
		}) {
			target.map = exactMatch
		} else if let firstValid = validMaps.first {
			target.map = firstValid
		} else if !target.map.isEmpty {
			target.map = CustomGameConfigs.canonicalMapPath(
				for: target.map,
				knownMapPathsByShortName: mapLookup
			)
		} else if fallbackToAscentIfEmpty {
			target.map = MapID.ascent.rawValue
		}
	}
	
	private func ensureValidMapForCurrentMode() {
		canonicalize(&settings, fallbackToAscentIfEmpty: false)
	}
	
	private func saveSettings() {
		var updated = settings
		updated.gameRules = rules
		canonicalize(&updated, fallbackToAscentIfEmpty: true)
		
		if updated.gamePod.isEmpty {
			updated.gamePod = cachedPingOptions.first?.ping.serverID
				?? selfPings.min(by: { $0.ping < $1.ping })?.serverID
				?? party.matchmakingData.preferredGamePods.first
				?? ""
		}

		Task {
			isSaving = true
			defer { isSaving = false }
			var saved = false
			await load {
				party = try await $0.setCustomGameSettings(updated, in: party.id)
				saved = true
			}
			if saved {
				dismiss()
			}
		}
	}
	
	private func returnToStandardLobby() {
		let targetQueue = party.eligibleQueues?.first(where: { $0 == .unrated })
			?? party.eligibleQueues?.first(where: { $0 != .custom })
			?? .unrated
		Task {
			isReturningToStandard = true
			defer { isReturningToStandard = false }
			var didReset = false
			await load {
				party = try await $0.makeDefaultQueue(targetQueue, in: party.id)
				didReset = true
			}
			if didReset {
				dismiss()
			}
		}
	}
}
