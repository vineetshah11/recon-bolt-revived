import SwiftUI
import ValorantAPI
import HandyOperators
import CGeometry

struct ActRankView: View {
	let seasonInfo: CareerSummary.SeasonInfo
	var isIcon = true
	var isShowingAllWins = false
	
	@Environment(\.seasons) private var seasons
	@Environment(\.imageManager) private var imageManager
	
	@State private var triangleImages: [AssetImage: UIImage] = [:]
	@State private var reloadToken = 0
	
	private var triangleTaskKey: String {
		let winsKey = (seasonInfo.winsByTier ?? [:])
			.filter { $0.key > 0 && $0.value > 0 }
			.sorted { $0.key < $1.key }
			.map { "\($0.key)" }
			.joined(separator: ",")
		return "\(reloadToken):\(seasonInfo.seasonID.description):\(winsKey):\(seasons != nil)"
	}
	
	var body: some View {
		let idealSize = isIcon ? 80 : 160.0
		let standardRowCount = isIcon ? 3 : 7
		let actInfo = seasons?.act(seasonInfo.seasonID)
		
		ZStack {
			let border = actInfo?.borders.last { seasonInfo.winCount >= $0.winsRequired }
			if let border {
				let winsByTier = seasonInfo.winsByTier ?? [:]
				let container = isIcon
					? (border.icon ?? actInfo?.borders.lazy.compactMap(\.icon).first) // show icon even when not qualified for border
					: border.fullImage
				container?.view()
				
				Canvas { context, size in
					typealias ResolvedImage = GraphicsContext.ResolvedImage
					typealias TierTriangles = (upwards: ResolvedImage?, downwards: ResolvedImage?)
					
					let triangleTiers = winsByTier
						.sorted(on: \.key)
						.reversed()
						.lazy // lazily resolve images—essentially waits until a certain tier's triangles are requested to resolve its images
						.filter { $0.key > 0 } // only ones we can actually display (important for auto-fitting)
						.map { [context] tier, count -> (TierTriangles, Int) in
							let tierInfo = seasons?.tierInfo(number: tier, in: actInfo)
							let upwards = resolve(tierInfo?.rankTriangleUpwards, using: context)
							let downwards = resolve(tierInfo?.rankTriangleDownwards, using: context)
							// i have no idea why in the world this ever happens but i've encountered a person with a negative count. i can't make sense of it so let's just pretend it's zero.
							return ((upwards, downwards), max(0, count))
						}
						.flatMap(repeatElement(_:count:))
					
					let rowCountToFitAll = Int(Double(triangleTiers.count).squareRoot().rounded(.up))
					let rowCount = isShowingAllWins ? rowCountToFitAll : standardRowCount
					
					// the images don't quite have this aspect ratio, but we're rescaling them anyway, so we may as well make them ideal
					let triangleRatio: CGFloat = sin(.pi / 3)
					// triangles should not be scaled about (0.5, 0.5) but rather a point 2/3 of the way down
					let triangleCenter = CGSize(width: 0.5, height: 2/3)
					
					context.scaleBy(x: size.width, y: size.height)
					
					do { // fit to container
						let width = 0.6
						let height = width * triangleRatio
						let sizeDifference = CGVector(dx: 1 - width, dy: 1 - height)
						let center = sizeDifference * triangleCenter
						let yOffset = isIcon ? -0.053 : -0.066 // because of course it's not centered
						context.translateBy(x: center.dx, y: center.dy + yOffset)
						context.scaleBy(x: width, y: height)
					}
					
					do { // map unit square to top triangle
						let triangleHeight = 1 / CGFloat(rowCount)
						context.translateBy(x: 0.5, y: 0)
						context.scaleBy(x: triangleHeight, y: triangleHeight)
					}
					
					var remainingTiers = triangleTiers[...] // constant-time prefix removal
					for rowNumber in 0..<rowCount {
						guard !remainingTiers.isEmpty else { break } // all done
						
						let tierCount = rowNumber * 2 + 1
						let tiers = remainingTiers.prefix(tierCount)
						remainingTiers = remainingTiers.dropFirst(tierCount)
						
						var context = context
						context.translateBy(x: 0, y: CGFloat(rowNumber))
						
						for (index, tier) in tiers.enumerated() {
							let shouldPointUpwards = index % 2 == 0
							let triangle = shouldPointUpwards ? tier.upwards : tier.downwards
							guard let triangle else { continue }
							
							var context = context
							context.translateBy(x: CGFloat(index - rowNumber - 1) * 0.5, y: 0)
							
							context.draw(triangle, in: CGRect(origin: .zero, size: .one))
						}
					}
				}
			}
		}
		.aspectRatio(1, contentMode: .fit)
		.frame(idealWidth: idealSize, idealHeight: idealSize)
		.task(id: triangleTaskKey) {
			await loadMissingTriangles(actInfo: actInfo)
		}
		.onReceive(imageManager.imageDidUpdate) { updated in
			guard updated == nil || triangleImages[updated!] != nil else { return }
			triangleImages.removeAll()
			reloadToken &+= 1
		}
	}
	
