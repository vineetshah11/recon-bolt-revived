import SwiftUI
import UIKit

struct NotificationDiagnosticsView: View {
	@ObservedObject var accountManager: AccountManager
	@ObservedObject var assetManager: AssetManager
	@ObservedObject var settings: AppSettings
	
	@EnvironmentObject private var notificationManager: StoreNotificationManager
	
	@State private var selectedKind: TestNotificationKind = .wishlistMultiple
	@State private var selectedDelay: TestNotificationDelay = .fiveSeconds
	@State private var postDiagnosticAlerts = true
	@State private var testFeedback: String?
	@State private var testError: String?
	@State private var isResyncing = false
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				SettingsHeroCard(
					icon: "bell.and.waves.left.and.right",
					title: "Notification Testing",
					subtitle: "Preview exact notification banners instantly, schedule timed test notifications, or run a live store check without waiting for daily reset."
				)
				
				testTriggerSection
				liveStoreCheckSection
				pendingQueueSection
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.navigationTitle("Testing & Diagnostics")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await notificationManager.refreshStatus()
		}
	}
	
	// MARK: - Test Notification Preview & Trigger
	
	private var testTriggerSection: some View {
		let preview = notificationManager.previewContent(for: selectedKind)
		let hasPendingTests = notificationManager.pendingRequests.contains { $0.isTest }
		
		return VStack(alignment: .leading, spacing: 10) {
			SettingsSectionHeader("Test Notification")
			
			SettingsCard {
				VStack(spacing: 0) {
					VStack(alignment: .leading, spacing: 8) {
						HStack(spacing: 8) {
							Image(systemName: "text.bubble")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.tint)
							
							Text("Alert Type")
								.font(.caption.weight(.medium))
								.foregroundStyle(.secondary)
						}
						
						Menu {
							ForEach(TestNotificationKind.allCases) { kind in
								Button {
									selectedKind = kind
								} label: {
									if selectedKind == kind {
										Label(kind.title, systemImage: "checkmark")
									} else {
										Text(kind.title)
									}
								}
							}
						} label: {
							HStack(spacing: 8) {
								Text(selectedKind.title)
									.font(.subheadline.weight(.medium))
									.foregroundStyle(.primary)
									.lineLimit(1)
									.minimumScaleFactor(0.85)
								
								Spacer(minLength: 8)
								
								Image(systemName: "chevron.up.chevron.down")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.tint)
							}
							.padding(.horizontal, 12)
							.padding(.vertical, 10)
							.frame(maxWidth: .infinity)
							.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
						}
					}
					.padding(.horizontal, 16)
					.padding(.vertical, 12)
					
					SettingsRowDivider(leadingInset: 16)
					
					VStack(alignment: .leading, spacing: 8) {
						Text("Delay")
							.font(.caption.weight(.medium))
							.foregroundStyle(.secondary)
						
						Picker("Delay", selection: $selectedDelay) {
							ForEach(TestNotificationDelay.allCases) { delay in
								Text(delay.label).tag(delay)
							}
						}
						.pickerStyle(.segmented)
					}
					.padding(.horizontal, 16)
					.padding(.vertical, 12)
					
					SettingsRowDivider()
					
					Button {
						Task { await triggerTestNotification() }
					} label: {
						HStack {
							Image(systemName: "paperplane.fill")
								.font(.system(size: 16))
							Text("Send Test Notification")
								.font(.body.weight(.semibold))
							Spacer()
						}
						.foregroundStyle(.tint)
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					
					if hasPendingTests {
						SettingsRowDivider()
						
						Button(role: .destructive) {
							Task {
								await notificationManager.cancelTestNotifications()
								testFeedback = "Cancelled pending test notifications."
							}
						} label: {
							HStack {
								Image(systemName: "xmark.circle")
									.font(.system(size: 16))
								Text("Cancel Pending Test Notifications")
									.font(.body)
								Spacer()
							}
							.foregroundStyle(.red)
							.padding(.horizontal, 16)
							.padding(.vertical, 12)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				}
			}
			
			bannerPreviewCard(preview)
			
			if let testFeedback {
				HStack(spacing: 8) {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(.green)
					Text(testFeedback)
						.font(.footnote)
						.foregroundStyle(.primary)
				}
				.padding(12)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			}
			
			if let testError {
				VStack(alignment: .leading, spacing: 6) {
					HStack(spacing: 8) {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
						Text(testError)
							.font(.footnote)
					}
					Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
						Text("Open iOS Settings")
							.font(.footnote.weight(.semibold))
							.foregroundStyle(.orange)
					}
				}
				.padding(12)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			}
			
			SettingsFooter("Use 'Now' to preview an immediate iOS banner in-app, or '5s' / '30s' to lock your screen and verify Lock Screen formatting and tap-to-open routing.")
		}
	}
	
	private func bannerPreviewCard(_ preview: NotificationPreviewContent) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Banner Preview")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			HStack(alignment: .top, spacing: 12) {
				ZStack {
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(Color.accentColor.opacity(0.18))
					Image(systemName: "bell.badge.fill")
						.font(.system(size: 18))
						.foregroundStyle(Color.accentColor)
				}
				.frame(width: 38, height: 38)
				
				VStack(alignment: .leading, spacing: 2) {
					HStack {
						Text(preview.title)
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.primary)
							.lineLimit(1)
						Spacer()
						Text("now")
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
					
					if let subtitle = preview.subtitle, !subtitle.isEmpty {
						Text(subtitle)
							.font(.caption.weight(.medium))
							.foregroundStyle(.primary.opacity(0.85))
							.lineLimit(1)
					}
					
					Text(preview.body)
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.padding(14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.stroke(Color.separator.opacity(0.25), lineWidth: 0.5)
			}
		}
	}
	
	// MARK: - Live Store Check
	
	private var liveStoreCheckSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			SettingsSectionHeader("Live Store Check")
			
			SettingsCard {
				VStack(spacing: 0) {
					Toggle(isOn: $postDiagnosticAlerts) {
						HStack(spacing: 14) {
							Image(systemName: "bell.circle")
								.font(.system(size: 18))
								.foregroundStyle(.tint)
								.frame(width: 24)
							
							Text("Post Alert on Match")
								.font(.body)
						}
					}
					.padding(.horizontal, 16)
					.padding(.vertical, 12)
					
					SettingsRowDivider()
					
					Button {
						Task {
							_ = await notificationManager.runDiagnosticStoreCheck(postAlertsIfFound: postDiagnosticAlerts)
						}
					} label: {
						HStack {
							Image(systemName: "arrow.triangle.2.circlepath")
								.font(.system(size: 16))
							Text("Run Live Store Check Now")
								.font(.body.weight(.semibold))
							Spacer()
							if notificationManager.isCheckingStore {
								ProgressView()
									.controlSize(.small)
							}
						}
						.foregroundStyle(.tint)
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.disabled(notificationManager.isCheckingStore)
				}
			}
			
			if let report = notificationManager.lastManualReport {
				SettingsCard {
					VStack(alignment: .leading, spacing: 6) {
						diagnosticRow("Checked", value: report.checkedAt.formatted(date: .omitted, time: .standard))
						diagnosticRow("Accounts", value: "\(report.accountsSucceeded)/\(report.accountsAttempted) succeeded")
						if let key = report.rotationKey {
							diagnosticRow("Rotation", value: key)
						}
						diagnosticRow(
							"Wishlist Matches",
							value: report.wishlistMatchNames.isEmpty ? "None" : report.wishlistMatchNames.joined(separator: ", ")
						)
						diagnosticRow(
							"Bundles",
							value: report.activeBundleNames.isEmpty ? "None" : report.activeBundleNames.joined(separator: ", ")
						)
						diagnosticRow("Night Market", value: report.nightMarketActive ? "Active" : "Inactive")
						diagnosticRow(
							"Alerts Posted",
							value: report.notificationsPosted.isEmpty ? "None" : report.notificationsPosted.joined(separator: ", ")
						)
						if !report.errors.isEmpty {
							diagnosticRow("Errors", value: report.errors.joined(separator: " | "))
						}
					}
					.padding(14)
				}
			}
			
			SettingsCard {
				VStack(alignment: .leading, spacing: 6) {
					diagnosticRow("Background Refresh", value: backgroundRefreshLabel)
					if let lastBg = notificationManager.state.lastBackgroundCheckAt {
						diagnosticRow(
							"Last Check",
							value: "\(lastBg.formatted(date: .abbreviated, time: .shortened)) (\(notificationManager.state.lastBackgroundCheckSource ?? "Auto"))"
						)
					} else {
						diagnosticRow("Last Check", value: "Never run")
					}
					if let summary = notificationManager.state.lastBackgroundCheckSummary {
						diagnosticRow("Last Result", value: summary)
					}
					if let scheduleError = notificationManager.state.lastBackgroundScheduleError {
						diagnosticRow("Schedule Error", value: scheduleError)
					}
				}
				.padding(14)
			}
			
			SettingsFooter("Runs the exact same store-fetching and wishlist-matching pipeline used by iOS Background App Refresh.")
		}
	}
	
	// MARK: - Pending iOS Queue
	
	private var pendingQueueSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				SettingsSectionHeader("Scheduled iOS Queue (\(notificationManager.pendingRequests.count))")
				
				Spacer()
				
				Button("Resync") {
					isResyncing = true
					Task {
						await notificationManager.syncSchedules()
						isResyncing = false
					}
				}
				.font(.footnote.weight(.medium))
				.disabled(isResyncing)
			}
			.padding(.trailing, 8)
			
			SettingsCard {
				if notificationManager.pendingRequests.isEmpty {
					Text("No notifications currently scheduled.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(16)
				} else {
					VStack(spacing: 0) {
						ForEach(Array(notificationManager.pendingRequests.enumerated()), id: \.element.id) { index, item in
							if index > 0 {
								SettingsRowDivider(leadingInset: 16)
							}
							VStack(alignment: .leading, spacing: 4) {
								HStack(spacing: 6) {
									Text(item.title)
										.font(.subheadline.weight(.semibold))
									if item.isTest {
										Text("TEST")
											.font(.caption2.bold())
											.foregroundStyle(.orange)
											.padding(.horizontal, 6)
											.padding(.vertical, 2)
											.background(Color.orange.opacity(0.16), in: Capsule())
									}
									Spacer()
									if let triggerDate = item.nextTriggerDate {
										Text(triggerDate.formatted(date: .abbreviated, time: .shortened))
											.font(.caption2.monospacedDigit())
											.foregroundStyle(.secondary)
									}
								}
								
								if let subtitle = item.subtitle, !subtitle.isEmpty {
									Text(subtitle)
										.font(.caption.weight(.medium))
										.foregroundStyle(.primary.opacity(0.85))
								}
								
								Text(item.body)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 16)
							.padding(.vertical, 12)
						}
					}
				}
			}
		}
	}
	
	private func diagnosticRow(_ label: String, value: String) -> some View {
		HStack(alignment: .top, spacing: 8) {
			Text(label)
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
				.frame(width: 112, alignment: .leading)
			Text(value)
				.font(.caption)
				.foregroundStyle(.primary)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
	
	private var backgroundRefreshLabel: String {
		switch notificationManager.backgroundRefreshStatus {
		case .available: return "Available"
		case .denied: return "Disabled in iOS Settings"
		case .restricted: return "Restricted"
		@unknown default: return "Unknown"
		}
	}
	
	private func triggerTestNotification() async {
		testError = nil
		testFeedback = nil
		do {
			let fireDate = try await notificationManager.scheduleTestNotification(
				kind: selectedKind,
				delay: selectedDelay
			)
			if selectedDelay == .now {
				testFeedback = "Test notification triggered (\(selectedKind.title))."
			} else {
				testFeedback = "Scheduled \(selectedKind.title) for \(fireDate.formatted(date: .omitted, time: .standard)). Lock your screen now to inspect it on the Lock Screen."
			}
		} catch {
			testError = error.localizedDescription
		}
	}
}
