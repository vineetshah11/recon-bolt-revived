import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import ValorantAPI

struct BackupImportView: View {
	let stores: BackupStores
	let initialURL: URL?
	var onImportCompleted: (() -> Void)? = nil
	
	@Environment(\.dismiss) private var dismiss
	
	private enum Stage {
		case idle
		case verifying
		case verificationFailed(String)
		case needsPassword(VerifiedBackupArchive, error: String?)
		case ready(VerifiedBackupArchive, SymmetricKey?)
		case importing
		case completed(BackupImportSummary)
	}
	
	@State private var stage: Stage = .verifying
	@State private var isShowingFileImporter = false
	@State private var passwordInput = ""
	@State private var isUnlocking = false
	
	@State private var selectedModules: Set<BackupModuleKind> = []
	@State private var selectedPlayerIDs: Set<User.ID> = []
	@State private var importMode: BackupImportMode = .merge
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				switch stage {
				case .idle:
					idleView
				case .verifying:
					progressCard(
						title: "Verifying Backup Integrity…",
						subtitle: "Checking SHA-256 hashes, HMAC, and device ECDSA signature."
					)
				case .verificationFailed(let message):
					verificationFailedView(message: message)
				case .needsPassword(let archive, let error):
					passwordPromptView(archive: archive, errorMessage: error)
				case .ready(let archive, let key):
					readyView(archive: archive, encryptionKey: key)
				case .importing:
					progressCard(
						title: "Validating & Importing Data…",
						subtitle: "Verifying plaintext checksums and sanity-checking records before writing."
					)
				case .completed(let summary):
					completedView(summary: summary)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Import Backup")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				if case .completed = stage {
					EmptyView()
				} else if case .importing = stage {
					EmptyView()
				} else {
					Button("Cancel") {
						dismiss()
					}
				}
			}
		}
		.fileImporter(
			isPresented: $isShowingFileImporter,
			allowedContentTypes: [.reconBoltBackup, .data]
		) { result in
			switch result {
			case .success(let url):
				Task { await inspect(url: url) }
			case .failure(let error):
				if case .idle = stage {
					stage = .verificationFailed(error.localizedDescription)
				}
			}
		}
		.task {
			if let initialURL {
				await inspect(url: initialURL)
			} else {
				stage = .idle
				isShowingFileImporter = true
			}
		}
	}
	
	private var idleView: some View {
		VStack(spacing: 16) {
			SettingsHeroCard(
				icon: "square.and.arrow.down",
				title: "Import .rbbackup File",
				subtitle: "Select a Recon Bolt backup file to verify its integrity and choose what to restore."
			)
			
			Button {
				isShowingFileImporter = true
			} label: {
				Label("Choose Backup File…", systemImage: "doc.badge.plus")
					.font(.headline)
					.foregroundStyle(.white)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 14)
					.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.buttonStyle(.plain)
		}
	}
	
	private func progressCard(title: String, subtitle: String) -> some View {
		SettingsCard {
			HStack(spacing: 14) {
				ProgressView()
				VStack(alignment: .leading, spacing: 4) {
					Text(title)
						.font(.headline)
					Text(subtitle)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				Spacer()
			}
			.padding(18)
		}
	}
	
	private func verificationFailedView(message: String) -> some View {
		VStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 10) {
				Image(systemName: "xmark.shield.fill")
					.font(.system(size: 32))
					.foregroundStyle(.red)
				
				Text("Import Blocked")
					.font(.title3.bold())
					.foregroundStyle(.primary)
				
				Text(message)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(18)
			.background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
			
			VStack(spacing: 12) {
				Button {
					isShowingFileImporter = true
				} label: {
					Label("Choose Another File…", systemImage: "folder")
						.font(.headline)
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 14)
						.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				}
				.buttonStyle(.plain)
				
				Button {
					dismiss()
				} label: {
					Text("Close")
						.font(.headline)
						.foregroundStyle(.primary)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 14)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				}
				.buttonStyle(.plain)
			}
		}
	}
	
	private func passwordPromptView(archive: VerifiedBackupArchive, errorMessage: String?) -> some View {
		VStack(spacing: 16) {
			trustBanner(archive: archive)
			
			SettingsCard {
				VStack(alignment: .leading, spacing: 12) {
					Label("Password Required", systemImage: "lock.fill")
						.font(.headline)
					
					Text("This archive is encrypted with AES-256-GCM. Enter the export password to unlock and verify its contents.")
						.font(.footnote)
						.foregroundStyle(.secondary)
					
					SecureField("Backup Password", text: $passwordInput)
						.textContentType(.password)
						.padding(.horizontal, 12)
						.padding(.vertical, 10)
						.background(Color.groupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
					
					if let errorMessage {
						HStack(spacing: 6) {
							Image(systemName: "exclamationmark.triangle.fill")
								.font(.caption)
							Text(errorMessage)
								.font(.caption)
						}
						.foregroundStyle(.red)
					}
					
					Button {
						unlock(archive: archive)
					} label: {
						HStack {
							if isUnlocking {
								ProgressView()
									.tint(.white)
							}
							Text(isUnlocking ? "Deriving Key…" : "Unlock Backup")
								.font(.headline)
						}
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 13)
						.background(
							passwordInput.isEmpty || isUnlocking ? Color.secondary.opacity(0.35) : Color.accentColor,
							in: RoundedRectangle(cornerRadius: 12, style: .continuous)
						)
					}
					.buttonStyle(.plain)
					.disabled(passwordInput.isEmpty || isUnlocking)
				}
				.padding(16)
			}
		}
	}
	
	private func readyView(archive: VerifiedBackupArchive, encryptionKey: SymmetricKey?) -> some View {
		let manifest = archive.manifest
		let knownDescriptors = manifest.modules.compactMap { descriptor -> (BackupModuleDescriptor, BackupModuleKind)? in
			guard let kind = descriptor.knownKind else { return nil }
			return (descriptor, kind)
		}
		let unknownModules = manifest.modules.filter { $0.knownKind == nil }
		let selectablePlayers = manifest.players.map {
			BackupSelectablePlayer(
				id: $0.id,
				gameName: $0.gameName,
				tagLine: $0.tagLine,
				role: $0.role,
				matchCount: $0.matchCount,
				estimatedBytes: nil
			)
		}
		let hasPlayerScopedModules = knownDescriptors.contains { $0.1.isPlayerScoped && selectedModules.contains($0.1) }
		let canImport = !selectedModules.isEmpty && (!hasPlayerScopedModules || !selectedPlayerIDs.isEmpty || manifest.players.isEmpty)
		
		return VStack(spacing: 16) {
			trustBanner(archive: archive)
			
			if !unknownModules.isEmpty {
				HStack(alignment: .top, spacing: 10) {
					Image(systemName: "exclamationmark.triangle.fill")
						.foregroundStyle(.orange)
						.font(.subheadline)
					Text("This archive contains \(unknownModules.count) newer module\(unknownModules.count == 1 ? "" : "s") (\(unknownModules.map(\.id).joined(separator: ", "))) not recognized by this version of Recon Bolt. They will be skipped.")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				.padding(12)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			}
			
			VStack(alignment: .leading, spacing: 8) {
				SettingsSectionHeader("Import Mode")
				
				SettingsCard {
					ForEach(Array(BackupImportMode.allCases.enumerated()), id: \.element.id) { index, mode in
						Button {
							importMode = mode
						} label: {
							HStack(alignment: .top, spacing: 12) {
								VStack(alignment: .leading, spacing: 2) {
									Text(mode.title)
										.font(.body)
										.foregroundStyle(.primary)
									Text(mode.subtitle)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								Spacer()
								if importMode == mode {
									Image(systemName: "checkmark")
										.font(.body.weight(.semibold))
										.foregroundStyle(.tint)
								}
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 12)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						
						if index < BackupImportMode.allCases.count - 1 {
							SettingsRowDivider(leadingInset: 16)
						}
					}
				}
			}
			
			if selectablePlayers.count > 1 {
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("Players in Backup")
					
					SettingsCard {
						NavigationLink {
							BackupPlayerPickerView(
								players: selectablePlayers,
								selectedPlayerIDs: $selectedPlayerIDs
							)
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "person.2")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Players to Import")
									.font(.body)
									.foregroundStyle(.primary)
								
								Spacer()
								
								Text(selectedPlayerIDs.count == selectablePlayers.count
									 ? "All (\(selectablePlayers.count))"
									 : "\(selectedPlayerIDs.count) of \(selectablePlayers.count)")
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
				}
			}
			
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					SettingsSectionHeader("Data in Archive")
					Spacer()
					let allKnown = Set(knownDescriptors.map(\.1))
					Button(selectedModules == allKnown ? "Deselect All" : "Select All") {
						if selectedModules == allKnown {
							selectedModules.removeAll()
						} else {
							selectedModules = allKnown
						}
					}
					.font(.caption.weight(.medium))
					.padding(.trailing, 8)
				}
				
				SettingsCard {
					ForEach(Array(knownDescriptors.enumerated()), id: \.element.1.id) { index, pair in
						let (descriptor, kind) = pair
						Toggle(isOn: $selectedModules.contains(kind)) {
							HStack(spacing: 14) {
								Image(systemName: kind.icon)
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								VStack(alignment: .leading, spacing: 2) {
									Text(kind.displayName)
										.font(.body)
									Text("\(descriptor.itemCount) item\(descriptor.itemCount == 1 ? "" : "s") • \(Int64(descriptor.uncompressedBytes).formatted(.byteCount(style: .file)))")
										.font(.caption.monospacedDigit())
										.foregroundStyle(.secondary)
								}
							}
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 12)
						
						if index < knownDescriptors.count - 1 {
							SettingsRowDivider()
						}
					}
				}
			}
			
			Button {
				runImport(archive: archive, encryptionKey: encryptionKey)
			} label: {
				Label(
					importMode == .replace ? "Replace & Import Backup" : "Merge & Import Backup",
					systemImage: "square.and.arrow.down.fill"
				)
				.font(.headline)
				.foregroundStyle(.white)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 15)
				.background(
					canImport ? Color.accentColor : Color.secondary.opacity(0.35),
					in: RoundedRectangle(cornerRadius: 16, style: .continuous)
				)
			}
			.buttonStyle(.plain)
			.disabled(!canImport)
		}
	}
	
	private func trustBanner(archive: VerifiedBackupArchive) -> some View {
		let isThisDevice = archive.trustStatus.isThisDevice
		let accentColor: Color = isThisDevice ? .green : .blue
		let title = isThisDevice
			? "Verified — Signed by This Device"
			: "Integrity Verified — Another Recon Bolt Device"
		
		return VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 10) {
				Image(systemName: "checkmark.shield.fill")
					.font(.system(size: 24))
					.foregroundStyle(accentColor)
				
				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.font(.headline)
					Text("Exported \(archive.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)) • App v\(archive.manifest.appVersion)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				Spacer()
			}
			
			HStack(spacing: 8) {
				Label(archive.trustStatus.fingerprint, systemImage: "key.horizontal")
					.font(.caption.monospaced())
					.foregroundStyle(.secondary)
				
				Spacer()
				
				if archive.isPasswordEncrypted {
					Label("AES-256-GCM", systemImage: "lock.fill")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(accentColor)
						.padding(.horizontal, 8)
						.padding(.vertical, 3)
						.background(accentColor.opacity(0.14), in: Capsule())
				}
			}
		}
		.padding(16)
		.background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private func completedView(summary: BackupImportSummary) -> some View {
		let sortedEntries = summary.importedCounts
			.sorted { $0.key.displayName < $1.key.displayName }
		
		return VStack(spacing: 16) {
			SettingsHeroCard(
				icon: "checkmark.circle.fill",
				title: "Import Complete",
				subtitle: "Validated and restored \(summary.totalImportedItems) item\(summary.totalImportedItems == 1 ? "" : "s") using \(summary.mode.title.lowercased())."
			)
			
			if !sortedEntries.isEmpty {
				SettingsCard {
					ForEach(Array(sortedEntries.enumerated()), id: \.element.key.id) { index, entry in
						HStack(spacing: 12) {
							Image(systemName: entry.key.icon)
								.font(.system(size: 16))
								.foregroundStyle(.tint)
								.frame(width: 22)
							
							Text(entry.key.displayName)
								.font(.body)
							
							Spacer()
							
							Text("\(entry.value)")
								.font(.body.monospacedDigit())
								.foregroundStyle(.secondary)
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 12)
						
						if index < sortedEntries.count - 1 {
							SettingsRowDivider()
						}
					}
				}
			}
			
			Button {
				dismiss()
			} label: {
				Text("Done")
					.font(.headline)
					.foregroundStyle(.white)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 14)
					.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
			.buttonStyle(.plain)
		}
	}
	
	private func inspect(url: URL) async {
		stage = .verifying
		do {
			let archive = try await BackupService.inspectBackup(at: url)
			selectedModules = Set(archive.manifest.modules.compactMap(\.knownKind))
			selectedPlayerIDs = Set(archive.manifest.players.map(\.id))
			if archive.isPasswordEncrypted {
				passwordInput = ""
				stage = .needsPassword(archive, error: nil)
			} else {
				stage = .ready(archive, nil)
			}
		} catch {
			stage = .verificationFailed(error.localizedDescription)
		}
	}
	
	private func unlock(archive: VerifiedBackupArchive) {
		isUnlocking = true
		let candidate = passwordInput
		Task {
			defer { isUnlocking = false }
			do {
				let key = try await BackupService.unlockBackup(archive, password: candidate)
				stage = .ready(archive, key)
			} catch {
				stage = .needsPassword(archive, error: error.localizedDescription)
			}
		}
	}
	
	private func runImport(archive: VerifiedBackupArchive, encryptionKey: SymmetricKey?) {
		let options = BackupImportOptions(
			selectedModules: selectedModules,
			selectedPlayerIDs: selectedPlayerIDs,
			allManifestPlayersSelected: selectedPlayerIDs == Set(archive.manifest.players.map(\.id)),
			mode: importMode
		)
		stage = .importing
		Task {
			do {
				let summary = try await BackupService.importBackup(
					archive: archive,
					encryptionKey: encryptionKey,
					options: options,
					stores: stores
				)
				onImportCompleted?()
				stage = .completed(summary)
			} catch {
				stage = .verificationFailed(error.localizedDescription)
			}
		}
	}
}
