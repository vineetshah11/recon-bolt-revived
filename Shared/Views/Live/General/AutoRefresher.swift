import SwiftUI

struct AutoRefresher: View {
	@State private var isFilledUp = true
	@Environment(\.scenePhase) private var scenePhase
	
	var isPaused: Bool = false
	var refreshAction: () async -> Void
	
	private var isActive: Bool {
		!isPaused && scenePhase == .active
	}
	
	var body: some View {
		let strokeStyle = StrokeStyle(lineWidth: 4, lineCap: .round)
		
		Circle()
			.trim(from: 0, to: isFilledUp ? 1 : 1e-3)
			.scale(x: -1)
			.rotation(.degrees(90))
			.stroke(Color.accentColor, style: strokeStyle)
			.background(Circle().stroke(.quaternary, style: strokeStyle))
			.frame(width: 20, height: 20)
			.task(id: isActive) {
				isFilledUp = true
				guard isActive else { return }
				while !Task.isCancelled {
					await refreshAction()
					guard !Task.isCancelled else { return }
					
					let refreshInterval: TimeInterval = 5
					let tolerance: TimeInterval = 1
					withAnimation(.easeOut(duration: refreshInterval + tolerance)) {
						isFilledUp = false
					}
					await Task.sleep(seconds: refreshInterval, tolerance: tolerance)
					
					withAnimation(.easeIn(duration: 0.1)) {
						isFilledUp = true
					}
				}
			}
	}
}

#if DEBUG
struct AutoRefresher_Previews: PreviewProvider {
	static var previews: some View {
		AutoRefresher {}
			.padding()
			.previewLayout(.sizeThatFits)
	}
}
#endif
