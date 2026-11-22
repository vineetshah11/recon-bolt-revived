import SwiftUI

struct MatchRetentionView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var settings: AppSettings
	
	@EnvironmentObject private var bookmarkList: BookmarkList
	
	@State private var confirmDeleteUnlinked = false
	@State private var confirmDeleteAll = false
	@State private var resultMessage: String?
	@State private var isDeleting = false
	
	private let retentionOptions: [(days: Int, label: String)] = [
		(0, "Off"),
		(3, "3 Days"),
		(7, "7 Days"),
		(14, "14 Days"),
		(30, "30 Days"),
		(60, "60 Days"),
	]
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "clock.badge.xmark",
					title: "Auto-Delete Matches",
					subtitle: "Automatically delete downloaded match details after a set time to keep storage in check."
				)
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("Delete After")
					
					SettingsCard {
						ForEach(Array(retentionOptions.enumerated()), id: \.element.days) { index, option in
							Button {
								settings.matchRetentionDays = option.days
								triggerPrune()
							} label: {
								HStack {
									Text(option.label)
										.font(.body)
										.foregroundStyle(.primary)
									
									Spacer()
									
									if settings.matchRetentionDays == option.days {
										Image(systemName: "checkmark")
											.font(.body.weight(.semibold))
											.foregroundStyle(.tint)
									}
								}
								.padding(.horizontal, 16)
								.padding(.vertical, 14)
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
							
							if index < retentionOptions.count - 1 {
								SettingsRowDivider(leadingInset: 16)
							}
						}
					}
					
					SettingsFooter("Matches are deleted after the selected time unless they're always kept. This limits how far back Statistics can analyze your games.")
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("Always Keep")
					
					SettingsCard {
						keepToggleRow(icon: "person.crop.circle", title: "My Accounts", isOn: $settings.keepsOwnMatches)
						SettingsRowDivider()
						keepToggleRow(icon: "bookmark", title: "Bookmarked Players", isOn: $settings.keepsBookmarkedMatches)
						SettingsRowDivider()
						keepToggleRow(icon: "person.2.slash", title: "Unlinked Matches", isOn: $settings.keepsUnlinkedMatches)
					}
					
					SettingsFooter("Matches in these categories are never auto-deleted. Unlinked matches don't appear in the match history of any account or bookmarked player.")
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("Delete Manually")
					
					SettingsCard {
						Button {
							confirmDeleteUnlinked = true
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "person.2.slash")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Delete Unlinked Matches")
									.font(.body)
									.foregroundStyle(.tint)
								
								Spacer()
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.disabled(isDeleting)
						
						SettingsRowDivider()
						
						Button {
							confirmDeleteAll = true
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "trash")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Delete All Matches")
									.font(.body)
									.foregroundStyle(.tint)
								
								Spacer()
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.disabled(isDeleting)
					}
					
					SettingsFooter("Deletes downloaded matches right away, regardless of the settings above. Storage usage by player is shown in Matches and Downloads.")
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Auto-Delete")
		.navigationBarTitleDisplayMode(.inline)
		.confirmationDialog(
			"Delete Unlinked Matches",
			isPresented: $confirmDeleteUnlinked,
			titleVisibility: .visible
		) {
			Button("Delete Unlinked Matches", role: .destructive) {
				deleteUnlinked()
			}
		} message: {
			Text("Removes downloaded matches that do not appear in the match history of any signed-in account or bookmarked player.")
		}
		.confirmationDialog(
			"Delete All Matches",
			isPresented: $confirmDeleteAll,
			titleVisibility: .visible
		) {
			Button("Delete All Matches", role: .destructive) {
				deleteAll()
			}
		} message: {
			Text("Removes every downloaded match detail from this device. They can be re-downloaded later if still in Riot's match history.")
		}
		.alert("Matches Deleted", isPresented: Binding(
			get: { resultMessage != nil },
			set: { if !$0 { resultMessage = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			if let resultMessage {
				Text(resultMessage)
			}
		}
	}
	
	private func keepToggleRow(icon: String, title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
		Toggle(isOn: isOn) {
			HStack(spacing: 14) {
				Image(systemName: icon)
					.font(.system(size: 18))
					.foregroundStyle(.tint)
					.frame(width: 24)
				
				Text(title)
					.font(.body)
					.foregroundStyle(.primary)
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.onChange(of: isOn.wrappedValue) { _ in
			triggerPrune()
		}
	}
	
	private func triggerPrune() {
		Task {
			_ = await MatchRetentionManager.pruneIfEnabled(
				settings: settings,
				accountManager: accountManager,
				bookmarkList: bookmarkList
			)
		}
	}
	
	private func deleteUnlinked() {
		isDeleting = true
		Task {
			defer { isDeleting = false }
			do {
				let count = try await MatchRetentionManager.deleteUnlinkedMatches(
					accountManager: accountManager,
					bookmarkList: bookmarkList
				)
				resultMessage = count == 0
					? "No unlinked matches were found on this device."
					: "Deleted \(count) unlinked match\(count == 1 ? "" : "es")."
			} catch {
				resultMessage = error.localizedDescription
			}
		}
	}
	
	private func deleteAll() {
		isDeleting = true
		Task {
			defer { isDeleting = false }
			do {
				try await MatchRetentionManager.deleteAllMatches()
				resultMessage = "Deleted all downloaded match details from this device."
			} catch {
				resultMessage = error.localizedDescription
			}
		}
	}
}
