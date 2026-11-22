import SwiftUI

struct AssetStorageView: View {
	@ObservedObject var assetManager: AssetManager
	@EnvironmentObject private var imageManager: ImageManager
	
	@State private var newestVersion: AssetVersion?
	@State private var isCheckingUpdates = false
	@State private var updateStatusMessage: String?
	@State private var installedBytes: Int64 = 0
	@State private var backupBytes: Int64 = 0
	@State private var widgetBytes: Int64 = 0
	@State private var cachedImagesBytes: Int64 = 0
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				statusCard
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("Something Not Right?")
					
					SettingsCard {
						NavigationLink {
							RepairGameAssetsView(assetManager: assetManager)
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "wrench.and.screwdriver")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Repair Game Assets")
									.font(.body)
									.foregroundStyle(.primary)
								
								Spacer()
								
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
						
						HStack(spacing: 14) {
							Image(systemName: "trash")
								.font(.system(size: 18))
								.foregroundStyle(.tint)
								.frame(width: 24)
							
							VStack(alignment: .leading, spacing: 2) {
								Text("Don't Delete Vantage to Fix This")
									.font(.body.weight(.semibold))
									.foregroundStyle(.primary)
								
								Text("A reinstall signs you out and deletes your matches and histories.")
									.font(.subheadline)
									.foregroundStyle(.secondary)
									.fixedSize(horizontal: false, vertical: true)
							}
							
							Spacer()
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
					}
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("On This iPhone")
					
					SettingsCard {
						sizeRow(icon: "cube", title: "Installed Version", bytes: installedBytes, zeroLabel: "0 B")
						SettingsRowDivider()
						sizeRow(icon: "clock.arrow.circlepath", title: "Backup", bytes: backupBytes, zeroLabel: "None Yet")
						SettingsRowDivider()
						sizeRow(icon: "apps.iphone", title: "Widgets", bytes: widgetBytes, zeroLabel: "None Yet")
						SettingsRowDivider()
						sizeRow(icon: "photo.on.rectangle", title: "Cached Images", bytes: cachedImagesBytes, zeroLabel: "0 B")
						SettingsRowDivider(leadingInset: 16)
						
						Button {
							imageManager.clear()
							Task { await refreshSizes() }
						} label: {
							HStack {
								Text("Clear Cached Images")
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
					
					SettingsFooter("The backup is the previous version of the game assets. Vantage switches to it if the installed version can't be read.")
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsCard {
						NavigationLink {
							AssetsInfoView.LanguagePicker(languageOverride: assetManager.languageOverride) { language in
								await assetManager.setLanguageOverride(to: language)
								await refreshSizes()
							}
						} label: {
							HStack(spacing: 14) {
								Image(systemName: "globe")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								Text("Language")
									.font(.body)
									.foregroundStyle(.primary)
								
								Spacer()
								
								AssetsInfoView.LanguageOverrideLabel(language: assetManager.languageOverride)
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
					
					SettingsFooter("Changing the language downloads the game assets again.")
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Game Assets")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await refreshSizes()
			if newestVersion == nil {
				newestVersion = try? await AssetClient(language: assetManager.resolvedLanguage).getCurrentVersion()
			}
		}
		.onChange(of: assetManager.assets?.version) { _ in
			Task { await refreshSizes() }
		}
		.alert("Game Assets", isPresented: Binding(
			get: { updateStatusMessage != nil },
			set: { if !$0 { updateStatusMessage = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			if let updateStatusMessage {
				Text(updateStatusMessage)
			}
		}
	}
	
	private var statusCard: some View {
		let assets = assetManager.assets
		let hasError = assetManager.error != nil
		let isOutdated = assets != nil && newestVersion != nil && assets?.version != newestVersion
		
		return SettingsCard {
			HStack(spacing: 14) {
				ZStack {
					Circle()
						.fill(Color.secondary.opacity(0.22))
						.frame(width: 26, height: 26)
					
					if hasError || assets == nil {
						Image(systemName: "exclamationmark")
							.font(.caption.bold())
							.foregroundStyle(.orange)
					} else if isOutdated {
						Image(systemName: "arrow.down")
							.font(.caption.bold())
							.foregroundStyle(.tint)
					} else {
						Image(systemName: "checkmark")
							.font(.caption.bold())
							.foregroundStyle(.secondary)
					}
				}
				
				VStack(alignment: .leading, spacing: 3) {
					if hasError {
						Text("Error Loading Game Assets")
							.font(.body.weight(.semibold))
					} else if assets == nil {
						Text("Missing Game Assets")
							.font(.body.weight(.semibold))
					} else if isOutdated {
						Text("Game Assets Update Available")
							.font(.body.weight(.semibold))
					} else {
						Text("Game Assets Are Up to Date")
							.font(.body.weight(.semibold))
					}
					
					if let assets {
						Text(statusDetailLine(assets: assets))
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					} else if let error = assetManager.error {
						Text(error.localizedDescription)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				
				Spacer()
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			
			SettingsRowDivider(leadingInset: 16)
			
			Button {
				checkForUpdates()
			} label: {
				HStack(spacing: 14) {
					Image(systemName: "arrow.clockwise")
						.font(.system(size: 18))
						.foregroundStyle(.tint)
						.frame(width: 24)
					
					Text(isCheckingUpdates ? "Checking for Updates..." : "Check for Updates")
						.font(.body)
						.foregroundStyle(.tint)
					
					Spacer()
					
					if isCheckingUpdates {
						ProgressView()
							.controlSize(.small)
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 14)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.disabled(isCheckingUpdates)
		}
	}
	
	private func statusDetailLine(assets: AssetCollection) -> String {
		let langName = Locale.current.localizedString(forIdentifier: assets.language) ?? assets.language
		let cleanVersion = Self.shortVersion(assets.version.version)
		let datePart: String
		if let installedAt = assetManager.installedAt {
			let formatted = installedAt.formatted(.dateTime.day().month(.abbreviated))
			datePart = " · installed \(formatted)"
		} else {
			datePart = ""
		}
		return "VALORANT \(cleanVersion) · \(langName)\(datePart)"
	}
	
	private static func shortVersion(_ raw: String) -> String {
		let parts = raw.split(separator: ".")
		if parts.count >= 2 {
			return "\(parts[0]).\(parts[1])"
		}
		return raw
	}
	
	private func sizeRow(icon: String, title: LocalizedStringKey, bytes: Int64, zeroLabel: LocalizedStringKey) -> some View {
		HStack(spacing: 14) {
			Image(systemName: icon)
				.font(.system(size: 18))
				.foregroundStyle(.tint)
				.frame(width: 24)
			
			Text(title)
				.font(.body)
				.foregroundStyle(.primary)
			
			Spacer()
			
			if bytes > 0 {
				Text(bytes, format: .byteCount(style: .file))
					.font(.body.monospacedDigit())
					.foregroundStyle(.secondary)
			} else {
				Text(zeroLabel)
					.font(.body)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
	}
	
	private func checkForUpdates() {
		isCheckingUpdates = true
		Task {
			defer { isCheckingUpdates = false }
			do {
				let updated = try await assetManager.checkForUpdates()
				newestVersion = try? await AssetClient(language: assetManager.resolvedLanguage).getCurrentVersion()
				await refreshSizes()
				updateStatusMessage = updated
					? "Downloaded the latest game assets."
					: "Your game assets are already up to date."
			} catch {
				updateStatusMessage = error.localizedDescription
			}
		}
	}
	
	@MainActor
	private func refreshSizes() async {
		let assetSizes = assetManager.storageSizes()
		let breakdown = await StorageBreakdown.compute(assetManager: assetManager)
		installedBytes = assetSizes.installedBytes
		backupBytes = assetSizes.backupBytes
		widgetBytes = assetSizes.widgetBytes
		cachedImagesBytes = breakdown.cachedImagesBytes
	}
}

struct RepairGameAssetsView: View {
	@ObservedObject var assetManager: AssetManager
	@EnvironmentObject private var imageManager: ImageManager
	@State private var isRepairing = false
	@State private var repairFinished = false
	
	var body: some View {
		VStack(spacing: 0) {
			ScrollView {
				VStack(spacing: 20) {
					VStack(spacing: 12) {
						Image(systemName: "wrench.and.screwdriver")
							.font(.system(size: 46))
							.foregroundStyle(.tint)
						
						Text("Repair Game Assets")
							.font(.title2.bold())
						
						Text("Downloads every game asset again and clears cached images. Your accounts, matches, histories and settings stay.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
							.padding(.horizontal, 12)
					}
					.padding(.top, 20)
					.padding(.bottom, 8)
					
					VStack(alignment: .leading, spacing: 8) {
						SettingsSectionHeader("If You Delete Vantage Instead")
						
						SettingsCard {
							consequenceRow(icon: "person.crop.circle", title: "Accounts", status: "Signed Out")
							SettingsRowDivider()
							consequenceRow(icon: "gamecontroller", title: "Downloaded Matches", status: "Deleted")
							SettingsRowDivider()
							consequenceRow(icon: "archivebox", title: "Histories and Settings", status: "Deleted")
						}
						
						SettingsFooter("Older matches may not download again. Histories and settings include Shop History, Name History, Friend List Changes, Player Settings Snapshots, bookmarked players and presets.")
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
			}
			
			Button {
				isRepairing = true
				Task {
					await assetManager.repairAssets(imageManager: imageManager)
					isRepairing = false
					repairFinished = true
				}
			} label: {
				HStack(spacing: 10) {
					if isRepairing {
						ProgressView()
							.tint(.white)
					}
					Text(isRepairing ? "Repairing Game Assets..." : "Repair Game Assets")
						.font(.headline)
				}
				.foregroundStyle(.white)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 16)
				.background(TintShapeStyle.tint, in: Capsule())
			}
			.buttonStyle(.plain)
			.disabled(isRepairing)
			.padding(.horizontal, 20)
			.padding(.vertical, 16)
		}
		.background(Color.groupedBackground)
		.navigationTitle("")
		.navigationBarTitleDisplayMode(.inline)
		.alert("Repair Complete", isPresented: $repairFinished) {
			Button("OK", role: .cancel) {}
		} message: {
			if let error = assetManager.error {
				Text(error.localizedDescription)
			} else {
				Text("Every game asset was re-downloaded and cached images were cleared. Your accounts, matches, histories, and settings stayed intact.")
			}
		}
	}
	
	private func consequenceRow(icon: String, title: LocalizedStringKey, status: LocalizedStringKey) -> some View {
		HStack(spacing: 14) {
			Image(systemName: icon)
				.font(.system(size: 18))
				.foregroundStyle(.tint)
				.frame(width: 24)
			
			Text(title)
				.font(.body)
				.foregroundStyle(.primary)
			
			Spacer()
			
			Text(status)
				.font(.body)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
	}
}
