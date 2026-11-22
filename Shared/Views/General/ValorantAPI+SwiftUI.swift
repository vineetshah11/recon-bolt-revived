import SwiftUI
import ValorantAPI
import ArrayBuilder

extension Team.ID {
	static let gauntletPalette: [Color] = [
		Color(red: 190 / 255, green: 56 / 255, blue: 255 / 255), // 1: Purple Corgis
		Color(red: 24 / 255, green: 226 / 255, blue: 255 / 255), // 2: Cyan Sloths
		Color(red: 255 / 255, green: 110 / 255, blue: 18 / 255), // 3: Orange Bears
		Color(red: 52 / 255, green: 108 / 255, blue: 255 / 255), // 4: Blue Penguins
		Color(red: 255 / 255, green: 45 / 255, blue: 95 / 255),  // 5: Red Elephants
		Color(red: 95 / 255, green: 232 / 255, blue: 22 / 255),  // 6: Green Octopi
		Color(red: 255 / 255, green: 65 / 255, blue: 235 / 255), // 7: Pink Rabbits
		Color(red: 255 / 255, green: 206 / 255, blue: 18 / 255), // 8: Yellow Squirrels
	]
	
	private static let gauntletTeamNames: [String] = [
		"Purple Corgis",
		"Cyan Sloths",
		"Orange Bears",
		"Blue Penguins",
		"Red Elephants",
		"Green Octopi",
		"Pink Rabbits",
		"Yellow Squirrels",
	]
	
	/// 1-based Gauntlet team slot (`1...8`) when `rawID` is `"Team_1"`..`"Team_N"`.
	var gauntletSlotIndex: Int? {
		let lowercased = rawID.lowercased()
		guard
			lowercased.hasPrefix("team_"),
			let number = Int(lowercased.dropFirst("team_".count)),
			number > 0
		else { return nil }
		return ((number - 1) % Self.gauntletPalette.count) + 1
	}
	
	var gauntletDisplayName: String? {
		guard let slot = gauntletSlotIndex else { return nil }
		return Self.gauntletTeamNames[slot - 1]
	}
	
	var gauntletMascotAssetName: String? {
		guard let slot = gauntletSlotIndex else { return nil }
		return "gauntlet/mascot_\(slot)"
	}
	
	func gauntletRoboAssetName(isOVariant: Bool = true, isKillfeed: Bool = false) -> String? {
		let slot = gauntletSlotIndex ?? 1
		let variant = isOVariant ? "o" : "x"
		let suffix = isKillfeed ? "_killfeed" : ""
		return "gauntlet/robo_\(slot)_\(variant)\(suffix)"
	}
	
	static func isGauntletOVariant(for playerID: Player.ID, teamID: Team.ID, in players: [Player]) -> Bool {
		let teammates = players
			.filter { $0.teamID == teamID }
			.sorted {
				if $0.score != $1.score {
					return $0.score > $1.score
				}
				return $0.id.description < $1.id.description
			}
		guard let index = teammates.firstIndex(where: { $0.id == playerID }) else { return true }
		return index % 2 == 0
	}
	
	var color: Color? {
		let lowercased = rawID.lowercased()
		switch lowercased {
		case "blue":
			return .valorantBlue
		case "red":
			return .valorantRed
		case "green":
			return Self.gauntletPalette[5]
		case "yellow":
			return Self.gauntletPalette[7]
		case "purple":
			return Self.gauntletPalette[0]
		case "orange":
			return Self.gauntletPalette[2]
		case "pink", "magenta":
			return Self.gauntletPalette[6]
		case "teal":
			return .teal
		case "cyan":
			return Self.gauntletPalette[1]
		case "neutral":
			return .gray
		default:
			if let slot = gauntletSlotIndex {
				return Self.gauntletPalette[slot - 1]
			}
			return nil
		}
	}
}

extension Color {
	private static let multiTeamPalette: [Color] = Team.ID.gauntletPalette + [
		.indigo,
		.mint,
		.brown,
		.teal,
	]
	
