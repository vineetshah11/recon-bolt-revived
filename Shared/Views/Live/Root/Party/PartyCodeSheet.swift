import SwiftUI
import ValorantAPI
import UIKit

struct PartyCodeSheet: View {
	@Binding var party: Party
	let isOwner: Bool
	var onPartyChanged: () async -> Void = {}
	
	@State private var isUpdating = false
	@State private var didCopyCode = false
	@State private var isShowingJoinAlert = false
	@State private var joinCodeInput = ""
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.dismiss) private var dismiss
	
	private var hasCode: Bool {
		!party.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
	
	private var canModifyCode: Bool {
		isOwner && party.state != .inMatchmaking && !isUpdating
	}
	
	var body: some View {
		VStack(spacing: 18) {
			HStack {
				Color.clear
					.frame(width: 34, height: 34)
				
				Spacer()
				
				Text("Party Code")
					.font(.headline)
				
				Spacer()
				
				Button {
					dismiss()
				} label: {
					Image(systemName: "xmark")
						.font(.subheadline.weight(.bold))
						.foregroundStyle(Color.accentColor)
						.frame(width: 34, height: 34)
						.background(Color.tertiaryGroupedBackground, in: Circle())
				}
			}
			.padding(.top, 14)
			
			VStack(spacing: 0) {
				if hasCode {
					Button {
						UIPasteboard.general.string = party.inviteCode
						didCopyCode = true
						Task {
							try? await Task.sleep(for: .seconds(1.5))
							didCopyCode = false
						}
					} label: {
						HStack {
							Text("Current Party Code")
								.foregroundStyle(.primary)
							Spacer()
							HStack(spacing: 8) {
								Text(party.inviteCode)
									.monospaced()
									.foregroundStyle(didCopyCode ? .green : .secondary)
								Image(systemName: didCopyCode ? "checkmark" : "doc.on.doc")
									.font(.subheadline)
									.foregroundStyle(didCopyCode ? Color.green : .secondary)
							}
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 14)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					
					Divider()
						.padding(.leading, 16)
					
					Button {
						disableCode()
					} label: {
						rowLabel("Disable Code", color: Color.accentColor)
					}
					.buttonStyle(.plain)
					.disabled(!canModifyCode)
					.opacity(canModifyCode ? 1 : 0.45)
				} else {
					Button {
						generateCode()
					} label: {
						rowLabel("Generate Code", color: Color.accentColor)
					}
					.buttonStyle(.plain)
					.disabled(!canModifyCode)
					.opacity(canModifyCode ? 1 : 0.45)
				}
				
				Divider()
					.padding(.leading, 16)
				
				Button {
					joinCodeInput = ""
					isShowingJoinAlert = true
				} label: {
					rowLabel("Join Party by Code", color: Color.accentColor)
				}
				.buttonStyle(.plain)
				.disabled(isUpdating)
			}
			.background(
				Color.secondaryGroupedBackground,
				in: RoundedRectangle(cornerRadius: 16, style: .continuous)
			)
			.overlay {
				if isUpdating {
					RoundedRectangle(cornerRadius: 16, style: .continuous)
						.fill(.ultraThinMaterial)
						.overlay { ProgressView() }
				}
			}
			
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 16)
		.background(Color.groupedBackground)
		.presentationDetents([.height(hasCode ? 260 : 220), .medium])
		.presentationDragIndicator(.visible)
		.alert("Join Party", isPresented: $isShowingJoinAlert) {
			TextField("Party Code", text: $joinCodeInput)
				.textInputAutocapitalization(.characters)
				.autocorrectionDisabled()
			Button("Cancel", role: .cancel) {}
			Button("Join") {
				joinByCode()
			}
			.disabled(joinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
		} message: {
			Text("Enter the invite code of the party you want to join.")
		}
	}
	
	private func rowLabel(_ title: LocalizedStringKey, color: Color) -> some View {
		HStack {
			Text(title)
				.foregroundStyle(color)
			Spacer()
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
		.contentShape(Rectangle())
	}
	
	private func generateCode() {
		Task {
			isUpdating = true
			defer { isUpdating = false }
			await load {
				party = try await $0.generatePartyCode(in: party.id)
			}
		}
	}
	
	private func disableCode() {
		Task {
			isUpdating = true
			defer { isUpdating = false }
			await load {
				party = try await $0.disablePartyCode(in: party.id)
			}
		}
	}
	
	private func joinByCode() {
		let normalized = joinCodeInput
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.uppercased()
		guard !normalized.isEmpty else { return }
		Task {
			isUpdating = true
			defer { isUpdating = false }
			var joined = false
			await load {
				_ = try await $0.joinPartyByCode(normalized)
				joined = true
			}
			if joined {
				await onPartyChanged()
				dismiss()
			}
		}
	}
}
