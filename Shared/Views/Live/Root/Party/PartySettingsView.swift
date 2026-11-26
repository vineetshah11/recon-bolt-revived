import SwiftUI
import ValorantAPI

struct PartySettingsView: View {
	@Binding var party: Party
	let userID: User.ID
	@Binding var shouldAutoShow: Bool
	var onPartyChanged: () async -> Void = {}
	var onStartPracticeRange: () async -> Void = {}
	
	@State private var isChangingQueue = false
	@State private var showingPartyCode = false
	@State private var showingCustomSettings = false
	@State private var isTogglingCustomMode = false
	@State private var showingInviteAlert = false
	@State private var inviteName = ""
	@State private var inviteTag = ""
	@State private var isConfirmingLeave = false
	@State private var isLeaving = false
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.dismiss) private var dismiss
	
	private var selfMember: Party.Member? {
		party.members.firstElement(withID: userID) ?? party.members.first
	}
	
	private var isOwner: Bool {
		selfMember?.isOwner == true
	}
	
	private var canEditMatchmakingSettings: Bool {
		isOwner && party.state != .inMatchmaking
	}
	
	private var canInvitePlayers: Bool {
		(isOwner || party.accessibility == .open) && party.state != .inMatchmaking
	}
	
	private var serversSummaryText: String {
		let total = selfMember?.pings.count ?? 0
		let selected = party.matchmakingData.preferredGamePods.count
		guard total > 0 else { return "-" }
		if selected == 0 {
			return "\(total) / \(total)"
		}
		return "\(selected) / \(total)"
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					headerCard
					coreSettingsCard
					invitePlayersSection
					practiceAndMatchSection
					if party.members.count > 1 {
						leavePartyButton
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 14)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Party Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
							.fontWeight(.semibold)
							.foregroundStyle(Color.accentColor)
					}
					.accessibilityLabel("Close")
				}
			}
			.sheet(isPresented: $showingPartyCode) {
				PartyCodeSheet(
					party: $party,
					isOwner: isOwner,
					onPartyChanged: onPartyChanged
				)
			}
			.sheet(isPresented: $showingCustomSettings) {
				PartyCustomGameSettingsSheet(
					party: $party,
					userID: userID,
					onPartyChanged: onPartyChanged
				)
			}
			.alert("Invite Player", isPresented: $showingInviteAlert) {
				TextField("Name", text: $inviteName)
					.autocorrectionDisabled()
				TextField("Tag", text: $inviteTag)
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
				Button("Cancel", role: .cancel) {}
				Button("Invite") {
					sendNameTagInvite()
				}
				.disabled(
					inviteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
					|| inviteTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				)
			} message: {
				Text("Enter the Riot ID of the player you want to invite.")
			}
		}
	}
	
	private var headerCard: some View {
		VStack(alignment: .leading, spacing: 8) {
			Image(systemName: "gearshape")
				.font(.system(size: 32, weight: .regular))
				.foregroundStyle(Color.accentColor)
			
			Text("Party Settings")
				.font(.title3.bold())
			
			Text("Adjust your queue, manage party codes, and configure server preferences.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(18)
		.background(
			Color.secondaryGroupedBackground,
			in: RoundedRectangle(cornerRadius: 18, style: .continuous)
		)
	}
	
	private var coreSettingsCard: some View {
		VStack(spacing: 0) {
			HStack(spacing: 14) {
				Image(systemName: "list.bullet")
					.font(.body.weight(.medium))
					.foregroundStyle(Color.accentColor)
					.frame(width: 24)
				
				Text("Queue")
					.font(.body)
				
				Spacer()
				
				if isChangingQueue {
					ProgressView()
				} else {
					Menu {
						ForEach(party.eligibleQueues ?? [], id: \.self) { queue in
							Button {
								changeQueue(to: queue)
							} label: {
								HStack {
									QueueLabel(queue: queue)
									if queue == party.matchmakingData.queueID {
										Image(systemName: "checkmark")
									}
								}
							}
						}
					} label: {
						HStack(spacing: 6) {
							QueueLabel(queue: party.matchmakingData.queueID)
							Image(systemName: "chevron.up.chevron.down")
								.font(.caption.weight(.semibold))
						}
						.foregroundStyle(Color.accentColor)
					}
					.disabled(!canEditMatchmakingSettings || (party.eligibleQueues ?? []).isEmpty)
					.opacity(canEditMatchmakingSettings ? 1 : 0.6)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			
			Divider()
				.padding(.leading, 54)
			
			Button {
				showingPartyCode = true
			} label: {
				HStack(spacing: 14) {
					Image(systemName: "rectangle.and.pencil.and.ellipsis")
						.font(.body.weight(.medium))
						.foregroundStyle(Color.accentColor)
						.frame(width: 24)
					
					Text("Party Code")
						.font(.body)
						.foregroundStyle(.primary)
					
					Spacer()
					
					Text(party.inviteCode.isEmpty ? "-" : party.inviteCode)
						.font(party.inviteCode.isEmpty ? .body : .body.monospaced())
						.foregroundStyle(.secondary)
					
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.tertiary)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 14)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			
			Divider()
				.padding(.leading, 54)
			
			NavigationLink {
				PartyServerSelectionView(party: $party, userID: userID, isOwner: isOwner)
			} label: {
				HStack(spacing: 14) {
					Image(systemName: "server.rack")
						.font(.body.weight(.medium))
						.foregroundStyle(Color.accentColor)
						.frame(width: 24)
					
					Text("Servers")
						.font(.body)
						.foregroundStyle(.primary)
					
					Spacer()
					
					Text(serversSummaryText)
						.font(.body)
						.monospacedDigit()
						.foregroundStyle(.secondary)
					
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.tertiary)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 14)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
		}
		.background(
			Color.secondaryGroupedBackground,
			in: RoundedRectangle(cornerRadius: 18, style: .continuous)
		)
	}
	
	private var invitePlayersSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Invite Players")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 6)
			
			VStack(spacing: 0) {
				NavigationLink {
					PartyInviteFriendsView(party: $party, userID: userID)
				} label: {
					HStack(spacing: 14) {
						Image(systemName: "person.2")
							.font(.body.weight(.medium))
							.foregroundStyle(Color.accentColor)
							.frame(width: 24)
						
						Text("Invite Friends")
							.font(.body)
							.foregroundStyle(.primary)
						
						Spacer()
						
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.tertiary)
					}
					.padding(.horizontal, 16)
					.padding(.vertical, 14)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				
				Divider()
					.padding(.leading, 54)
				
				Button {
					inviteName = ""
					inviteTag = ""
					showingInviteAlert = true
				} label: {
					HStack(spacing: 14) {
						Image(systemName: "person.badge.plus")
							.font(.body.weight(.medium))
							.foregroundStyle(Color.accentColor)
							.frame(width: 24)
						
						Text("Invite by Name & Tag")
							.font(.body)
							.foregroundStyle(Color.accentColor)
						
						Spacer()
					}
					.padding(.horizontal, 16)
					.padding(.vertical, 14)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.disabled(!canInvitePlayers)
				.opacity(canInvitePlayers ? 1 : 0.45)
			}
			.background(
				Color.secondaryGroupedBackground,
				in: RoundedRectangle(cornerRadius: 18, style: .continuous)
			)
		}
	}
	
	private var practiceAndMatchSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Practice & Match")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 6)
			
			VStack(spacing: 0) {
				if party.isCustomGame {
					Button {
						showingCustomSettings = true
					} label: {
						HStack(spacing: 14) {
							Image(systemName: "slider.horizontal.3")
								.font(.body.weight(.medium))
								.foregroundStyle(Color.accentColor)
								.frame(width: 24)
							
							Text("Custom Game Settings")
								.font(.body)
								.foregroundStyle(.primary)
							
							Spacer()
							
							Image(systemName: "chevron.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.tertiary)
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					
					Divider()
						.padding(.leading, 54)
					
					Button {
						switchCustomMode(enabled: false)
					} label: {
						HStack(spacing: 14) {
							Image(systemName: "arrow.uturn.backward")
								.font(.body.weight(.medium))
								.foregroundStyle(Color.accentColor)
								.frame(width: 24)
							
							Text("Return to Standard Queue")
								.font(.body)
								.foregroundStyle(Color.accentColor)
							
							Spacer()
							
							if isTogglingCustomMode {
								ProgressView()
							}
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.disabled(!canEditMatchmakingSettings || isTogglingCustomMode)
					.opacity(canEditMatchmakingSettings ? 1 : 0.45)
				} else {
					Button {
						switchCustomMode(enabled: true)
					} label: {
						HStack(spacing: 14) {
							Image(systemName: "wrench.and.screwdriver")
								.font(.body.weight(.medium))
								.foregroundStyle(Color.accentColor)
								.frame(width: 24)
							
							Text("Custom Game")
								.font(.body)
								.foregroundStyle(.primary)
							
							Spacer()
							
							if isTogglingCustomMode {
								ProgressView()
							} else {
								Image(systemName: "chevron.right")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.tertiary)
							}
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.disabled(!canEditMatchmakingSettings || isTogglingCustomMode)
					.opacity(canEditMatchmakingSettings ? 1 : 0.45)
				}
				
				Divider()
					.padding(.leading, 54)
				
				Button {
					dismiss()
					Task {
						await onStartPracticeRange()
					}
				} label: {
					HStack(spacing: 14) {
						Image(systemName: "scope")
							.font(.body.weight(.medium))
							.foregroundStyle(Color.accentColor)
							.frame(width: 24)
						
						Text("Practice Range")
							.font(.body)
							.foregroundStyle(.primary)
						
						Spacer()
						
						if party.members.count > 1 {
							Text("Solo only")
								.font(.caption)
								.foregroundStyle(.secondary)
						} else {
							Image(systemName: "chevron.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.tertiary)
						}
					}
					.padding(.horizontal, 16)
					.padding(.vertical, 14)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.disabled(party.members.count > 1 || party.state == .inMatchmaking)
				.opacity((party.members.count > 1 || party.state == .inMatchmaking) ? 0.45 : 1)
				
				Divider()
					.padding(.leading, 54)
				
				Toggle(isOn: $shouldAutoShow) {
					HStack(spacing: 14) {
						Image(systemName: "bolt.circle")
							.font(.body.weight(.medium))
							.foregroundStyle(Color.accentColor)
							.frame(width: 24)
						
						Text("Auto-open Live Match")
							.font(.body)
					}
				}
				.tint(Color.accentColor)
				.padding(.horizontal, 16)
				.padding(.vertical, 10)
			}
			.background(
				Color.secondaryGroupedBackground,
				in: RoundedRectangle(cornerRadius: 18, style: .continuous)
			)
		}
	}
	
	private var leavePartyButton: some View {
		Button(role: .destructive) {
			isConfirmingLeave = true
		} label: {
			HStack {
				Spacer()
				if isLeaving {
					ProgressView()
				} else {
					Text("Leave Party")
						.font(.body.weight(.semibold))
				}
				Spacer()
			}
			.padding(.vertical, 14)
			.background(
				Color.secondaryGroupedBackground,
				in: RoundedRectangle(cornerRadius: 18, style: .continuous)
			)
		}
		.disabled(isLeaving)
		.confirmationDialog(
			"Leave Party?",
			isPresented: $isConfirmingLeave,
			titleVisibility: .visible
		) {
			Button("Leave Party", role: .destructive) {
				leaveCurrentParty()
			}
		} message: {
			Text("You will leave your current party and return to a solo lobby.")
		}
	}
	
	private func changeQueue(to queue: QueueID) {
		Task {
			isChangingQueue = true
			defer { isChangingQueue = false }
			await load {
				party = try await $0.changeQueue(to: queue, in: party.id)
			}
		}
	}
	
	private func sendNameTagInvite() {
		let trimmedName = inviteName.trimmingCharacters(in: .whitespacesAndNewlines)
		let trimmedTag = inviteTag
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
		guard !trimmedName.isEmpty, !trimmedTag.isEmpty else { return }
		Task {
			await load {
				party = try await $0.inviteToParty(name: trimmedName, tag: trimmedTag, in: party.id)
			}
		}
	}
	
	private func switchCustomMode(enabled: Bool) {
		Task {
			isTogglingCustomMode = true
			defer { isTogglingCustomMode = false }
			let targetQueue = party.eligibleQueues?.first(where: { $0 == .unrated })
				?? party.eligibleQueues?.first
				?? .unrated
			var switched = false
			await load {
				if enabled {
					party = try await $0.makeCustomGame(in: party.id)
				} else {
					party = try await $0.makeDefaultQueue(targetQueue, in: party.id)
				}
				switched = true
			}
			if switched, enabled {
				showingCustomSettings = true
			}
		}
	}
	
	private func leaveCurrentParty() {
		Task {
			isLeaving = true
			defer { isLeaving = false }
			var left = false
			await load {
				try await $0.leaveParty(party.id)
				left = true
			}
			if left {
				await onPartyChanged()
				dismiss()
			}
		}
	}
}