	static func assignedTeamColors(for teamIDs: [Team.ID], ownTeamID: Team.ID?) -> [Team.ID: Color] {
		var result: [Team.ID: Color] = [:]
		
		for id in teamIDs {
			if let explicit = id.color {
				result[id] = explicit
			} else if id == ownTeamID {
				result[id] = .valorantBlue
			}
		}
		
		let usedExplicitColors = Set(result.values)
		let availablePalette = multiTeamPalette.filter { !usedExplicitColors.contains($0) }
		let palette = availablePalette.isEmpty ? multiTeamPalette : availablePalette
		
		var nextIndex = 0
		for id in teamIDs where result[id] == nil {
			result[id] = palette[nextIndex % palette.count]
			nextIndex += 1
		}
		return result
	}
}

enum PlacementFormatter {
	private static let formatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .ordinal
		let preferred = Bundle.main.preferredLocalizations.first ?? "en_US"
		formatter.locale = Locale(identifier: preferred)
		return formatter
	}()
	
	static func ordinal(_ rank: Int) -> String {
		formatter.string(from: NSNumber(value: rank)) ?? "#\(rank)"
	}
}

extension Location: Identifiable {
	public var id: String { "\(shard):\(region)" }
}

extension Location {
	var name: String {
		switch self {
		case .europe:
			return String(localized: "Europe", table: "Locations")
		case .northAmerica:
			return String(localized: "North America", table: "Locations")
		case .korea:
			return String(localized: "Korea", table: "Locations")
		case .asiaPacific:
			return String(localized: "Asia Pacific", table: "Locations")
		case .brazil:
			return String(localized: "Brazil", table: "Locations")
		case .latinAmerica:
			return String(localized: "Latin America", table: "Locations")
		case .pbe:
			return String(localized: "PBE", table: "Locations")
		default:
			return String(localized: "Unknown Location", table: "Locations")
		}
	}
}

extension APIError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .unauthorized:
			return String(localized: "The API rejected your authorization.", table: "Errors", comment: "Riot API Error")
		case .tokenFailure(message: let message):
			return String(localized: "Your token has expired. \(message)", table: "Errors", comment: "Riot API Error")
		case .sessionExpired:
			return String(localized: "Your session has expired! Please sign in again.", table: "Errors", comment: "Riot API Error")
		case .sessionResumptionFailure(let error):
			return String(localized: "Your session could not be resumed. \(error.localizedDescription)", table: "Errors", comment: "Riot API Error")
		case .scheduledDowntime:
			return String(localized: "Valorant is currently undergoing scheduled maintenance. Riot is probably updating the game!", table: "Errors", comment: "Riot API Error")
		case .resourceNotFound:
			return String(localized: "The resource could not be found.", table: "Errors", comment: "Riot API Error")
		case .badResponseCode(400, _, let error?) where error.errorCode == "INVALID_HEADERS":
			return String(localized: "Invalid Headers: \(error.message)", table: "Errors", comment: "Riot API Error")
		case .badResponseCode(404, _, let error?) where error.errorCode == "MATCH_NOT_FOUND":
			return String(localized: "This match could not be loaded! Valorant discards match details for older matches after a few months.", table: "Errors", comment: "Riot API Error")
		case .badResponseCode(let code, _, nil):
			return String(localized: "The API returned an error code \(code).", table: "Errors", comment: "Riot API Error")
		case .badResponseCode(let code, _, let error?):
			return String(localized: "The API returned an error code \(code), i.e. \(error.errorCode). \(error.message)", table: "Errors", comment: "Riot API Error")
		case .rateLimited(retryAfter: let delay):
			return [String].build {
				String(localized: "You are sending too many requests.", table: "Errors", comment: "Riot API Error")
				delay.map { String(localized: "Please try again in \($0) seconds.", table: "Errors", comment: "Riot API Error") }
			}.joined(separator: " ")
		}
	}
}

extension CGPoint {
	public init(_ position: Position) {
		self.init(x: position.x, y: position.y)
	}
}
