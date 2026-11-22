import SwiftUI

struct AboutScreen: View {
	var body: some View {
		List {
			Text("""
				Recon Bolt was originally created in October 2022 as a companion app for Valorant, helping players check hidden RR changes, match history, live lobbies, agent select, store offers, missions, loadouts, and detailed stats.

				Development was forced to stop after legal threats from Riot in 2024, even though Riot had reviewed and approved the app two years earlier. Without updates, Riot's API changes throughout 2024 gradually broke the app until users could no longer connect.

				Recon Bolt Revived is brought back to life and maintained by Vineet and DT. Together, they revived the project with modern Riot WebView OAuth, 2FA support, restored API endpoints, newer weapons, a confirmed Dodge button, and fully unlocked Pro features.
				""", comment: "About Screen"
			)
			
			Section(header: Text("Links", comment: "About Screen: section")) {
				ListLink("GitHub Repo", destination: "https://github.com/vineetshah11/recon-bolt-revived")
				ListLink("Vineet's GitHub", destination: "https://github.com/vineetshah11")
				ListLink("DT's Page", destination: "https://guns.lol/dt.l21")
				ListLink("Original Creator Page", destination: "https://juliand665.com/")
			}
			
			Section(header: Text("Credits", comment: "About Screen: section")) {
				Text("Originally created by [Julian Dunskus](https://juliand665.com/).")
				
				VStack(alignment: .leading, spacing: 4) {
					Text("Revived & Maintained by [Vineet](https://discord.com/users/vineetshah_11) & [DT](https://guns.lol/dt.l21).")
					Text("Discord: **vineetshah_11** & **dt.l21**")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				
				VStack(alignment: .leading, spacing: 8) {
					Link("Valorant-API.com" as String, destination: URL(string: "https://valorant-api.com")!)
					Text("An invaluable API hosting all the assets (images, data, etc.) used throughout Valorant. This is where almost every image in the app comes from.", comment: "About Screen")
				}
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
