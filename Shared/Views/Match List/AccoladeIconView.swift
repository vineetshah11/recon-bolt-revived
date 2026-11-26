import SwiftUI

struct AccoladeIcon: View {
	let type: AccoladeType
	var size: CGFloat = 20
	
	var body: some View {
		Group {
			switch type {
			case .mvp:
				MVPEmblem()
			case .topFrag:
				TopFragShape()
					.fill()
			case .masterful:
				MasterfulShape()
					.fill()
			case .kills:
				CrossedDaggersShape()
					.fill()
			case .damage:
				DamageShockwaveShape()
					.fill()
			case .headshots:
				HeadshotReticleEmblem()
			case .firstBloods:
				FirstBloodShape()
					.fill(style: FillStyle(eoFill: true))
			case .aces:
				AceCrownShape()
					.fill()
			case .clutches:
				ClutchWingsShape()
					.fill()
			case .trades:
				TradesArrowsShape()
					.stroke(style: StrokeStyle(lineWidth: size * 0.105, lineCap: .butt, lineJoin: .miter))
			case .assists:
				bundledImage("accolades/assists")
			case .spikePlants:
				bundledImage("accolades/spike_plants") {
					SpikeFallbackShape()
						.fill(style: FillStyle(eoFill: true))
				}
			}
		}
		.frame(width: size, height: size)
	}
	
	@ViewBuilder
	private func bundledImage<Fallback: View>(
		_ name: String,
		@ViewBuilder fallback: () -> Fallback = { EmptyView() }
	) -> some View {
		if let uiImage = UIImage.bundledAsset(named: name) {
			Image(uiImage: uiImage)
				.renderingMode(.template)
				.resizable()
				.scaledToFit()
		} else {
			fallback()
		}
	}
}

struct NewBestBadge: View {
	var size: CGFloat = 15
	
	var body: some View {
		ZStack {
			Circle()
				.fill(Color(red: 0.96, green: 0.56, blue: 0.18))
			FourPointStarShape()
				.fill(Color(red: 0.11, green: 0.11, blue: 0.13))
				.frame(width: size * 0.56, height: size * 0.56)
		}
		.frame(width: size, height: size)
	}
}

struct AccoladePillView: View {
	let item: AccoladeMatchItem
	var showNewBest: Bool = false
	
	private let tint = Color(red: 0.78, green: 0.67, blue: 0.34)
	
