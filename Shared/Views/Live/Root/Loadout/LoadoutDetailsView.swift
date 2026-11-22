import SwiftUI
import ValorantAPI

struct LoadoutDetailsView: View {
	var fetchedLoadout: Loadout
	@State private var loadout: UpdatableLoadout
	var inventory: Inventory
	
	@LocalData private var summary: CareerSummary?
	@EnvironmentObject private var presetManager: LoadoutPresetManager
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	
	@State private var privacyExpanded = false
	@State private var showingRandomizeDialog = false
	@State private var showingShareSheet = false
	@State private var isRandomizing = false
	@State private var actRankHiddenOverride: Bool?
	
	init(loadout: Loadout, inventory: Inventory) {
		self.fetchedLoadout = loadout
		self._loadout = State(initialValue: .init(loadout))
		self.inventory = inventory
		self._summary = LocalData(id: loadout.subject)
	}
	
	var body: some View {
		let loadoutBinding = Binding { loadout } set: { newLoadout in
			loadout = newLoadout
			Task {
				await load {
					loadout = .init(try await $0.updateLoadout(to: .init(newLoadout)))
				}
			}
		}
		
		VStack(spacing: 12) {
			cardSection(loadoutBinding)
			
			changeTitleRow(loadoutBinding)
			
			weaponLoadoutRow(loadoutBinding)
			
			privacySettingsBox(loadoutBinding)
			
			presetsRows(loadoutBinding)
			
			Divider()
				.padding(.vertical, 4)
			
			SprayWheelView(expressions: loadoutBinding.expressions, inventory: inventory)
				.padding(.vertical, 4)
		}
		.withLocalData($summary, id: loadout.subject)
		.confirmationDialog(
			"Randomize Loadout",
			isPresented: $showingRandomizeDialog,
			titleVisibility: .visible
		) {
			Button("All Owned Items") {
				randomize(favoritesOnly: false)
			}
			Button("Favorites Only") {
				randomize(favoritesOnly: true)
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Replaces your equipped card, title, weapon skins, and expressions.")
		}
		.sheet(isPresented: $showingShareSheet) {
			LoadoutShareSheet(loadout: loadout)
		}
	}
	
	private func cardSection(_ loadoutBinding: Binding<UpdatableLoadout>) -> some View {
		NavigationLink {
			PlayerCardPicker(selection: loadoutBinding.identity.card, inventory: inventory)
		} label: {
			ZStack(alignment: .bottomTrailing) {
				PlayerCardImage.wide(loadout.identity.card)
					.cornerRadius(12)
				
				Image(systemName: "pencil")
					.font(.system(size: 14, weight: .bold))
					.foregroundStyle(.white)
					.frame(width: 30, height: 30)
					.background(Color.black.opacity(0.65), in: Circle())
					.padding(8)
			}
		}
		.buttonStyle(.plain)
	}
	
	private func changeTitleRow(_ loadoutBinding: Binding<UpdatableLoadout>) -> some View {
		NavigationLink {
			PlayerTitlePicker(selection: loadoutBinding.identity.title, inventory: inventory)
		} label: {
			LoadoutActionRow(
				icon: "pencil.line",
				title: "Change Title",
				trailing: {
					PlayerTitleLabel(titleID: loadout.identity.title)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			)
		}
		.buttonStyle(.plain)
	}
	
	private func weaponLoadoutRow(_ loadoutBinding: Binding<UpdatableLoadout>) -> some View {
		NavigationLink {
			WeaponLoadoutView(loadout: loadoutBinding, inventory: inventory)
		} label: {
			LoadoutActionRow(icon: "scope", title: "Weapon Loadout")
		}
		.buttonStyle(.plain)
	}
	
	private func privacySettingsBox(_ loadoutBinding: Binding<UpdatableLoadout>) -> some View {
		VStack(spacing: 0) {
			Button {
				withAnimation(.easeInOut(duration: 0.2)) {
					privacyExpanded.toggle()
				}
			} label: {
				HStack(spacing: 12) {
					Image(systemName: "hand.raised.fill")
						.foregroundStyle(Color.valorantRed)
						.frame(width: 24)
					Text("Privacy Settings")
						.font(.body.weight(.medium))
					Spacer()
					Image(systemName: privacyExpanded ? "chevron.up" : "chevron.down")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				.padding(14)
			}
			.buttonStyle(.plain)
			
			if privacyExpanded {
				Divider()
					.padding(.horizontal, 12)
				
				VStack(spacing: 12) {
					privacyToggleRow(
						title: "Incognito",
						subtitle: "Hides your name from players outside your party.",
						isOn: loadoutBinding.isIncognito
					)
					
					privacyToggleRow(
						title: "Hide Account Level",
						subtitle: "Hides your account level from other players.",
						isOn: loadoutBinding.identity.isLevelHidden
					)
					
					privacyToggleRow(
						title: "Hide Previous Act Rank",
						subtitle: "Hides your previous act rank from your player card.",
						isOn: Binding(
							get: { actRankHiddenOverride ?? summary?.isActRankBadgeHidden ?? false },
							set: { newValue in
								actRankHiddenOverride = newValue
								Task {
									await load { client in
										try await client.setActRankBadgeHidden(newValue)
										try await client.fetchCareerSummary(for: loadout.subject, forceFetch: true)
									}
								}
							}
						)
					)
				}
				.padding(14)
				.background(Color.secondaryGroupedBackground.opacity(0.6))
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
	}
	
	private func privacyToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
		Toggle(isOn: isOn) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.subheadline.weight(.medium))
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
		.tint(Color.valorantRed)
	}
	
	private func presetsRows(_ loadoutBinding: Binding<UpdatableLoadout>) -> some View {
		VStack(spacing: 8) {
			NavigationLink {
				LoadoutPresetsView(loadout: loadoutBinding, inventory: inventory, favoritesOnly: false)
			} label: {
				LoadoutActionRow(icon: "square.stack.3d.up.fill", title: "Loadout Presets")
			}
			.buttonStyle(.plain)
			
			NavigationLink {
				LoadoutPresetsView(loadout: loadoutBinding, inventory: inventory, favoritesOnly: true)
			} label: {
				LoadoutActionRow(icon: "star.square.on.square.fill", title: "Favorites Presets")
			}
			.buttonStyle(.plain)
			
			Button {
				showingRandomizeDialog = true
			} label: {
				LoadoutActionRow(
					icon: "dice.fill",
					title: isRandomizing ? "Randomizing..." : "Randomize",
					showChevron: false
				)
			}
			.buttonStyle(.plain)
			.disabled(isRandomizing)
			
			Button {
				showingShareSheet = true
			} label: {
				LoadoutActionRow(icon: "square.and.arrow.up", title: "Share")
			}
			.buttonStyle(.plain)
		}
	}
	
	private func randomize(favoritesOnly: Bool) {
		guard let assets else { return }
		isRandomizing = true
		Task {
			defer { isRandomizing = false }
			await load { client in
				let favs: Favorites? = favoritesOnly ? (try? await client.getFavorites()) : nil
				let randomized = LoadoutPresetManager.randomizedLoadout(
					from: loadout,
					inventory: inventory,
					assets: assets,
					favorites: favs
				)
				loadout = .init(try await client.updateLoadout(to: .init(randomized)))
			}
		}
	}
}

private struct LoadoutActionRow<Trailing: View>: View {
	var icon: String
	var title: LocalizedStringKey
	var showChevron = true
	@ViewBuilder var trailing: () -> Trailing
	
	init(
		icon: String,
		title: LocalizedStringKey,
		showChevron: Bool = true,
		@ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
	) {
		self.icon = icon
		self.title = title
		self.showChevron = showChevron
		self.trailing = trailing
	}
	
	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.foregroundStyle(Color.valorantRed)
				.frame(width: 24)
			Text(title)
				.font(.body.weight(.medium))
			Spacer()
			trailing()
			if showChevron {
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
	}
}

#if DEBUG
struct LoadoutDetailsView_Previews: PreviewProvider {
	static var previews: some View {
		ScrollView {
			RefreshableBox(title: "Loadout", isExpanded: .constant(true)) {
				LoadoutDetailsView(loadout: PreviewData.loadout, inventory: PreviewData.inventory)
			} refresh: { _ in }
				.forPreviews()
		}
		.environmentObject(LoadoutPresetManager())
		.navigationTitle("Loadout")
		.withToolbar()
	}
}
#endif
