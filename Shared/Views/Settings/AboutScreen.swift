import SwiftUI

struct AboutScreen: View {
	var body: some View {
		List {
			Text("""
				Recon Bolt is an unofficial Valorant companion for your iPhone — check your match history and rank, follow your live game, peek at your daily store, and browse your loadout and the full agent, map, and skin reference, all without alt-tabbing. It's a personal revival project, not made or endorsed by Riot, sideloaded via AltStore just for fun.
				""", comment: "About Screen"
			)

			Section(header: Text("Links", comment: "About Screen: section")) {
				ListLink("GitHub Repo", icon: "chevron.left.forwardslash.chevron.right", destination: "https://github.com/vineetshah11/recon-bolt-revived")
				ListLink("Valorant-API.com", icon: "photo.on.rectangle", destination: "https://valorant-api.com")
			}

			Section(header: Text("Legal", comment: "About Screen: section")) {
				Text("""
					Recon Bolt isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Valorant. Valorant and Riot Games are trademarks or registered trademarks of Riot Games, Inc. © Riot Games, Inc.
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