	private func loadMissingTriangles(actInfo: Act?) async {
		let winsByTier = seasonInfo.winsByTier ?? [:]
		var targets: Set<AssetImage> = []
		for (tier, count) in winsByTier where tier > 0 && count > 0 {
			let tierInfo = seasons?.tierInfo(number: tier, in: actInfo)
			if let up = tierInfo?.rankTriangleUpwards { targets.insert(up) }
			if let down = tierInfo?.rankTriangleDownwards { targets.insert(down) }
		}
		var loaded: [AssetImage: UIImage] = [:]
		var missing: [AssetImage] = []
		for img in targets {
			if let existing = triangleImages[img] ?? imageManager.cachedImage(for: img, bucket: .icon) {
				loaded[img] = existing
			} else {
				missing.append(img)
			}
		}
		if !missing.isEmpty {
			await withTaskGroup(of: (AssetImage, UIImage?).self) { group in
				for img in missing {
					group.addTask { [imageManager] in
						let uiImage = await imageManager.awaitImage(for: img, bucket: .icon)
						return (img, uiImage)
					}
				}
				for await (img, uiImage) in group {
					if let uiImage {
						loaded[img] = uiImage
					}
				}
			}
		}
		guard !Task.isCancelled else { return }
		if loaded.count != triangleImages.count || loaded.keys.contains(where: { triangleImages[$0] !== loaded[$0] }) {
			triangleImages = loaded
		}
	}
	
	func resolve(_ image: AssetImage?, using context: GraphicsContext) -> GraphicsContext.ResolvedImage? {
		guard let image else { return nil }
		guard let uiImage = triangleImages[image] ?? imageManager.cachedImage(for: image, bucket: .icon) else {
			return nil
		}
		return context.resolve(Image(uiImage: uiImage))
	}
}

#if DEBUG
struct ActRankView_Previews: PreviewProvider {
	static let assets = AssetManager.forPreviews.assets!
	static let currentAct = assets.seasons.acts[.init("2a27e5d2-4d30-c9e2-b15a-93b8909a442c")!]!
	static let previousAct = assets.seasons.actBefore(currentAct)!
	
	static let bySeason = PreviewData.summary.competitiveInfo!.bySeason!
	
	static var previews: some View {
		HStack(alignment: .bottom) {
			ForEach(assets.seasons.actsInOrder) { act in
				preview(for: act)
					.padding()
			}
		}
		.fixedSize()
		.previewLayout(.sizeThatFits)
		
		ActRankView(seasonInfo: bySeason[currentAct.id]!, isShowingAllWins: true)
			.preferredColorScheme(.dark)
	}
	
	static func preview(for act: Act) -> some View {
		VStack {
			if let seasonInfo = bySeason[act.id] {
				ActRankView(seasonInfo: seasonInfo, isIcon: true)
				ActRankView(seasonInfo: seasonInfo, isIcon: false)
			}
			
			Text(act.nameWithEpisode)
				.font(.caption.smallCaps())
		}
	}
}
#endif
