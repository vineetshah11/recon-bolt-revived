import SwiftUI
import ValorantAPI

struct PlayerSettingsSnapshotsView: View {
	@EnvironmentObject private var snapshotStore: PlayerSettingsSnapshotStore
	@EnvironmentObject private var accountManager: AccountManager
	@Environment(\.valorantLoad) private var load
	
	@State private var currentSettings: PlayerSettings?
	@State private var isLoadingCloud = false
	@State private var cloudError: String?
	@State private var showingSavePrompt = false
	@State private var newSnapshotTitle = ""
	@State private var snapshotToRestore: PlayerSettingsSnapshot?
	@State private var snapshotToRename: PlayerSettingsSnapshot?
	@State private var renameText = ""
	@State private var statusBanner: String?
	
	private var accountID: User.ID? {
		accountManager.activeAccount?.id
	}
	
	var body: some View {
		let snapshots = snapshotStore.snapshots(for: accountID)
		
		List {
			Section {
				if isLoadingCloud {
					HStack {
						ProgressView()
						Text("Checking Riot cloud settings...")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				} else if let currentSettings {
					VStack(alignment: .leading, spacing: 6) {
						Text("Cloud Settings Ready")
							.font(.headline)
						Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(currentSettings.data.utf8.count), countStyle: .file)) • Type: \(currentSettings.type)")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					.padding(.vertical, 2)
					
					Button {
						newSnapshotTitle = "Backup \(Date().formatted(date: .abbreviated, time: .shortened))"
						showingSavePrompt = true
					} label: {
						Label("Save Current Cloud Settings Snapshot", systemImage: "square.and.arrow.down")
					}
				} else if let cloudError {
					VStack(alignment: .leading, spacing: 8) {
						Text("Unavailable")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.orange)
						Text(cloudError)
							.font(.caption)
							.foregroundStyle(.secondary)
						Button {
							Task { await fetchCloudSettings() }
						} label: {
							Label("Retry", systemImage: "arrow.clockwise")
								.font(.subheadline.weight(.medium))
						}
					}
				}
			} header: {
				Text("Riot Cloud Preferences")
			} footer: {
				Text("Back up your VALORANT PC keybinds, sensitivity, crosshair profiles, and video preferences stored on Riot's servers, or restore a previous snapshot.")
			}
			
			if let statusBanner {
				Section {
					Label(statusBanner, systemImage: "checkmark.circle.fill")
						.foregroundStyle(.green)
				}
			}
			
			Section {
				if snapshots.isEmpty {
					Text("No saved snapshots yet. Pull to fetch from Riot Cloud and save a backup.")
						.foregroundStyle(.secondary)
				} else {
					ForEach(snapshots) { snapshot in
						NavigationLink {
							PlayerSettingsSnapshotDetailView(
								snapshot: snapshot,
								onRestore: { snapshotToRestore = snapshot },
								onRename: {
									snapshotToRename = snapshot
									renameText = snapshot.title
								}
							)
						} label: {
							VStack(alignment: .leading, spacing: 4) {
								Text(snapshot.title)
									.font(.headline)
								Text("\(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)) • \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.rawData.utf8.count), countStyle: .file))")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.padding(.vertical, 2)
						}
						.swipeActions(edge: .trailing) {
							Button(role: .destructive) {
								snapshotStore.delete(id: snapshot.id)
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
				}
			} header: {
				Text("Saved Snapshots (\(snapshots.count))")
			}
		}
		.navigationTitle("Player Settings")
		.refreshable {
			await fetchCloudSettings()
		}
		.task {
			if currentSettings == nil {
				await fetchCloudSettings()
			}
		}
		.alert("Save Settings Snapshot", isPresented: $showingSavePrompt) {
			TextField("Snapshot Title", text: $newSnapshotTitle)
			Button("Save") {
				if let currentSettings {
					snapshotStore.addSnapshot(
						title: newSnapshotTitle,
						rawData: currentSettings.data,
						accountID: accountID
					)
				}
			}
			Button("Cancel", role: .cancel) {}
		}
		.alert("Rename Snapshot", isPresented: Binding(
			get: { snapshotToRename != nil },
			set: { if !$0 { snapshotToRename = nil } }
		)) {
			TextField("Title", text: $renameText)
			Button("Save") {
				if let target = snapshotToRename {
					snapshotStore.rename(id: target.id, to: renameText)
				}
			}
			Button("Cancel", role: .cancel) {}
		}
		.confirmationDialog(
			"Restore Settings to Riot Cloud?",
			isPresented: Binding(
				get: { snapshotToRestore != nil },
				set: { if !$0 { snapshotToRestore = nil } }
			),
			titleVisibility: .visible
		) {
			Button("Restore Snapshot", role: .destructive) {
				if let target = snapshotToRestore {
					restore(target)
				}
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			if let target = snapshotToRestore {
				Text("This will overwrite your active Riot cloud settings with \"\(target.title)\".")
			}
		}
	}
	
	private func fetchCloudSettings() async {
		guard let client = accountManager.activeAccount?.client else {
			cloudError = "Sign in to access Riot cloud settings."
			return
		}
		isLoadingCloud = true
		cloudError = nil
		defer { isLoadingCloud = false }
		
		do {
			currentSettings = try await client.getPlayerSettings()
		} catch {
			cloudError = error.localizedDescription
		}
	}
	
	private func restore(_ snapshot: PlayerSettingsSnapshot) {
		Task {
			await load { client in
				try await client.savePlayerSettings(snapshot.rawData)
				currentSettings = PlayerSettings(data: snapshot.rawData)
				statusBanner = "Restored \"\(snapshot.title)\" to Riot Cloud."
			}
		}
	}
}

private struct PlayerSettingsSnapshotDetailView: View {
	var snapshot: PlayerSettingsSnapshot
	var onRestore: () -> Void
	var onRename: () -> Void
	
	var body: some View {
		List {
			Section {
				LabeledRow("Title", describing: snapshot.title)
				LabeledRow("Saved", describing: snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
				LabeledRow("Payload Size", describing: ByteCountFormatter.string(fromByteCount: Int64(snapshot.rawData.utf8.count), countStyle: .file))
			}
			
			Section {
				Button {
					onRestore()
				} label: {
					Label("Restore to Riot Cloud", systemImage: "icloud.and.arrow.up")
						.foregroundStyle(Color.accentColor)
				}
				
				Button {
					onRename()
				} label: {
					Label("Rename Snapshot", systemImage: "pencil")
				}
			}
			
			Section("Raw Preview") {
				Text(String(snapshot.rawData.prefix(600)))
					.font(.system(.caption2, design: .monospaced))
					.foregroundStyle(.secondary)
			}
		}
		.navigationTitle(snapshot.title)
	}
}
