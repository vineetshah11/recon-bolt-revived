import SwiftUI

struct AboutScreen: View {
	var body: some View {
		List {
			Text("""
				Recon Bolt was originally created in October 2022 as a companion app for Valorant, helping players check hidden RR changes, match history, live lobbies, agent select, store offers, missions, loadouts, and detailed stats.

				Development was forced to stop after legal threats from Riot in 2024, even though Riot had reviewed and approved the app two years earlier. Without updates, Riot's API changes throughout 2024 gradually broke the app until users could no longer connect.

				Recon Bolt Revived is brought back to life and maintained by Vineet and DT, who rebuilt Riot WebView OAuth and 2FA login, repaired the broken API endpoints, added the newer weapons and Gauntlet support, and unlocked Pro features by default. Vantage is the Valpaw edition of that revival, and they keep it running today.
				""", comment: "About Screen"
			)

			Section(header: Text("Links", comment: "About Screen: section")) {
				ListLink("GitHub Repo", icon: "chevron.left.forwardslash.chevron.right", destination: "https://github.com/vineetshah11/recon-bolt-revived")
				ListLink("Vineet's GitHub", icon: "person.crop.circle", destination: "https://github.com/vineetshah11")
				ListLink("DT's Page", icon: "person.crop.circle", destination: "https://guns.lol/dt.l21")
				ListLink("Original Creator Page", destination: "https://juliand665.com/")
			}

			Section(header: Text("Credits", comment: "About Screen: section")) {
				Text("Originally created by [Julian Dunskus (juliand665)](https://juliand665.com/), who designed and built Recon Bolt and its API layer.")

				Text("Revived and maintained by [DT (Timothy Maume)](https://guns.lol/dt.l21), who rebuilt Riot authentication with WebView OAuth and 2FA, repaired the broken API endpoints, and added the newer weapons, Gauntlet support, and Pro features.")

				Text("Extended and maintained for Valpaw by [Vineet (vineetshah11)](https://github.com/vineetshah11).")

				Text("You can find DT and Vineet on Discord as dt.l21 and vineetshah_11.", comment: "About Screen: credits")

				VStack(alignment: .leading, spacing: 8) {
					Link("Valorant-API.com" as String, destination: URL(string: "https://valorant-api.com")!)
					Text("An invaluable API hosting all the assets (images, data, etc.) used throughout Valorant. This is where almost every image in the app comes from.", comment: "About Screen")
				}
			}

			Section(header: Text("Legal", comment: "About Screen: section")) {
				Text("""
					Vantage isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Valorant. Valorant and Riot Games are trademarks or registered trademarks of Riot Games, Inc. © Riot Games, Inc.
					""", comment: "About Screen: legal disclaimer"
				)
				.font(.footnote)
				.foregroundStyle(.secondary)
			}
		}
		.navigationTitle("About")
	}
}

struct ListLink: View {
	var label: LocalizedStringKey
	var icon: String?
	var destination: URL
	
	init(_ label: LocalizedStringKey, icon: String? = nil, destination: String) {
		self.label = label
		self.destination = .init(string: destination)!
		self.icon = icon
	}
	
	var body: some View {
		Link(destination: destination) {
			NavigationLink {} label: {
				Label(label, systemImage: icon ?? "link")
			}
			.tint(.primary)
		}
	}
}

#if DEBUG
struct AboutScreen_Previews: PreviewProvider {
    static var previews: some View {
        AboutScreen()
			.withToolbar()
    }
}
#endif