	var body: some View {
		HStack(spacing: 5) {
			AccoladeIcon(type: item.type, size: 14)
				.foregroundStyle(tint)
			
			Text(item.type.title.uppercased())
				.font(.caption2.weight(.bold))
				.foregroundStyle(tint)
			
			Text(item.type.formattedValue(item.value))
				.font(.caption2.weight(.semibold).monospacedDigit())
				.foregroundStyle(tint.opacity(0.75))
			
			if showNewBest && item.isNewBest {
				NewBestBadge(size: 14)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(tint.opacity(0.14), in: Capsule())
		.overlay(
			Capsule()
				.stroke(tint.opacity(0.28), lineWidth: 1)
		)
		.fixedSize()
	}
}

// MARK: - Accolade Vector Emblems

private struct MVPEmblem: View {
	var body: some View {
		GeometryReader { geo in
			let side = min(geo.size.width, geo.size.height)
			ZStack {
				HexagonOutlineShape()
					.stroke(style: StrokeStyle(lineWidth: side * 0.095, lineJoin: .miter))
				FivePointStarShape()
					.fill()
					.frame(width: side * 0.48, height: side * 0.48)
			}
			.frame(width: geo.size.width, height: geo.size.height)
		}
	}
}

private struct HexagonOutlineShape: Shape {
	func path(in rect: CGRect) -> Path {
		let cx = rect.midX
		let cy = rect.midY
		let r = min(rect.width, rect.height) * 0.43
		var path = Path()
		for i in 0..<6 {
			let angle = (CGFloat(i) * .pi / 3) - (.pi / 2)
			let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
			if i == 0 {
				path.move(to: pt)
			} else {
				path.addLine(to: pt)
			}
		}
		path.closeSubpath()
		return path
	}
}

private struct FivePointStarShape: Shape {
	func path(in rect: CGRect) -> Path {
		let cx = rect.midX
		let cy = rect.midY
		let outerR = min(rect.width, rect.height) * 0.5
		let innerR = outerR * 0.40
		var path = Path()
		for i in 0..<10 {
			let r = i.isMultiple(of: 2) ? outerR : innerR
			let angle = (CGFloat(i) * .pi / 5) - (.pi / 2)
			let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
			if i == 0 {
				path.move(to: pt)
			} else {
				path.addLine(to: pt)
			}
		}
		path.closeSubpath()
		return path
	}
}

private struct FourPointStarShape: Shape {
	func path(in rect: CGRect) -> Path {
		let cx = rect.midX
		let cy = rect.midY
		let outer = min(rect.width, rect.height) * 0.5
		let inner = outer * 0.36
		var path = Path()
		for i in 0..<8 {
			let r = i.isMultiple(of: 2) ? outer : inner
			let angle = (CGFloat(i) * .pi / 4) - (.pi / 2)
			let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
			if i == 0 {
				path.move(to: pt)
			} else {
				path.addLine(to: pt)
			}
		}
		path.closeSubpath()
		return path
	}
}

private struct TopFragShape: Shape {
	func path(in rect: CGRect) -> Path {
		let cx = rect.midX
		let cy = rect.midY
		let s = min(rect.width, rect.height)
		let innerR = s * 0.11
		var path = Path()
		for i in 0..<16 {
			let angle = (CGFloat(i) * .pi / 8) - (.pi / 2)
			let r: CGFloat
			if i % 4 == 0 {
				// Long cardinal spikes (N/S slightly taller than E/W)
				r = (i % 8 == 0) ? s * 0.48 : s * 0.45
			} else if i % 2 == 0 {
				r = s * 0.30
			} else {
				r = innerR
			}
			let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
			if i == 0 {
				path.move(to: pt)
			} else {
				path.addLine(to: pt)
			}
		}
		path.closeSubpath()
		return path
	}
}

private struct MasterfulShape: Shape {
	func path(in rect: CGRect) -> Path {
		func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
		}
		var path = Path()
		path.move(to: p(0.25, 0.14))
		path.addLine(to: p(0.75, 0.14))
		path.addLine(to: p(0.94, 0.36))
		path.addLine(to: p(0.50, 0.90))
		path.addLine(to: p(0.06, 0.36))
		path.closeSubpath()
		return path
	}
}

private struct CrossedDaggersShape: Shape {
	func path(in rect: CGRect) -> Path {
		func addBlade(rotationAngle: CGFloat, to path: inout Path) {
			let w = rect.width
			let h = rect.height
			var blade = Path()
			blade.move(to: CGPoint(x: 0.50 * w, y: 0.04 * h))
			blade.addLine(to: CGPoint(x: 0.575 * w, y: 0.22 * h))
			blade.addLine(to: CGPoint(x: 0.55 * w, y: 0.72 * h))
			blade.addLine(to: CGPoint(x: 0.62 * w, y: 0.75 * h))
			blade.addLine(to: CGPoint(x: 0.62 * w, y: 0.80 * h))
			blade.addLine(to: CGPoint(x: 0.53 * w, y: 0.80 * h))
			blade.addLine(to: CGPoint(x: 0.53 * w, y: 0.95 * h))
			blade.addLine(to: CGPoint(x: 0.47 * w, y: 0.95 * h))
			blade.addLine(to: CGPoint(x: 0.47 * w, y: 0.80 * h))
			blade.addLine(to: CGPoint(x: 0.38 * w, y: 0.80 * h))
			blade.addLine(to: CGPoint(x: 0.38 * w, y: 0.75 * h))
			blade.addLine(to: CGPoint(x: 0.45 * w, y: 0.72 * h))
			blade.addLine(to: CGPoint(x: 0.425 * w, y: 0.22 * h))
			blade.closeSubpath()
			
			let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
				.rotated(by: rotationAngle)
				.translatedBy(x: -rect.midX, y: -rect.midY)
			path.addPath(blade.applying(transform))
		}
		var path = Path()
		addBlade(rotationAngle: .pi / 4.4, to: &path)
		addBlade(rotationAngle: -.pi / 4.4, to: &path)
		return path
	}
}

private struct DamageShockwaveShape: Shape {
	func path(in rect: CGRect) -> Path {
		func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
		}
		var path = Path()
		// Top-right sweeping crescent with inner notch (matching VALPAW Damage emblem)
		path.move(to: p(0.10, 0.34))
		path.addCurve(to: p(0.90, 0.56), control1: p(0.42, 0.04), control2: p(0.88, 0.14))
		path.addCurve(to: p(0.68, 0.42), control1: p(0.84, 0.46), control2: p(0.76, 0.42))
		path.addLine(to: p(0.64, 0.46))
		path.addLine(to: p(0.58, 0.38))
		path.addCurve(to: p(0.10, 0.34), control1: p(0.44, 0.24), control2: p(0.24, 0.24))
		path.closeSubpath()
		
