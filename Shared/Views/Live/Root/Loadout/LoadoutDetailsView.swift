import SwiftUI
import ValorantAPI
import CGeometry

struct LoadoutDetailsView: View {
	var fetchedLoadout: Loadout
	@State private var loadout: UpdatableLoadout
	/// Missing when the inventory couldn't be fetched. The loadout itself is still usable, so it's shown read-only.
	var inventory: Inventory?
	
	@Environment(\.valorantLoad) private var load
	
    var body: some View {
		let loadoutBinding = Binding { loadout } set: { newLoadout in
			loadout = newLoadout
			Task {
				await load {
					loadout = .init(try await $0.updateLoadout(to: .init(newLoadout)))
				}
			}
		}
		
		Group {
			if let inventory {
				LoadoutCustomizer(loadout: loadoutBinding, inventory: inventory)
			} else {
				LoadoutOverview(loadout: loadout)
			}
		}
		.buttonBorderShape(.capsule)
		.task(id: fetchedLoadout.version) {
			loadout = .init(fetchedLoadout)
		}
	}
}

extension LoadoutDetailsView {
	init(loadout: Loadout, inventory: Inventory?) {
		self.init(fetchedLoadout: loadout, loadout: .init(loadout), inventory: inventory)
	}
}

/// Read-only version of the loadout, used when the inventory couldn't be loaded (it's only needed for editing).
private struct LoadoutOverview: View {
	var loadout: UpdatableLoadout
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		VStack(spacing: 16) {
			PlayerCardImage.wide(loadout.identity.card)
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			
			PlayerTitleLabel(titleID: loadout.identity.title)
				.font(.subheadline.weight(.semibold))
			
			HStack(spacing: 12) {
				ForEach(Spray.Slot.ID.inCCWOrder, id: \.self) { slot in
					spraySlot(slot)
				}
			}
			
			weaponGrid
			
			VStack(spacing: 4) {
				Text("Inventory unavailable", comment: "Loadout: shown when the inventory could not be loaded")
					.font(.subheadline.weight(.semibold))
				Text("Your loadout is shown above, but items can't be changed until your inventory loads. Tap the refresh button to try again.", comment: "Loadout: shown when the inventory could not be loaded")
					.font(.caption)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
			}
			.padding(.top, 4)
		}
	}
	
	private func spraySlot(_ slot: Spray.Slot.ID) -> some View {
		ZStack {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(Color(uiColor: .secondarySystemFill))
			
			if let spray = loadout.sprays[slot] {
				(assets?.sprays[spray]?.bestIcon).view()
					.padding(8)
			} else {
				Image(systemName: "nosign")
					.foregroundColor(.secondary)
			}
		}
		.aspectRatio(1, contentMode: .fit)
		.frame(maxWidth: .infinity)
	}
	
	private var weaponGrid: some View {
		LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
			ForEach(Weapon.ID.orderInCollection, id: \.self) { gunID in
				if let gun = loadout.guns[gunID], let resolved = assets?.resolveSkin(gun.skin.level) {
					let icon = resolved.chroma(gun.skin.chroma)?.displayIcon ?? resolved.displayIcon
					icon.view()
						.frame(height: 40)
						.frame(maxWidth: .infinity)
						.padding(6)
						.background(
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.fill(Color(uiColor: .tertiarySystemFill))
						)
				}
			}
		}
	}
}

private struct LoadoutCustomizer: View {
	@Binding var loadout: UpdatableLoadout
	var inventory: Inventory
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		cardPicker
		
		Divider()
		
