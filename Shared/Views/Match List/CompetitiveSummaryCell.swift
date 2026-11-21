import SwiftUI
import ValorantAPI
import HandyOperators

struct CompetitiveSummaryCell: View {
	let summary: CareerSummary?

	@Environment(\.seasons) private var seasons
	@Environment(\.colorScheme) private var colorScheme

	private let artworkSize = 96.0
	private let primaryFont = Font.callout.weight(.semibold)
	private let secondaryFont = Font.caption

	var body: some View {
		TransparentNavigationLink {
			if let summary {
				CareerSummaryView(summary: summary)
			}
		} label: {
			HStack(alignment: .rankIcon, spacing: 16) {
				Spacer(minLength: 0)

				currentActInfo
					.fixedSize()
					.frame(maxWidth: .infinity)

				peakInfo
					.fixedSize()
					.frame(maxWidth: .infinity)

				Spacer(minLength: 0)
			}
			.frame(maxWidth: .infinity)
			.fixedSize(horizontal: false, vertical: true)
			.padding(.vertical, 16)
			.padding(.horizontal, 8)
			.background(ReconTheme.background)
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.stroke(ReconTheme.border, lineWidth: 1)
			)
			.updatingGameConfig()
		}
		.disabled(summary == nil)
		.listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.clear)
	}

	@ViewBuilder
	private var currentActInfo: some View {
		VStack {
			let act = seasons?.currentAct()
			let info: CareerSummary.SeasonInfo?
			if let raw = summary?.competitiveInfo?.inSeason(act?.id) {
				info = raw.isBlankCurrentActSnapshot ? bestRankedSeasonInfo(in: summary) : raw
			} else {
				info = bestRankedSeasonInfo(in: summary)
			}
			let tier = info?.competitiveTier ?? 0
			let tierInfo = seasons?.tierInfo(number: tier, in: act)

			// Treat tier 0 (unranked) explicitly — the API name may be an internal placeholder.
			let isUnranked = tier == 0

			SeasonLabel(season: act?.id)
				.font(secondaryFont)
				.foregroundColor(ReconTheme.secondary)

			RankInfoView(summary: summary, size: artworkSize, lineWidth: 5, shouldFallBackOnPrevious: false)
				.alignmentGuide(.rankIcon) { $0[VerticalAlignment.center] }

			Group {
				if isUnranked {
					Text("Unranked", comment: "Match List: player has not played ranked this act")
						.foregroundColor(ReconTheme.secondary)
						.font(primaryFont)
				} else if let tierInfo {
					Text(tierInfo.name)
						.foregroundColor(.white)
						.font(primaryFont)
				} else {
					Text("Unknown Rank", comment: "Match List: should never appear unless assets are missing/outdated")
						.foregroundColor(ReconTheme.secondary)
						.font(primaryFont)
				}

				Text(isUnranked ? "0 RR" : "\(info?.adjustedRankedRating ?? 0) RR")
					.font(secondaryFont)
					.foregroundColor(ReconTheme.secondary)
			}
			.placeholder(if: summary == nil)

			if let info, info.leaderboardRank > 0 {
				LeaderboardRankView(rank: info.leaderboardRank, tierInfo: tierInfo)
			}
		}
	}

	private func bestRankedSeasonInfo(in summary: CareerSummary?) -> CareerSummary.SeasonInfo? {
		summary?.competitiveInfo?.bySeason?.values
			.filter { $0.competitiveTier > 0 }
			.max(by: { $0.seasonID < $1.seasonID })
	}

	@ViewBuilder
	private var peakInfo: some View {
		if
			let peakRank = summary?.peakRank(seasons: seasons),
			let info = seasons?.tierInfo(peakRank)
		{
			VStack {
				SeasonLabel(season: peakRank.season)
					.font(secondaryFont)
					.foregroundColor(ReconTheme.secondary)

				PeakRankIcon(
					peakRank: peakRank, tierInfo: info,
					size: artworkSize,
					borderOpacity: colorScheme == .dark ? 0.4 : 1 // it's very light, so this helps maintain the same contrast
				)

				VStack {
					Text(info.name)
						.foregroundColor(.white)
						.font(primaryFont)
					Text("Lifetime Peak")
						.foregroundColor(ReconTheme.secondary)
						.font(secondaryFont)
				}
			}
		}
	}

	@ViewBuilder
	private func actRankInfo(for info: CareerSummary.SeasonInfo, in act: Act) -> some View {
		VStack {
			let tierInfo = seasons?.tierInfo(number: info.competitiveTier, in: act)

			ActRankView(seasonInfo: info)
				.frame(width: 120, height: 120)
				.padding(.top, -10)
				.fixedSize()
				.overlay(
					CompetitiveTierImage(tierInfo: tierInfo)
						.frame(width: 40, height: 40)
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
						.shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
				)

			Text(act.name)
				.font(primaryFont)

			if let episode = act.episode {
				Text(episode.name)
					.font(secondaryFont)
			}
		}
	}
}

#if DEBUG
struct CompetitiveSummaryCell_Previews: PreviewProvider, PreviewProviderWithAssets {
	static func previews(assets: AssetCollection) -> some View {
		let act = assets.seasons.with(PreviewData.gameConfig).currentAct()!

		CompetitiveSummaryCell(summary: PreviewData.summary)
			.buttonStyle(.navigationLinkPreview)
			.previewLayout(.sizeThatFits)
			.environmentObject(ImageManager())
			.previewDisplayName("Single Cell")

		List {
			Section {
				CompetitiveSummaryCell(summary: nil)

				CompetitiveSummaryCell(summary: PreviewData.summary <- {
					$0.competitiveInfo!.bySeason = $0.competitiveInfo!.bySeason!
						.filter { $0.key == act.id }
				})
			}

			Section {
				CompetitiveSummaryCell(summary: PreviewData.summary)
			}

			Section {
				CompetitiveSummaryCell(summary: PreviewData.summary <- {
					$0.competitiveInfo!.bySeason![act.id] = .init(
						seasonID: act.id,
						leaderboardRank: 152,
						competitiveTier: 27,
						rankedRating: 543
					)
				})
			}

			Section {
				CompetitiveSummaryCell(summary: PreviewData.summary <- {
					$0.competitiveInfo!.bySeason![act.id] = .init(seasonID: act.id, competitiveTier: 20, rankedRating: 32)
				})
			}
		}
		.withToolbar()
		.environmentObject(ImageManager())
		.previewDisplayName("List")
	}
}
#endif