		// 2x2 grid of 4 rotated squares (diamonds) in the lower-left
		let centers: [(CGFloat, CGFloat)] = [
			(0.29, 0.54),
			(0.49, 0.54),
			(0.29, 0.74),
			(0.49, 0.74),
		]
		let r: CGFloat = 0.082
		for (cx, cy) in centers {
			path.move(to: p(cx, cy - r))
			path.addLine(to: p(cx + r, cy))
			path.addLine(to: p(cx, cy + r))
			path.addLine(to: p(cx - r, cy))
			path.closeSubpath()
		}
		return path
	}
}

private struct HeadshotReticleEmblem: View {
	var body: some View {
		GeometryReader { geo in
			let side = min(geo.size.width, geo.size.height)
			ZStack {
				HeadshotReticleLinesShape()
					.stroke(style: StrokeStyle(lineWidth: side * 0.095, lineCap: .square))
				Circle()
					.frame(width: side * 0.18, height: side * 0.18)
			}
			.frame(width: geo.size.width, height: geo.size.height)
		}
	}
}

private struct HeadshotReticleLinesShape: Shape {
	func path(in rect: CGRect) -> Path {
		let cx = rect.midX
		let cy = rect.midY
		let s = min(rect.width, rect.height)
		let r = s * 0.30
		let innerTick = s * 0.20
		let outerTick = s * 0.45
		
		var path = Path()
		path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
		
		// Top, Bottom, Left, Right crosshair ticks
		path.move(to: CGPoint(x: cx, y: cy - outerTick))
		path.addLine(to: CGPoint(x: cx, y: cy - innerTick))
		path.move(to: CGPoint(x: cx, y: cy + innerTick))
		path.addLine(to: CGPoint(x: cx, y: cy + outerTick))
		path.move(to: CGPoint(x: cx - outerTick, y: cy))
		path.addLine(to: CGPoint(x: cx - innerTick, y: cy))
		path.move(to: CGPoint(x: cx + innerTick, y: cy))
		path.addLine(to: CGPoint(x: cx + outerTick, y: cy))
		return path
	}
}

private struct FirstBloodShape: Shape {
	func path(in rect: CGRect) -> Path {
		func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
		}
		var path = Path()
		// Sharp Valorant-style winged diamond emblem
		path.move(to: p(0.50, 0.10))
		path.addLine(to: p(0.66, 0.34))
		path.addLine(to: p(0.92, 0.44))
		path.addLine(to: p(0.70, 0.58))
		path.addLine(to: p(0.50, 0.90))
		path.addLine(to: p(0.30, 0.58))
		path.addLine(to: p(0.08, 0.44))
		path.addLine(to: p(0.34, 0.34))
		path.closeSubpath()
		