		VStack(spacing: 16) {
			titlePicker
			
			sprayPicker
			
			NavigationLink {
				WeaponLoadoutView(loadout: $loadout, inventory: inventory)
			} label: {
				HStack {
					Text("Weapon Loadout")
					Image(systemName: "chevron.forward")
				}
			}
			.buttonStyle(.bordered)
		}
		.padding(.vertical)
	}
	
	var cardPicker: some View {
		NavigationLink {
			PlayerCardPicker(selection: $loadout.identity.card, inventory: inventory)
		} label: {
			PlayerCardImage.wide(loadout.identity.card)
				.overlay(alignment: .bottomTrailing) {
					Image(systemName: "pencil.circle.fill")
						.foregroundStyle(.regularMaterial)
						.font(.system(size: 24))
						.padding(8)
				}
		}
	}
	
	var titlePicker: some View {
		NavigationLink {
			PlayerTitlePicker(selection: $loadout.identity.title, inventory: inventory)
		} label: {
			HStack {
				PlayerTitleLabel(titleID: loadout.identity.title)
				
				Image(systemName: "pencil.circle.fill")
					.foregroundColor(.secondary)
					.padding(.trailing, -4)
			}
			.foregroundColor(.primary)
		}
		.buttonStyle(.bordered)
	}
	
	var sprayPicker: some View {
		GeometryReader { geometry in
			let circleRadius: CGFloat = geometry.size.width / 2
			let center = CGPoint(x: circleRadius, y: circleRadius)
			let innerRadius = 0.3 * circleRadius
			let sprayCellSize = 0.8 * (circleRadius - innerRadius)
			let slots = Spray.Slot.ID.inCCWOrder
			let slotCount = CGFloat(slots.count)
			let angleOffset = Angle.radians(CGFloat.pi / slotCount)
			let lineWidth: CGFloat = 2
			let spacing: CGFloat = 8
			let areaColor = Color(uiColor: .secondarySystemFill)
			let lineColor = Color.secondary
			
			ForEach(slots.indexed(), id: \.element) { index, slot in
				let angle = Angle.radians(2 * CGFloat.pi * (CGFloat(index) / slotCount))
				let path = Path.donutPart(
					startAngle: angle - angleOffset,
					endAngle: angle + angleOffset,
					innerRadius: innerRadius,
					outerRadius: circleRadius
				)
				
				NavigationLink {
					SprayPicker(selection: $loadout.sprays[slot], inventory: inventory)
				} label: {
					sprayIcon(for: slot)
						.frame(width: sprayCellSize, height: sprayCellSize)
						.mask(RoundedRectangle(cornerRadius: 16, style: .continuous))
						.position(center + CGVector(angle: angle.radians, length: (circleRadius + innerRadius) / 2))
						.contentShape(path)
						.background {
							path.fill(areaColor)
							path.stroke(lineWidth: lineWidth + 2 * spacing)
								.blendMode(.destinationOut)
							path.stroke(areaColor, lineWidth: lineWidth)
							path.stroke(lineColor, lineWidth: lineWidth)
						}
				}
				.buttonStyle(.plain)
				.compositingGroup()
			}
			
			ForEach(slots.indices, id: \.self) { index in
				let angle = Angle.radians(2 * CGFloat.pi * (CGFloat(index) / slotCount))
				
				ZStack {
					Capsule().stroke(lineWidth: lineWidth + spacing).blendMode(.destinationOut)
					Capsule().fill(areaColor)
					Capsule().fill(lineColor)
				}
				.frame(width: 1.2 * circleRadius - innerRadius, height: lineWidth)
				.position(center + CGVector(dx: (circleRadius + innerRadius) / 2, dy: 0))
				.rotationEffect(angle + angleOffset)
			}
		}
		.compositingGroup()
		.aspectRatio(1, contentMode: .fit)
		.frame(maxWidth: 400)
		.padding(.horizontal)
	}
	
	@ViewBuilder
	func sprayIcon(for slot: Spray.Slot.ID) -> some View {
		if let spray = loadout.sprays[slot] {
			(assets?.sprays[spray]?.bestIcon).view()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			Color.clear
		}
	}
	
	struct SprayCell: View {
		var slot: Spray.Slot.ID
		@Binding var spray: Spray.ID?
		var inventory: Inventory
		
		@Environment(\.assets) private var assets
		
		var body: some View {
			NavigationLink {
				SprayPicker(selection: $spray, inventory: inventory)
			} label: {
				if let spray {
					(assets?.sprays[spray]?.bestIcon).view()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else {
					Color.clear
				}
			}
			.buttonStyle(.plain)
		}
	}
}

private extension Path {
	static func donutPart(
		startAngle: Angle, endAngle: Angle,
		innerRadius: CGFloat, outerRadius: CGFloat
	) -> Self {
		.init {
			let center = CGPoint(x: outerRadius, y: outerRadius)
			let isClockwise = startAngle > endAngle
			$0.addArc(center: center, radius: innerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: isClockwise)
			$0.addLine(to: center + .init(angle: endAngle.radians, length: outerRadius))
			$0.addArc(center: center, radius: outerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: !isClockwise)
			$0.closeSubpath()
		}
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
		.navigationTitle("Loadout")
		.withToolbar()
	}
}
#endif
