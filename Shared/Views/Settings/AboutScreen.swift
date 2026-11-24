import SwiftUI

/// Bundle-backed version info, shared by About, the patch notes, and the request log.
enum AppVersion {
	static var short: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
	}
	
	static var build: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
	}
	
	static var display: String {
		"\(short) (\(build))"
	}
}

/// One shipped release: what changed, how to confirm it, and what the previous version already had.
struct AppRelease: Identifiable {
	struct Change: Identifiable {
		var title: String
		var detail: String
		/// The quickest way to confirm this change in the build you installed.
		var check: String?
		
		var id: String { title }
	}
	
	var version: String
	/// nil for older builds we only know by their feature set.
	var date: String?
	var summary: String
	var changes: [Change]
	/// Features that were already present before this release, so a look-back knows the baseline.
	var baseline: [String]
	
	var id: String { version }
	
	var isInstalled: Bool {
		version == AppVersion.short
	}
}

enum ReleaseNotes {
	/// Newest first. Bump the app's MARKETING_VERSION and add an entry here for every build.
	static let releases: [AppRelease] = [
		AppRelease(
			version: "1.5",
			date: "24 Nov 2026",
			summary: "Adds a spike timer to Live Match and makes instalock stop retrying forever.",
			changes: [
				.init(
					title: "Spike Planted countdown",
					detail: "A manual 45-second countdown now sits under the map on Live Match. Tap the row when you plant: it switches to tenths for the last 10 seconds (9.9 down to 0.0), pulses amber at 7s and red at 3.5s, then detonates with a blast animation and a heavy haptic.",
					check: "Open a live match and tap Spike Planted. The readout should run 9.9 → 0.0 and end on the red Detonated row. Tap the row again to restart, or the ✕ to cancel."
				),
				.init(
					title: "Instalock retries once, then stops",
					detail: "Instalock waits a random 0.2–1.0s before its first lock-in so it doesn't always fire at the same instant. If Riot rejects that attempt it waits 3 seconds and tries exactly once more, then gives up instead of retrying on every one-second refresh.",
					check: "Enable Instalock Agent, queue into agent select, and confirm your agent locks. With the request log open you should see at most two lock-in requests per attempt."
				),
			],
			baseline: [ // deliberately empty for the current release
			]
		),
		AppRelease(
			version: "1.4",
			date: nil,
			summary: "The Vantage build that came before the spike timer and the instalock retry.",
			changes: [],
			baseline: [
				"Live match, scoreboard, and round stats",
				"Agent select with manual picks",
				"Store, missions, loadouts, and career stats",
				"Riot WebView OAuth and 2FA login",
				"Newer weapons and Gauntlet support",
			]
		),
	]
	
	static var installed: AppRelease? {
		releases.first { $0.isInstalled }
	}
	
	/// The release the user most likely came from, e.g. for a \"what's new since…\" line.
	static var previous: AppRelease? {
		guard let index = releases.firstIndex(where: \.isInstalled) else { return nil }
		let next = releases.index(after: index)
		return next < releases.endIndex ? releases[next] : nil
	}
}

struct ReleaseNotesView: View {
	var body: some View {
		List {
			Section {
				LabeledRow("Installed", describing: AppVersion.display)
				
				if let previous = ReleaseNotes.previous {
					LabeledRow("Previous", describing: previous.version)
				}
			} footer: {
				Text("Everything below is per release, so you can see what changed since the version you were on.")
			}
			
			ForEach(ReleaseNotes.releases) { release in
				Section {
					ForEach(release.changes) { change in
						changeRow(change)
					}
					
					if release.changes.isEmpty {
						ForEach(release.baseline, id: \.self) { item in
							Label {
								Text(item)
									.font(.footnote)
							} icon: {
								Image(systemName: "smallcircle.filled.circle")
									.font(.caption2)
									.foregroundStyle(.secondary)
							}
						}
					}
					
					Text(release.summary)
						.font(.footnote)
						.foregroundStyle(.secondary)
				} header: {
					releaseHeader(release)
				} footer: {
					if !release.changes.isEmpty, !release.baseline.isEmpty {
						Text("Already in the previous build: \(release.baseline.joined(separator: "; ")).")
					}
				}
			}
		}
		.navigationTitle("Patch Notes")
	}
	
	private func changeRow(_ change: AppRelease.Change) -> some View {
		VStack(alignment: .leading, spacing: 5) {
			Text(change.title)
				.font(.subheadline.weight(.semibold))
			
			Text(change.detail)
				.font(.footnote)
				.foregroundStyle(.secondary)
			
			if let check = change.check {
				Label {
					Text(check)
						.font(.caption)
				} icon: {
					Image(systemName: "checkmark.circle")
						.font(.caption)
						.foregroundStyle(.tint)
				}
				.padding(.top, 2)
			}
		}
		.padding(.vertical, 2)
	}
	
	private func releaseHeader(_ release: AppRelease) -> some View {
		HStack(spacing: 6) {
			Text("Version \(release.version)")
			
			if let date = release.date {
				Text("· \(date)")
			}
			
			if release.isInstalled {
				Text("Installed")
					.font(.caption2.weight(.bold))
					.foregroundStyle(.white)
					.padding(.horizontal, 6)
					.padding(.vertical, 2)
					.background(Capsule().fill(Color.accentColor))
			}
		}
	}
}

struct AboutScreen: View {
	var body: some View {
		List {
			Section(header: Text("Version", comment: "About Screen: section")) {
				LabeledRow("Installed", describing: AppVersion.display)
				
				NavigationLink {
					ReleaseNotesView()
				} label: {
					Label("Patch Notes", systemImage: "list.bullet.rectangle")
				}
				
				Text("Patch notes list every release with what changed and what to check, so you can compare against the version you were on.", comment: "About Screen: patch notes explanation")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			
			Text("""
				Recon Bolt was originally created in October 2022 as a companion app for Valorant, helping players check hidden RR changes, match history, live lobbies, agent select, store offers, missions, loadouts, and detailed stats.

				Development was forced to stop after legal threats from Riot in 2024, even though Riot had reviewed and approved the app two years earlier. Without updates, Riot's API changes throughout 2024 gradually broke the app until users could no longer connect.

				Recon Bolt Revived / Vantage is brought back to life and maintained by Vineet and DT, who rebuilt Riot WebView OAuth and 2FA login, repaired the broken API endpoints, added the newer weapons and Gauntlet support, and unlocked Pro features by default. Vantage is the Valpaw edition of that revival, and they keep it running today.
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
		
		ReleaseNotesView()
			.withToolbar()
			.previewDisplayName("Patch Notes")
    }
}
#endif
