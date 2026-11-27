import SwiftUI
import ValorantAPI

struct RefreshableBox<Content: View>: View {
	var title: LocalizedStringKey
	@Binding var isExpanded: Bool
	var isTabActive: Bool = true
	var refreshCooldown: TimeInterval = 60
	var autoRefreshDelay: Duration = .milliseconds(160)
	@ViewBuilder var content: () -> Content
	var refresh: (ValorantClient) async throws -> Void
	
	@State private var lastRefreshDate: Date?
	@State private var isRefreshing = false
	@Environment(\.valorantLoad) private var load
	
	private struct RefreshTrigger: Equatable {
		var isExpanded: Bool
		var isTabActive: Bool
	}
	
	var body: some View {
		VStack(spacing: 0) {
			HStack {
				ExpandButton(isExpanded: $isExpanded) {
					HStack {
						Text(title)
						
						Spacer()
					}
				}
				.padding()
				
				AsyncButton(action: manualRefresh) {
					Image(systemName: "arrow.clockwise")
						.padding()
				}
			}
			.font(.title2.weight(.semibold))
			
			if isExpanded {
				Divider()
				
				content()
					.groupBoxStyle(NestedGroupBoxStyle())
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
		.background {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(Color.secondaryGroupedBackground)
				.shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
		}
		.task(id: RefreshTrigger(isExpanded: isExpanded, isTabActive: isTabActive)) {
			guard isExpanded, isTabActive else { return }
			if let lastRefreshDate, Date.now.timeIntervalSince(lastRefreshDate) < refreshCooldown {
				return
			}
			if autoRefreshDelay > .zero {
				try? await Task.sleep(for: autoRefreshDelay)
				guard !Task.isCancelled else { return }
			}
			await doRefresh(force: false)
		}
		.onSceneActivation {
			guard isExpanded, isTabActive else { return }
			await doRefresh(force: true)
		}
	}
	
	@Sendable
	private func manualRefresh() async {
		await doRefresh(force: true)
	}
	
	private func doRefresh(force: Bool) async {
		guard !isRefreshing else { return }
		if !force, let lastRefreshDate, Date.now.timeIntervalSince(lastRefreshDate) < refreshCooldown {
			return
		}
		isRefreshing = true
		defer { isRefreshing = false }
		var didSucceed = false
		await load { client in
			try await refresh(client)
			didSucceed = true
		}
		if didSucceed {
			lastRefreshDate = .now
		}
	}
	
	#if DEBUG
	func forPreviews() -> some View {
		self.padding()
			.background(Color.groupedBackground)
			.shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
			.previewLayout(.sizeThatFits)
	}
	#endif
	
	private struct NestedGroupBoxStyle: GroupBoxStyle {
		func makeBody(configuration: Configuration) -> some View {
			VStack(spacing: 16) {
				configuration.content
			}
			.frame(maxWidth: .infinity)
			.padding()
			.background(Color.tertiaryGroupedBackground)
			.cornerRadius(8)
		}
	}
}
