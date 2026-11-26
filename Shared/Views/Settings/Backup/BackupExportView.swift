import SwiftUI
import UIKit
import ValorantAPI

struct BackupExportView: View {
	let stores: BackupStores
	
	@State private var inventory: BackupInventory?
	@State private var isLoadingInventory = true
	@State private var selectedModules: Set<BackupModuleKind> = BackupModuleKind.defaultExportSelection
	@State private var selectedPlayerIDs: Set<User.ID> = []
	
	@State private var encryptWithPassword = false
	@State private var password = ""
	@State private var confirmPassword = ""
	
	@State private var isExporting = false
	@State private var exportError: String?
	@State private var exportResult: BackupExportResult?
	@State private var documentExportURL: URL?
	@State private var exportTask: Task<Void, Never>?
	
	private struct ModuleStats {
		let count: Int
		let bytes: Int64?
	}
	
	@State private var cachedModuleStats: [BackupModuleKind: ModuleStats] = [:]
	@State private var cachedStatsPlayerSelection: Set<User.ID> = []
	@State private var cachedEffectiveSelectedModulesCount = 0
	@State private var cachedEstimatedSelectedDiskBytes: Int64 = 0
	
	private var passwordValidationError: String? {
		guard encryptWithPassword else { return nil }
		if password.isEmpty {
			return "Enter a password to encrypt the backup."
		}
		if password != confirmPassword {
			return "Passwords do not match."
		}
		return nil
	}
	
	private func effectiveItemCount(for kind: BackupModuleKind) -> Int {
		if let cached = cachedModuleStats[kind] {
			return cached.count
		}
		return inventory?.itemCount(for: kind, selectedPlayers: selectedPlayerIDs) ?? 0
	}
	
	private func recomputeModuleStats(force: Bool = false) {
		guard let inventory else {
			cachedModuleStats.removeAll()
			cachedEffectiveSelectedModulesCount = 0
			cachedEstimatedSelectedDiskBytes = 0
			return
		}
		if force || cachedModuleStats.isEmpty || cachedStatsPlayerSelection != selectedPlayerIDs {
			cachedStatsPlayerSelection = selectedPlayerIDs
			var updated: [BackupModuleKind: ModuleStats] = [:]
			updated.reserveCapacity(BackupModuleKind.allCases.count)
			for kind in BackupModuleKind.allCases {
				updated[kind] = ModuleStats(
					count: inventory.itemCount(for: kind, selectedPlayers: selectedPlayerIDs),
					bytes: inventory.estimatedBytes(for: kind, selectedPlayers: selectedPlayerIDs)
				)
			}
			cachedModuleStats = updated
		}
		
		var count = 0
		var totalBytes: Int64 = 0
		for kind in selectedModules {
			if let stat = cachedModuleStats[kind] {
				if stat.count > 0 {
					count += 1
				}
				totalBytes += stat.bytes ?? 0
			}
		}
		cachedEffectiveSelectedModulesCount = count
		cachedEstimatedSelectedDiskBytes = totalBytes
	}
	
	private var canExport: Bool {
		!isLoadingInventory
			&& !isExporting
			&& cachedEffectiveSelectedModulesCount > 0
			&& passwordValidationError == nil
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "square.and.arrow.up",
					title: "Export Cached Data",
					subtitle: "Create a signed .rbbackup archive to preserve your matches, profiles, and personal data across app updates or reinstalls. Riot login tokens and downloadable assets are never included."
				)
				
