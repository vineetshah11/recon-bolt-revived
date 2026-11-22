import SwiftUI
import ValorantAPI

/// Interactive 4-slot expression wheel supporting both Sprays and Flex (Totems) at exact Riot positional indices.
struct SprayWheelView: View {
	@Binding var expressions: [Int: Loadout.Expression]
	var inventory: Inventory
	
	/// Riot's `ActiveExpressions` stores [bottom(0), left(1), top(2), right(3)],
	/// while visual wheel quadrants 0...3 go right(0°), bottom(90°), left(180°), top(270°).
	private static let dataIndicesForVisualSlice = [3, 0, 1, 2]
	
	@State private var activeSlotIndex: Int?
	
	var body: some View {
		GeometryReader { geometry in
			let size = min(geometry.size.width, geometry.size.height)
			let outerRadius = size / 2
			let innerRadius = size * 0.19
			let iconDistance = (outerRadius + innerRadius) / 2
			let iconSize = size * 0.25
			
			ZStack {
				ForEach(0..<4, id: \.self) { visualSlice in
					let dataIndex = Self.dataIndicesForVisualSlice[visualSlice]
					let centerAngle = Angle.degrees(Double(visualSlice) * 90)
					let sliceShape = WheelSliceShape(
						centerAngle: centerAngle,
						innerRadiusRatio: 0.38
					)
					
					Button {
						activeSlotIndex = dataIndex
					} label: {
						ZStack {
							sliceShape
								.fill(Color.secondaryGroupedBackground)
							sliceShape
								.stroke(Color.separator, lineWidth: 1.5)
							
							let expr = expressions[dataIndex] ?? .empty
							ExpressionImageView(expression: expr)
								.frame(width: iconSize, height: iconSize)
								.overlay(alignment: .bottomTrailing) {
									if expr.totem != nil {
										Image(systemName: "hand.raised.fingers.spread.fill")
											.font(.system(size: 10, weight: .bold))
											.foregroundStyle(.white)
											.padding(3)
											.background(Color.valorantRed, in: Circle())
											.offset(x: 4, y: 4)
									}
								}
								.offset(
									x: CGFloat(cos(centerAngle.radians)) * iconDistance,
									y: CGFloat(sin(centerAngle.radians)) * iconDistance
								)
						}
					}
					.buttonStyle(.plain)
				}
				
				Circle()
					.fill(Color.groupedBackground)
					.frame(width: innerRadius * 2, height: innerRadius * 2)
					.overlay {
						Circle()
							.stroke(Color.separator, lineWidth: 1.5)
					}
					.overlay {
						Image(systemName: "sparkles")
							.font(.title3.weight(.semibold))
							.foregroundStyle(.secondary)
					}
			}
			.frame(width: size, height: size)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.aspectRatio(1, contentMode: .fit)
		.frame(maxWidth: 280)
		.frame(maxWidth: .infinity)
		.sheet(isPresented: Binding(
			get: { activeSlotIndex != nil },
			set: { if !$0 { activeSlotIndex = nil } }
		)) {
			if let slotIndex = activeSlotIndex {
				NavigationStack {
					ExpressionPicker(
						selection: Binding(
							get: { expressions[slotIndex] ?? .empty },
							set: { newValue in
								var copy = expressions
								if newValue.isEmpty {
									copy.removeValue(forKey: slotIndex)
								} else {
									copy[slotIndex] = newValue
								}
								expressions = copy
							}
						),
						inventory: inventory
					)
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button("Done") { activeSlotIndex = nil }
						}
					}
				}
			}
		}
	}
}

private struct WheelSliceShape: Shape {
	var centerAngle: Angle
	var innerRadiusRatio: CGFloat
	var gapDegrees: Double = 4
	
	func path(in rect: CGRect) -> Path {
		let center = CGPoint(x: rect.midX, y: rect.midY)
		let outerRadius = min(rect.width, rect.height) / 2
		let innerRadius = outerRadius * innerRadiusRatio
		let halfSpan = 45 - gapDegrees / 2
		let startAngle = Angle.degrees(centerAngle.degrees - halfSpan)
		let endAngle = Angle.degrees(centerAngle.degrees + halfSpan)
		
		var path = Path()
		path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
		path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
		path.closeSubpath()
		return path
	}
}
