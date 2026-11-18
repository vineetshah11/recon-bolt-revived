import SwiftUI
import ValorantAPI
import HandyOperators

struct MatchDetailsView: View {
	let data: MatchViewData
	@State var highlight = PlayerHighlightInfo()
	@State private var tab: Tab = .scoreboard
	
	private enum Tab: Hashable {
		case scoreboard
		case performance
	}
	
	private static let startDateFormatter = DateFormatter() <- {
		$0.dateStyle = .short
	}
	private static let startTimeFormatter = DateFormatter() <- {
		$0.timeStyle = .short
	}
	private static let gameLengthFormatter = DateComponentsFormatter() <- {
		$0.unitsStyle = .abbreviated
		$0.allowedUnits = [.hour, .minute, .second]
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				MatchDetailsHero(data: data)
					.edgesIgnoringSafeArea(.horizontal)
				
				HStack {
					let matchInfo = data.details.matchInfo
					
					Text(matchInfo.gameStart, formatter: Self.startDateFormatter)
						.foregroundColor(.white)
					Text(matchInfo.gameStart, formatter: Self.startTimeFormatter)
						.foregroundColor(ReconTheme.secondary)
					
					Spacer()
					
					Text(Self.gameLengthFormatter.string(from: matchInfo.gameLength)!)
						.foregroundColor(.white)
				}
				.font(.system(.subheadline, design: .rounded))
				.padding(.horizontal)
				
				tabPicker
				
				switch tab {
				case .scoreboard:
					ScoreboardView(data: data, highlight: $highlight)
					
					if KillBreakdownView.canDisplay(for: data) {
						Divider()
							.background(ReconTheme.border)
							.padding(.horizontal)
						
						KillBreakdownView(data: data, highlight: $highlight)
						
						detailsByRoundLink
					}
				case .performance:
					MatchPerformanceView(data: data, highlight: $highlight)
				}
			}
			.padding(.bottom)
		}
		.background(ReconTheme.background.ignoresSafeArea())
		.preferredColorScheme(.dark)
	}
	
	private var tabPicker: some View {
		HStack(spacing: 4) {
			tabButton(.scoreboard, label: Text("Scoreboard", comment: "Match Details: tab"))
			tabButton(.performance, label: Text("Performance", comment: "Match Details: tab"))
		}
		.padding(4)
		.background(Capsule().fill(Color.white.opacity(0.07)))
		.padding(.horizontal)
	}
	
	private func tabButton(_ tab: Tab, label: Text) -> some View {
		Button {
			withAnimation(.easeInOut(duration: 0.2)) {
				self.tab = tab
			}
		} label: {
			label
				.font(.system(.subheadline, design: .rounded).weight(.semibold))
				.foregroundColor(self.tab == tab ? ReconTheme.background : .white.opacity(0.7))
				.padding(.vertical, 8)
				.frame(maxWidth: .infinity)
				.background(
					Capsule().fill(self.tab == tab ? Color.white : Color.clear)
				)
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
	}
	
	private var detailsByRoundLink: some View {
		VStack(alignment: .leading, spacing: 8) {
			NavigationLink {
				RoundInfoContainer(matchData: data, roundNumber: 0)
			} label: {
				HStack {
					Text("Details by Round", comment: "Match Details: button to view details by round")
					Image(systemName: "chevron.forward")
				}
				.font(.system(.subheadline, design: .rounded).weight(.semibold))
				.foregroundColor(.white)
			}
			
			Text("You can also tap a round's number in the kill breakdown above to quickly view its details.", comment: "Match Details: footnote")
				.font(.footnote)
				.foregroundColor(ReconTheme.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal)
	}
}

#if DEBUG
struct MatchDetailsView_Previews: PreviewProvider {
	static var previews: some View {
		MatchDetailsView(
			data: PreviewData.singleMatchData
		)
		.navigationTitle("Match Details")
		.withToolbar(allowLargeTitles: false)
	}
}
#endif