				if isLoadingInventory {
					SettingsCard {
						HStack(spacing: 12) {
							ProgressView()
							Text("Scanning cached data…")
								.font(.subheadline)
								.foregroundStyle(.secondary)
							Spacer()
						}
						.padding(16)
					}
				} else if let inventory {
					playersSection(inventory: inventory)
					
					presetsBar(inventory: inventory)
					
					ForEach(BackupModuleGroup.allCases) { group in
						moduleGroupSection(group: group, inventory: inventory)
					}
					
					securitySection
					
					exportActionSection
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Export Backup")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await loadInventory()
		}
		.onChange(of: selectedPlayerIDs) { _ in
			recomputeModuleStats()
		}
		.onChange(of: selectedModules) { _ in
			recomputeModuleStats()
		}
		.onDisappear {
			exportTask?.cancel()
			exportTask = nil
			cleanupTemporaryExport()
		}
		.sheet(item: $exportResult) { result in
			NavigationStack {
				exportReadySheet(result: result)
			}
		}
		.alert("Export Failed", isPresented: Binding(
			get: { exportError != nil },
			set: { if !$0 { exportError = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			if let exportError {
				Text(exportError)
			}
		}
	}
	
	private func playersSection(inventory: BackupInventory) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			SettingsSectionHeader("Players")
			
			SettingsCard {
				NavigationLink {
					BackupPlayerPickerView(
						players: inventory.players,
						selectedPlayerIDs: $selectedPlayerIDs
					)
				} label: {
					HStack(spacing: 14) {
						Image(systemName: "person.2")
							.font(.system(size: 18))
							.foregroundStyle(.tint)
							.frame(width: 24)
						
						Text("Included Players")
							.font(.body)
							.foregroundStyle(.primary)
						
						Spacer()
						
						Text(playerSummaryLabel(inventory: inventory))
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
				.disabled(inventory.players.isEmpty)
			}
			
			SettingsFooter("Filter which accounts, bookmarked players, or cached players are included. Full match details automatically carry co-player identities so scoreboards work offline.")
		}
	}
	
	private func playerSummaryLabel(inventory: BackupInventory) -> String {
		if inventory.players.isEmpty {
			return "None"
		}
		if selectedPlayerIDs.count == inventory.players.count {
			return "All (\(inventory.players.count))"
		}
		return "\(selectedPlayerIDs.count) of \(inventory.players.count)"
	}
	
	private func presetsBar(inventory: BackupInventory) -> some View {
		HStack(spacing: 8) {
			presetChip(title: "All Data") {
				selectedModules = Set(BackupModuleKind.allCases)
			}
			presetChip(title: "Essential") {
				selectedModules = BackupModuleKind.essentialSelection
			}
			presetChip(title: "Matches Only") {
				selectedModules = [.matchLists, .matchDetails, .users, .playerIdentities]
			}
			presetChip(title: "Clear") {
				selectedModules.removeAll()
			}
			Spacer()
		}
	}
	
	private func presetChip(title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.caption.weight(.medium))
				.foregroundStyle(.tint)
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.background(Color.secondaryGroupedBackground, in: Capsule())
		}
		.buttonStyle(.plain)
	}
	
	private func moduleGroupSection(group: BackupModuleGroup, inventory: BackupInventory) -> some View {
		let kinds = BackupModuleKind.allCases.filter { $0.group == group }
		return VStack(alignment: .leading, spacing: 8) {
			SettingsSectionHeader(LocalizedStringKey(group.title))
			
			SettingsCard {
				ForEach(Array(kinds.enumerated()), id: \.element.id) { index, kind in
					moduleRow(kind: kind, inventory: inventory)
					if index < kinds.count - 1 {
						SettingsRowDivider()
					}
				}
			}
		}
	}
	
	private func moduleRow(kind: BackupModuleKind, inventory: BackupInventory) -> some View {
		let stat = cachedModuleStats[kind]
		let count = stat?.count ?? inventory.itemCount(for: kind, selectedPlayers: selectedPlayerIDs)
		let bytes = stat?.bytes ?? inventory.estimatedBytes(for: kind, selectedPlayers: selectedPlayerIDs)
		let isEmpty = count == 0
		
		return Toggle(isOn: Binding(
			get: { !isEmpty && selectedModules.contains(kind) },
			set: { isOn in
				if isOn {
					selectedModules.insert(kind)
				} else {
					selectedModules.remove(kind)
				}
			}
		)) {
			HStack(spacing: 14) {
				Image(systemName: kind.icon)
					.font(.system(size: 18))
					.foregroundStyle(isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
					.frame(width: 24)
				
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 6) {
						Text(kind.displayName)
							.font(.body)
							.foregroundStyle(isEmpty ? .secondary : .primary)
						
						if kind.isSensitivePrivate {
							Text("Private")
								.font(.caption2.weight(.semibold))
								.foregroundStyle(.orange)
								.padding(.horizontal, 6)
								.padding(.vertical, 2)
								.background(Color.orange.opacity(0.14), in: Capsule())
						}
					}
					
					HStack(spacing: 6) {
						Text("\(count) item\(count == 1 ? "" : "s")")
						if let bytes, bytes > 0 {
							Text("•")
							Text(bytes, format: .byteCount(style: .file))
						}
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				}
			}
		}
		.disabled(isEmpty)
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
	}
	