		// Inner diamond cutout
		path.move(to: p(0.50, 0.34))
		path.addLine(to: p(0.60, 0.50))
		path.addLine(to: p(0.50, 0.66))
		path.addLine(to: p(0.40, 0.50))
		path.closeSubpath()
		return path
	}
}

private struct AceCrownShape: Shape {
	func path(in rect: CGRect) -> Path {
		func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
		}
		var path = Path()
		// 5-spike crown crest
		path.move(to: p(0.14, 0.72))
		path.addLine(to: p(0.08, 0.32))
		path.addLine(to: p(0.28, 0.52))
		path.addLine(to: p(0.30, 0.22))
		path.addLine(to: p(0.43, 0.48))
		path.addLine(to: p(0.50, 0.14))
		path.addLine(to: p(0.57, 0.48))
		path.addLine(to: p(0.70, 0.22))
		path.addLine(to: p(0.72, 0.52))
		path.addLine(to: p(0.92, 0.32))
		path.addLine(to: p(0.86, 0.72))
		path.closeSubpath()
		
		// Sleek curved base bar
		path.move(to: p(0.16, 0.80))
		path.addLine(to: p(0.84, 0.80))
		path.addLine(to: p(0.80, 0.90))
		path.addLine(to: p(0.20, 0.90))
		path.closeSubpath()
		return path
	}
}

private struct ClutchWingsShape: Shape {
	func path(in rect: CGRect) -> Path {
		func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
		}
		var path = Path()
		// Winged V-crest
		path.move(to: p(0.50, 0.90))
		path.addLine(to: p(0.12, 0.46))
		path.addLine(to: p(0.20, 0.40))
		path.addLine(to: p(0.08, 0.28))
		path.addLine(to: p(0.22, 0.24))
		path.addLine(to: p(0.12, 0.12))
		path.addLine(to: p(0.34, 0.22))
		path.addLine(to: p(0.44, 0.44))
		path.addLine(to: p(0.50, 0.52))
		path.addLine(to: p(0.56, 0.44))
		path.addLine(to: p(0.66, 0.22))
		path.addLine(to: p(0.88, 0.12))
		path.addLine(to: p(0.78, 0.24))
		path.addLine(to: p(0.92, 0.28))
		path.addLine(to: p(0.80, 0.40))
		path.addLine(to: p(0.88, 0.46))
		path.closeSubpath()
		
		// Small centered vertical diamond in the upper V-notch
		path.move(to: p(0.50, 0.14))
		path.addLine(to: p(0.57, 0.26))
		path.addLine(to: p(0.50, 0.38))
		path.addLine(to: p(0.43, 0.26))
		path.closeSubpath()
		return path
	}
}

private struct TradesArrowsShape: Shape {
	func path(in rect: CGRect) -> Path {
		func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
		}
		var path = Path()
		// Upper-left arrow pointing down-left (↙), cleanly separated from lower-right arrow
		path.move(to: p(0.56, 0.14))
		path.addLine(to: p(0.22, 0.48))
		path.move(to: p(0.22, 0.24))
		path.addLine(to: p(0.22, 0.48))
		path.addLine(to: p(0.46, 0.48))
		
		// Lower-right arrow pointing up-right (↗)
		path.move(to: p(0.44, 0.86))
		path.addLine(to: p(0.78, 0.52))
		path.move(to: p(0.54, 0.52))
		path.addLine(to: p(0.78, 0.52))
		path.addLine(to: p(0.78, 0.76))
		return path
	}
}

private struct SpikeFallbackShape: Shape {
	func path(in rect: CGRect) -> Path {
		func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
		}
		var path = Path()
		path.move(to: p(0.12, 0.20))
		path.addLine(to: p(0.88, 0.20))
		path.addLine(to: p(0.50, 0.86))
		path.closeSubpath()
		path.addEllipse(in: CGRect(x: rect.minX + 0.38 * rect.width, y: rect.minY + 0.32 * rect.height, width: rect.width * 0.24, height: rect.height * 0.24))
		return path
	}
}
