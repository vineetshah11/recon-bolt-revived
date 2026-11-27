import SwiftUI

struct AutoRefresher: View {
	@State private var isFilledUp = true
	@State private var lastRefreshDate: Date?
	@Environment(\.scenePhase) private var scenePhase
	
	var isPaused: Bool = false
	var initialDelay: Duration = .milliseconds(180)
	var refreshInterval: TimeInterval = 5
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
				var tx = Transaction()
				tx.disablesAnimations = true
				withTransaction(tx) {
					isFilledUp = true
				}
				guard isActive else { return }
				if initialDelay > .zero {
					try? await Task.sleep(for: initialDelay)
					guard !Task.isCancelled else { return }
				}
				if let lastRefreshDate {
					let elapsed = Date.now.timeIntervalSince(lastRefreshDate)
					if elapsed < refreshInterval {
						let remaining = refreshInterval - elapsed
						let tolerance: TimeInterval = min(1, remaining * 0.2)
						withAnimation(.easeOut(duration: remaining + tolerance)) {
							isFilledUp = false
						}
						await Task.sleep(seconds: remaining, tolerance: tolerance)
						guard !Task.isCancelled else { return }
						withAnimation(.easeIn(duration: 0.1)) {
							isFilledUp = true
						}
					}
				}
				while !Task.isCancelled {
					await refreshAction()
					guard !Task.isCancelled else { return }
					lastRefreshDate = .now
					
					let tolerance: TimeInterval = 1
					withAnimation(.easeOut(duration: refreshInterval + tolerance)) {
						isFilledUp = false
					}
					await Task.sleep(seconds: refreshInterval, tolerance: tolerance)
					guard !Task.isCancelled else { return }
					
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