	private var securitySection: some View {
		VStack(alignment: .leading, spacing: 8) {
			SettingsSectionHeader("Security & Tamper Protection")
			
			SettingsCard {
				HStack(alignment: .top, spacing: 14) {
					Image(systemName: "checkmark.shield")
						.font(.system(size: 18))
						.foregroundStyle(.green)
						.frame(width: 24)
					
					VStack(alignment: .leading, spacing: 2) {
						Text("Signed & Integrity-Protected")
							.font(.body)
						Text("Every export is LZFSE-compressed and sealed with SHA-256 hashes, HMAC-SHA256, and your device's Keychain ECDSA signature.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
				
				SettingsRowDivider()
				
				Toggle(isOn: $encryptWithPassword) {
					HStack(spacing: 14) {
						Image(systemName: "lock")
							.font(.system(size: 18))
							.foregroundStyle(.tint)
							.frame(width: 24)
						
						Text("Encrypt with Password (AES-256)")
							.font(.body)
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
				
				if encryptWithPassword {
					SettingsRowDivider(leadingInset: 16)
					
					VStack(spacing: 10) {
						SecureField("Backup Password", text: $password)
							.textContentType(.newPassword)
							.padding(.horizontal, 12)
							.padding(.vertical, 10)
							.background(Color.groupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
						
						SecureField("Confirm Password", text: $confirmPassword)
							.textContentType(.newPassword)
							.padding(.horizontal, 12)
							.padding(.vertical, 10)
							.background(Color.groupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
						
						if let validation = passwordValidationError {
							HStack(spacing: 6) {
								Image(systemName: "exclamationmark.triangle.fill")
									.font(.caption)
								Text(validation)
									.font(.caption)
								Spacer()
							}
							.foregroundStyle(.orange)
						}
					}
					.padding(16)
				}
			}
			
			SettingsFooter("Optional password encryption uses PBKDF2-HMAC-SHA256 + AES-256-GCM. If you forget your password, the archive cannot be decrypted.")
		}
	}
	
	private var exportActionSection: some View {
		VStack(spacing: 8) {
			Button {
				runExport()
			} label: {
				HStack(spacing: 10) {
					if isExporting {
						ProgressView()
							.tint(.white)
					} else {
						Image(systemName: "arrow.up.doc.fill")
					}
					Text(isExporting ? "Building Verified Archive…" : "Create .rbbackup Archive")
						.font(.headline)
				}
				.foregroundStyle(.white)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 15)
				.background(
					canExport ? Color.accentColor : Color.secondary.opacity(0.35),
					in: RoundedRectangle(cornerRadius: 16, style: .continuous)
				)
			}
			.buttonStyle(.plain)
			.disabled(!canExport)
			
			if cachedEstimatedSelectedDiskBytes > 0 {
				Text("Raw JSON on disk: \(cachedEstimatedSelectedDiskBytes, format: .byteCount(style: .file)) (compressed in archive)")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}
		}
		.padding(.top, 4)
	}
	
	private func exportReadySheet(result: BackupExportResult) -> some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "checkmark.seal.fill",
					title: "Backup Ready",
					subtitle: "Your verified .rbbackup archive has been created and sealed against tampering."
				)
				
				SettingsCard {
					summaryRow(title: "File Name", value: result.fileURL.lastPathComponent)
					SettingsRowDivider(leadingInset: 16)
					summaryRow(title: "Archive Size", value: result.byteCount.formatted(.byteCount(style: .file)))
					SettingsRowDivider(leadingInset: 16)
					summaryRow(title: "Categories", value: "\(result.moduleCount)")
					SettingsRowDivider(leadingInset: 16)
					summaryRow(title: "Items", value: "\(result.totalItems)")
					SettingsRowDivider(leadingInset: 16)
					summaryRow(title: "Players", value: "\(result.playerCount)")
					SettingsRowDivider(leadingInset: 16)
					summaryRow(title: "Protection", value: result.isEncrypted ? "AES-256-GCM + ECDSA" : "SHA-256 + ECDSA")
					SettingsRowDivider(leadingInset: 16)
					summaryRow(title: "Device Key ID", value: result.fingerprint, monospaced: true)
				}
				
				VStack(spacing: 12) {
					Button {
						documentExportURL = result.fileURL
					} label: {
						Label("Save to Files…", systemImage: "folder.badge.plus")
							.font(.headline)
							.foregroundStyle(.white)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 14)
							.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
					}
					.buttonStyle(.plain)
					
					ShareLink(
						item: result.fileURL,
						preview: SharePreview(result.fileURL.lastPathComponent, icon: Image(systemName: "lock.doc"))
					) {
						Label("Share via AirDrop / Apps…", systemImage: "square.and.arrow.up")
							.font(.headline)
							.foregroundStyle(.tint)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 14)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
					}
				}
			}
			.padding(16)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Export Complete")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button("Done") {
					cleanupTemporaryExport()
				}
			}
		}
		.background(
			DocumentExporterPresenter(url: $documentExportURL)
				.frame(width: 0, height: 0)
		)
	}
	
	private func summaryRow(title: String, value: String, monospaced: Bool = false) -> some View {
		HStack {
			Text(title)
				.font(.body)
				.foregroundStyle(.secondary)
			Spacer()
			Text(value)
				.font(monospaced ? .footnote.monospaced() : .body.monospacedDigit())
				.foregroundStyle(.primary)
				.lineLimit(1)
				.truncationMode(.middle)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
	}
	
	private func loadInventory() async {
		isLoadingInventory = true
		let built = await BackupService.buildInventory(stores: stores)
		inventory = built
		selectedPlayerIDs = built.allPlayerIDs
		recomputeModuleStats(force: true)
		isLoadingInventory = false
	}
	
	private func runExport() {
		guard let inventory else { return }
		exportTask?.cancel()
		cleanupTemporaryExport()
		isExporting = true
		
		let activeModules = Set(selectedModules.filter { effectiveItemCount(for: $0) > 0 })
		let options = BackupExportOptions(
			selectedModules: activeModules,
			selectedPlayerIDs: selectedPlayerIDs,
			allPlayersSelected: selectedPlayerIDs == inventory.allPlayerIDs,
			password: encryptWithPassword ? password : nil
		)
		
		exportTask = Task {
			defer {
				isExporting = false
				exportTask = nil
			}
			do {
				let result = try await BackupService.exportBackup(
					options: options,
					inventory: inventory,
					stores: stores
				)
				if Task.isCancelled {
					try? FileManager.default.removeItem(at: result.fileURL)
					return
				}
				exportResult = result
			} catch is CancellationError {
				return
			} catch {
				exportError = error.localizedDescription
			}
		}
	}
	
	private func cleanupTemporaryExport() {
		documentExportURL = nil
		if let url = exportResult?.fileURL {
			try? FileManager.default.removeItem(at: url)
		}
		exportResult = nil
	}
}

