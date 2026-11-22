import SwiftUI

struct StorageView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	
	@EnvironmentObject private var bookmarkList: BookmarkList
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@StateObject private var storageManager = StorageManager()
	
	@State private var breakdown = StorageBreakdown()
	@State private var isLoaded = false
	
	@State private var confirmRemoveAccounts = false
	@State private var confirmDeleteBookmarks = false
	@State private var confirmDeletePresets = false
	@State private var confirmResetSettings = false
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				summaryCard
				
				SettingsCard {
					NavigationLink {
						AssetStorageView(assetManager: assetManager)
					} label: {
						HStack(spacing: 14) {
							Image(systemName: "cube")
								.font(.system(size: 18))
								.foregroundStyle(.tint)
								.frame(width: 24)
							
							Text("Game Assets")
								.font(.body)
								.foregroundStyle(.primary)
							
							Spacer()
							
							Text(breakdown.gameAssetsBytes, format: .byteCount(style: .file))
								.font(.body.monospacedDigit())
								.foregroundStyle(.secondary)
							
							Image(systemName: "chevron.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					
					SettingsRowDivider()
					
					NavigationLink {
						StorageManagementView(manager: storageManager, accountManager: accountManager)
							.withLoadErrorAlerts()
					} label: {
						HStack(spacing: 14) {
							Image(systemName: "internaldrive")
								.font(.system(size: 18))
								.foregroundStyle(.tint)
								.frame(width: 24)
							
							VStack(alignment: .leading, spacing: 2) {
								Text("Matches and Downloads")
									.font(.body)
									.foregroundStyle(.primary)
								
								Text(breakdown.matchesAndDownloadsBytes, format: .byteCount(style: .file))
									.font(.footnote.monospacedDigit())
									.foregroundStyle(.secondary)
							}
							
							Spacer()
							
							Image(systemName: "chevron.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 12)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					
					SettingsRowDivider()
					
					NavigationLink {
						MatchRetentionView(accountManager: accountManager, settings: settings)
					} label: {
						HStack(spacing: 14) {
							Image(systemName: "clock.badge.xmark")
								.font(.system(size: 18))
								.foregroundStyle(.tint)
								.frame(width: 24)
							
							Text("Auto-Delete Matches")
								.font(.body)
								.foregroundStyle(.primary)
							
							Spacer()
							
							Text(settings.matchRetentionLabel)
								.font(.body)
								.foregroundStyle(.secondary)
							
							Image(systemName: "chevron.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("Your Data")
					
					SettingsCard {
						destructiveCountRow(
							icon: "person.crop.circle.badge.minus",
							title: "Remove All Accounts",
							count: accountManager.storedAccounts.count
						) {
							confirmRemoveAccounts = true
						}
						
						SettingsRowDivider()
						
						destructiveCountRow(
							icon: "bookmark.slash",
							title: "Delete All Bookmarks",
							count: bookmarkList.bookmarks.count
						) {
							confirmDeleteBookmarks = true
						}
						
						SettingsRowDivider()
						
						destructiveCountRow(
							icon: "square.3.layers.3d.slash",
							title: "Delete Loadout Presets",
							count: presetManager.presets.count
						) {
							confirmDeletePresets = true
						}
						
						SettingsRowDivider()
						
						Button {
							confirmResetSettings = true
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "arrow.counterclockwise")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Reset App Settings")
									.font(.body)
									.foregroundStyle(.tint)
								
								Spacer()
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 14)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
					
					SettingsFooter("Vantage keeps them only on this device and does not back them up to iCloud. Deleting Vantage deletes them too.")
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Storage and Data")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await reloadBreakdown()
		}
		.onAppear {
			Task { await reloadBreakdown() }
		}
		.confirmationDialog("Remove All Accounts?", isPresented: $confirmRemoveAccounts, titleVisibility: .visible) {
			Button("Remove All Accounts", role: .destructive) {
				accountManager.clear()
				Task { await reloadBreakdown() }
			}
		} message: {
			Text("Signs out of all Riot accounts stored on this device.")
		}
		.confirmationDialog("Delete All Bookmarks?", isPresented: $confirmDeleteBookmarks, titleVisibility: .visible) {
			Button("Delete All Bookmarks", role: .destructive) {
				bookmarkList.clearAll()
				Task { await reloadBreakdown() }
			}
		} message: {
			Text("Removes all bookmarked players from your list.")
		}
		.confirmationDialog("Delete Loadout Presets?", isPresented: $confirmDeletePresets, titleVisibility: .visible) {
			Button("Delete Loadout Presets", role: .destructive) {
				presetManager.deleteAll()
				Task { await reloadBreakdown() }
			}
		} message: {
			Text("Deletes all saved loadout presets from this device.")
		}
		.confirmationDialog("Reset App Settings?", isPresented: $confirmResetSettings, titleVisibility: .visible) {
			Button("Reset App Settings", role: .destructive) {
				settings.resetAll()
			}
		} message: {
			Text("Restores all interface, sign-in, accent color, and auto-delete preferences to their defaults.")
		}
	}
	
	private var summaryCard: some View {
		SettingsCard {
			VStack(alignment: .leading, spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					Text(breakdown.totalBytes, format: .byteCount(style: .file))
						.font(.title2.bold().monospacedDigit())
						.opacity(isLoaded ? 1 : 0.6)
					
					Text("Used by Vantage on this device")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				
				storageBar
				
				VStack(alignment: .leading, spacing: 6) {
					HStack(spacing: 14) {
						legendItem(color: .blue, title: "Game Assets")
						legendItem(color: .orange, title: "Matches")
						legendItem(color: .cyan, title: "Player Profiles")
					}
					HStack(spacing: 14) {
						legendItem(color: .purple, title: "Cached Images")
						legendItem(color: .red, title: "Only on This Device")
					}
				}
			}
			.padding(16)
		}
	}
	
	private var storageBar: some View {
		let segments: [(bytes: Int64, color: Color)] = [
			(breakdown.gameAssetsBytes, .blue),
			(breakdown.matchesBytes, .orange),
			(breakdown.playerProfilesBytes, .cyan),
			(breakdown.cachedImagesBytes, .purple),
			(breakdown.deviceOnlyBytes, .red),
		]
		let total = max(1, breakdown.totalBytes)
		
		return GeometryReader { geo in
			let nonZero = segments.filter { $0.bytes > 0 }
			if nonZero.isEmpty {
				Capsule()
					.fill(Color.secondary.opacity(0.22))
			} else {
				HStack(spacing: 1) {
					ForEach(Array(nonZero.enumerated()), id: \.offset) { _, seg in
						let fraction = CGFloat(seg.bytes) / CGFloat(total)
						Rectangle()
							.fill(seg.color)
							.frame(width: max(4, geo.size.width * fraction))
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.secondary.opacity(0.18))
				.clipShape(Capsule())
			}
		}
		.frame(height: 14)
	}
	
	private func legendItem(color: Color, title: LocalizedStringKey) -> some View {
		HStack(spacing: 6) {
			Circle()
				.fill(color)
				.frame(width: 7, height: 7)
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}
	
	private func destructiveCountRow(
		icon: String,
		title: LocalizedStringKey,
		count: Int,
		action: @escaping () -> Void
	) -> some View {
		let isDisabled = count == 0
		return Button(action: action) {
			HStack(spacing: 14) {
				Image(systemName: icon)
					.font(.system(size: 18))
					.foregroundStyle(isDisabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
					.frame(width: 24)
				
				Text(title)
					.font(.body)
					.foregroundStyle(isDisabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
				
				Spacer()
				
				Text("\(count)")
					.font(.body.monospacedDigit())
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(isDisabled)
	}
	
	@MainActor
	private func reloadBreakdown() async {
		breakdown = await StorageBreakdown.compute(assetManager: assetManager)
		isLoaded = true
	}
}
