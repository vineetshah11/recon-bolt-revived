import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	
	@EnvironmentObject private var notificationManager: StoreNotificationManager
	@State private var showingPermissionDeniedAlert = false
	
	private static let leadTimeOptions = [6, 12, 24, 48]
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "bell.badge",
					title: "Notifications",
					subtitle: "Receive local alerts when your daily shop rotates, wishlist items appear, featured bundles are leaving, or Night Market opens."
				)
				
				permissionStatusBanner
				backgroundRefreshBanner
				
				VStack(alignment: .leading, spacing: 14) {
					SettingsSectionHeader("Store Alerts")
					
					SettingsToggleCard(
						icon: "clock.arrow.circlepath",
						title: "Daily Shop Refresh",
						isOn: $settings.notifyShopRefresh,
						footer: "Notifies you right after the daily shop resets at 00:00 UTC. If Wishlist Match is also enabled, the generic alert waits briefly so a wishlist alert can replace it if a match is found."
					)
					
					SettingsToggleCard(
						icon: "heart.fill",
						title: "Wishlist Match",
						isOn: $settings.notifyWishlistMatch,
						footer: "Sends a custom alert with item names and prices (trimmed cleanly if several match) when wishlisted skins or accessories appear in your shop. Uses iOS Background App Refresh, so delivery timing depends on iOS (typically a few minutes to a couple hours after reset — avoid force-quitting the app)."
					)
					
					SettingsToggleCard(
						icon: "shippingbox.fill",
						title: "Bundle Leaving Soon",
						isOn: $settings.notifyBundleLeavingSoon,
						footer: "Sends an exact reminder before each active featured bundle leaves the store."
					)
					
					SettingsToggleCard(
						icon: "moon.stars.fill",
						title: "Night Market",
						isOn: $settings.notifyNightMarket,
						footer: "Notifies you via Background App Refresh when a Night Market opens (highlighting any wishlisted skins inside) and sends an exact reminder before it closes."
					)
				}
				
				if settings.notifyBundleLeavingSoon || settings.notifyNightMarket || (accountManager.storedAccounts.count > 1 && (settings.notifyWishlistMatch || settings.notifyNightMarket)) {
					VStack(alignment: .leading, spacing: 8) {
						SettingsSectionHeader("Options")
						
						SettingsCard {
							if settings.notifyBundleLeavingSoon || settings.notifyNightMarket {
								HStack(spacing: 14) {
									Image(systemName: "timer")
										.font(.system(size: 18))
										.foregroundStyle(.tint)
										.frame(width: 24)
									
									Text("Reminder Lead Time")
										.font(.body)
									
									Spacer(minLength: 8)
									
									Menu {
										ForEach(Self.leadTimeOptions, id: \.self) { hours in
											Button {
												settings.notificationLeadTimeHours = hours
											} label: {
												if settings.notificationLeadTimeHours == hours {
													Label(leadTimeLabel(for: hours), systemImage: "checkmark")
												} else {
													Text(leadTimeLabel(for: hours))
												}
											}
										}
									} label: {
										HStack(spacing: 5) {
											Text(leadTimeLabel(for: settings.notificationLeadTimeHours))
												.lineLimit(1)
											Image(systemName: "chevron.up.chevron.down")
												.font(.caption2.weight(.semibold))
										}
										.font(.subheadline.weight(.medium))
										.foregroundStyle(.tint)
										.fixedSize(horizontal: true, vertical: false)
									}
								}
								.padding(.horizontal, 16)
								.padding(.vertical, 10)
							}
							
							if (settings.notifyBundleLeavingSoon || settings.notifyNightMarket)
								&& accountManager.storedAccounts.count > 1
								&& (settings.notifyWishlistMatch || settings.notifyNightMarket) {
								SettingsRowDivider()
							}
							
							if accountManager.storedAccounts.count > 1 && (settings.notifyWishlistMatch || settings.notifyNightMarket) {
								Toggle(isOn: $settings.notifyAllAccounts) {
									HStack(spacing: 14) {
										Image(systemName: "person.2")
											.font(.system(size: 18))
											.foregroundStyle(.tint)
											.frame(width: 24)
										
										Text("Check All Signed-In Accounts")
											.font(.body)
									}
								}
								.padding(.horizontal, 16)
								.padding(.vertical, 12)
							}
						}
					}
				}
				
				VStack(alignment: .leading, spacing: 8) {
					SettingsSectionHeader("Status & Diagnostics")
					
					SettingsCard {
						VStack(spacing: 0) {
							HStack(spacing: 14) {
								Image(systemName: "calendar.badge.clock")
									.font(.system(size: 18))
									.foregroundStyle(.tint)
									.frame(width: 24)
								
								VStack(alignment: .leading, spacing: 2) {
									Text("Scheduled Alerts")
										.font(.body)
									Text(statusSummaryText)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								
								Spacer()
								
								Text("\(notificationManager.pendingRequests.count)")
									.font(.subheadline.monospacedDigit())
									.foregroundStyle(.secondary)
							}
							.padding(.horizontal, 16)
							.padding(.vertical, 12)
							
							SettingsRowDivider()
							
							NavigationLink {
								NotificationDiagnosticsView(
									accountManager: accountManager,
									assetManager: assetManager,
									settings: settings
								)
							} label: {
								HStack(spacing: 14) {
									Image(systemName: "bell.and.waves.left.and.right")
										.font(.system(size: 18))
										.foregroundStyle(.tint)
										.frame(width: 24)
									
									Text("Testing & Diagnostics")
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
						}
					}
					
					SettingsFooter("Open Testing & Diagnostics to preview every alert banner, trigger timed test notifications, run a live store check, or inspect the iOS notification queue.")
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Notifications")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await notificationManager.refreshStatus()
		}
		.onChange(of: settings.notifyShopRefresh) { isOn in
			Task { await handleToggleChanged(isOn: isOn) }
		}
		.onChange(of: settings.notifyWishlistMatch) { isOn in
			Task { await handleToggleChanged(isOn: isOn) }
		}
		.onChange(of: settings.notifyBundleLeavingSoon) { isOn in
			Task { await handleToggleChanged(isOn: isOn) }
		}
		.onChange(of: settings.notifyNightMarket) { isOn in
			Task { await handleToggleChanged(isOn: isOn) }
		}
		.onChange(of: settings.notificationLeadTimeHours) { _ in
			Task { await notificationManager.syncSchedules() }
		}
		.onChange(of: settings.notifyAllAccounts) { _ in
			Task { await notificationManager.syncSchedules() }
		}
		.alert("Notifications Blocked", isPresented: $showingPermissionDeniedAlert) {
			Button("Open Settings") {
				if let url = URL(string: UIApplication.openSettingsURLString) {
					UIApplication.shared.open(url)
				}
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Allow notifications for Recon Bolt Revived in iOS Settings so store alerts can be delivered.")
		}
	}
	
	@ViewBuilder
	private var permissionStatusBanner: some View {
		if notificationManager.authorizationStatus == .denied {
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .top, spacing: 10) {
					Image(systemName: "bell.slash.fill")
						.foregroundStyle(.orange)
						.font(.subheadline)
					VStack(alignment: .leading, spacing: 4) {
						Text("Notifications Are Disabled in iOS")
							.font(.subheadline.weight(.semibold))
						Text("Turn on Allow Notifications in iOS Settings to receive store alerts.")
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
				
				Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
					Text("Open iOS Settings")
						.font(.footnote.weight(.semibold))
						.foregroundStyle(.orange)
				}
			}
			.padding(14)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		} else if notificationManager.authorizationStatus == .notDetermined && settings.anyStoreNotificationEnabled {
			HStack(spacing: 12) {
				Image(systemName: "bell.badge")
					.foregroundStyle(.tint)
					.font(.title3)
				VStack(alignment: .leading, spacing: 2) {
					Text("Permission Required")
						.font(.subheadline.weight(.semibold))
					Text("Grant permission so iOS can display your scheduled alerts.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Button("Allow") {
					Task {
						let granted = await notificationManager.requestAuthorizationIfNeeded()
						if granted {
							await notificationManager.syncSchedules()
						}
					}
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		}
	}
	
	@ViewBuilder
	private var backgroundRefreshBanner: some View {
		if (settings.notifyWishlistMatch || settings.notifyNightMarket),
		   notificationManager.backgroundRefreshStatus != .available {
			HStack(alignment: .top, spacing: 10) {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.orange)
					.font(.subheadline)
				Text("iOS Background App Refresh is currently disabled (or Low Power Mode is active). Wishlist Match and Night Market opening alerts need Background App Refresh enabled in iOS Settings to check your store while closed.")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			.padding(12)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		}
	}
	
	private var statusSummaryText: String {
		let bundleCount = notificationManager.state.trackedBundles.count
		if let nextRefresh = notificationManager.state.lastKnownDailyRefreshDate, nextRefresh > Date() {
			return "Next reset \(nextRefresh.formatted(date: .omitted, time: .shortened)) · \(bundleCount) tracked bundle\(bundleCount == 1 ? "" : "s")"
		}
		return "\(bundleCount) tracked bundle\(bundleCount == 1 ? "" : "s") · Open Live Store once to sync timers"
	}
	
	private func leadTimeLabel(for hours: Int) -> String {
		if hours >= 48 && hours % 24 == 0 {
			return "\(hours / 24) days before"
		}
		return "\(hours) hours before"
	}
	
	private func handleToggleChanged(isOn: Bool) async {
		if isOn {
			let granted = await notificationManager.requestAuthorizationIfNeeded()
			if !granted {
				showingPermissionDeniedAlert = true
			}
		}
		await notificationManager.syncSchedules()
	}
}