private struct DocumentExporterPresenter: UIViewControllerRepresentable {
	@Binding var url: URL?
	
	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}
	
	func makeUIViewController(context: Context) -> UIViewController {
		UIViewController()
	}
	
	func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
		context.coordinator.parent = self
		guard let url, context.coordinator.presentedPicker == nil else { return }
		
		let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
		picker.delegate = context.coordinator
		context.coordinator.presentedPicker = picker
		
		DispatchQueue.main.async {
			let host: UIViewController?
			if uiViewController.viewIfLoaded?.window != nil, uiViewController.presentedViewController == nil {
				host = uiViewController
			} else {
				host = Self.topViewController()
			}
			guard let host, host.presentedViewController == nil else {
				context.coordinator.presentedPicker = nil
				self.url = nil
				return
			}
			host.present(picker, animated: true)
		}
	}
	
	private static func topViewController() -> UIViewController? {
		let keyWindow = UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first(where: \.isKeyWindow)
			?? UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first
		var current = keyWindow?.rootViewController
		while let presented = current?.presentedViewController {
			current = presented
		}
		return current
	}
	
	final class Coordinator: NSObject, UIDocumentPickerDelegate {
		var parent: DocumentExporterPresenter
		weak var presentedPicker: UIDocumentPickerViewController?
		
		init(parent: DocumentExporterPresenter) {
			self.parent = parent
		}
		
		func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
			finish()
		}
		
		func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
			finish()
		}
		
		private func finish() {
			presentedPicker = nil
			Task { @MainActor [weak self] in
				self?.parent.url = nil
			}
		}
	}
}
