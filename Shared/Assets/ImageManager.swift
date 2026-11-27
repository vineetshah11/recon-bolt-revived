import SwiftUI
import UIKit
import ImageIO
import Combine

enum ImageBucket: Int, Hashable, CaseIterable, Sendable {
	case icon = 256
	case banner = 960
	case medium = 1024
	case full = 2048
	
	var maxPixelSize: Int { rawValue }
}

final class ImageManager: @unchecked Sendable {
	static let shared = ImageManager()
	
	private let memoryCache = ImageMemoryCache()
	private let pipeline: Pipeline
	private let didUpdateSubject = PassthroughSubject<AssetImage?, Never>()
	private let revalidationLock = NSLock()
	private var knownRevalidated: Set<AssetImage> = []
	private var knownVersionString = UserDefaults.standard.string(forKey: Pipeline.versionDefaultsKey) ?? ""
	
	var imageDidUpdate: AnyPublisher<AssetImage?, Never> {
		didUpdateSubject.eraseToAnyPublisher()
	}
	
	init() {
		let subject = didUpdateSubject
		self.pipeline = Pipeline(memoryCache: memoryCache) { replacedImage in
			Task { @MainActor in
				subject.send(replacedImage)
			}
		}
	}
	
	func setVersion(_ version: AssetVersion) {
		let versionString = version.riotClientVersion
		revalidationLock.withLock {
			if versionString != knownVersionString {
				knownVersionString = versionString
				knownRevalidated.removeAll()
			}
		}
		Task.detached(priority: .utility) { [pipeline] in
			await pipeline.setVersion(versionString)
		}
	}
	
	func cachedImage(
		for image: AssetImage,
		bucket: ImageBucket,
		outlineRadius: CGFloat? = nil
	) -> UIImage? {
		memoryCache.image(for: image, bucket: bucket, outlineRadius: outlineRadius)
	}
	
	/// Synchronous helper restricted to Xcode/SwiftUI Previews.
	func syncPreviewImage(
		for image: AssetImage,
		bucket: ImageBucket,
		outlineRadius: CGFloat? = nil
	) -> UIImage? {
		if let cached = memoryCache.image(for: image, bucket: bucket, outlineRadius: outlineRadius) {
			return cached
		}
		guard let decoded = ImageDecoder.decode(at: image.localURL, bucket: bucket) else {
			return nil
		}
		memoryCache.store(decoded, for: image, bucket: bucket)
		if let outlineRadius {
			let radiusTenths = Int((outlineRadius * 10).rounded())
			let outlined = ImageDecoder.renderOutlined(decoded, radius: outlineRadius)
			memoryCache.storeOutlined(outlined, for: image, radiusTenths: radiusTenths)
			return outlined
		}
		return decoded
	}
	
	func loadImage(
		for image: AssetImage,
		bucket: ImageBucket,
		outlineRadius: CGFloat? = nil,
		forceRetry: Bool = false,
		onDownloadStart: (@Sendable () -> Void)? = nil
	) async throws -> UIImage? {
		try await pipeline.loadImage(
			for: image,
			bucket: bucket,
			outlineRadius: outlineRadius,
			forceRetry: forceRetry,
			onDownloadStart: onDownloadStart
		)
	}
	
	func scheduleRevalidationIfNeeded(for image: AssetImage) {
		let shouldSchedule = revalidationLock.withLock {
			!knownVersionString.isEmpty && knownRevalidated.insert(image).inserted
		}
		guard shouldSchedule else { return }
		Task.detached(priority: .utility) { [pipeline] in
			await pipeline.scheduleRevalidationIfNeeded(for: image)
		}
	}
	
	func awaitImage(for image: AssetImage?, bucket: ImageBucket = .full) async -> UIImage? {
		guard let image else { return nil }
		return try? await loadImage(for: image, bucket: bucket)
	}
	
	func prewarmHotAssets(from assets: AssetCollection) {
		var items: [(AssetImage, ImageBucket)] = []
		items.reserveCapacity(assets.maps.count + assets.agents.count + 48)
		var seen: Set<AssetImage> = []
		
		func appendIfNew(_ asset: AssetImage?, bucket: ImageBucket) {
			guard let asset, seen.insert(asset).inserted else { return }
			items.append((asset, bucket))
		}
		
		for map in assets.maps.values {
			appendIfNew(map.listViewIcon, bucket: .banner)
		}
		for agent in assets.agents.values {
			appendIfNew(agent.displayIcon, bucket: .icon)
		}
		if let latestAct = assets.seasons.actsInOrder.last {
			for tier in assets.seasons.tiers(in: latestAct).tiers.values {
				appendIfNew(tier.icon, bucket: .icon)
				appendIfNew(tier.rankTriangleUpwards, bucket: .icon)
			}
		}
		
		Task.detached(priority: .utility) { [pipeline] in
			await pipeline.prewarm(items: items)
		}
	}
	
	private func clearKnownRevalidated() {
		revalidationLock.withLock {
			knownRevalidated.removeAll()
		}
	}
	
	func clear() async {
		clearKnownRevalidated()
		await pipeline.clear()
	}
}

extension EnvironmentValues {
	var imageManager: ImageManager {
		get { self[ImageManagerKey.self] }
		set { self[ImageManagerKey.self] = newValue }
	}
	
	private enum ImageManagerKey: EnvironmentKey {
		static let defaultValue = ImageManager.shared
	}
}

// MARK: - Memory Cache

private final class ImageMemoryCache: @unchecked Sendable {
	private let hotCache: NSCache<NSString, UIImage> = {
		let cache = NSCache<NSString, UIImage>()
		cache.countLimit = 400
		cache.totalCostLimit = 48 * 1024 * 1024
		return cache
	}()
	
	private let largeCache: NSCache<NSString, UIImage> = {
		let cache = NSCache<NSString, UIImage>()
		cache.countLimit = 24
		cache.totalCostLimit = 64 * 1024 * 1024
		return cache
	}()
	
	private let outlinedCache: NSCache<NSString, UIImage> = {
		let cache = NSCache<NSString, UIImage>()
		cache.countLimit = 100
		cache.totalCostLimit = 12 * 1024 * 1024
		return cache
	}()
	
	private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?
	
	init() {
#if canImport(UIKit) && !WIDGETS
		memoryWarningObserver = NotificationCenter.default.addObserver(
			forName: UIApplication.didReceiveMemoryWarningNotification,
			object: nil,
			queue: nil
		) { [weak self] _ in
			self?.handleMemoryWarning()
		}
#endif
	}
	
	deinit {
		if let memoryWarningObserver {
			NotificationCenter.default.removeObserver(memoryWarningObserver)
		}
	}
	
	private func handleMemoryWarning() {
		largeCache.removeAllObjects()
		outlinedCache.removeAllObjects()
	}
	
	func image(for image: AssetImage, bucket: ImageBucket, outlineRadius: CGFloat?) -> UIImage? {
		if let outlineRadius {
			let radiusTenths = Int((outlineRadius * 10).rounded())
			return outlinedCache.object(forKey: Self.outlinedKey(for: image, radiusTenths: radiusTenths))
		}
		let cache = (bucket == .full) ? largeCache : hotCache
		return cache.object(forKey: Self.key(for: image, bucket: bucket))
	}
	
	func store(_ uiImage: UIImage, for image: AssetImage, bucket: ImageBucket) {
		let cache = (bucket == .full) ? largeCache : hotCache
		cache.setObject(uiImage, forKey: Self.key(for: image, bucket: bucket), cost: Self.cost(of: uiImage))
	}
	
	func storeOutlined(_ uiImage: UIImage, for image: AssetImage, radiusTenths: Int) {
		outlinedCache.setObject(
			uiImage,
			forKey: Self.outlinedKey(for: image, radiusTenths: radiusTenths),
			cost: Self.cost(of: uiImage)
		)
	}
	
	func removeImages(for image: AssetImage) {
		for bucket in ImageBucket.allCases {
			let cache = (bucket == .full) ? largeCache : hotCache
			cache.removeObject(forKey: Self.key(for: image, bucket: bucket))
		}
		outlinedCache.removeAllObjects()
	}
	
	func removeAll() {
		hotCache.removeAllObjects()
		largeCache.removeAllObjects()
		outlinedCache.removeAllObjects()
	}
	
	private static func key(for image: AssetImage, bucket: ImageBucket) -> NSString {
		"\(image.url.absoluteString)#b\(bucket.rawValue)" as NSString
	}
	
	private static func outlinedKey(for image: AssetImage, radiusTenths: Int) -> NSString {
		"\(image.url.absoluteString)#o\(radiusTenths)" as NSString
	}
	
	private static func cost(of image: UIImage) -> Int {
		if let cgImage = image.cgImage {
			return max(1, cgImage.bytesPerRow * cgImage.height)
		}
		let width = Int((image.size.width * image.scale).rounded(.up))
		let height = Int((image.size.height * image.scale).rounded(.up))
		return max(1, width * height * 4)
	}
}

// MARK: - Image Decoder

private enum ImageDecoder {
	static func decode(at fileURL: URL, bucket: ImageBucket) -> UIImage? {
		PerfMonitor.measure("ImageDecode \(fileURL.lastPathComponent)", warnOverMs: 4.0) {
			let cfURL = fileURL as CFURL
			if let source = CGImageSourceCreateWithURL(cfURL, nil) {
				let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
				let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
				let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
				let maxEdge = max(width, height)
				
				if maxEdge > bucket.maxPixelSize {
					let options: [CFString: Any] = [
						kCGImageSourceCreateThumbnailFromImageAlways: true,
						kCGImageSourceThumbnailMaxPixelSize: bucket.maxPixelSize,
						kCGImageSourceCreateThumbnailWithTransform: true,
						kCGImageSourceShouldCacheImmediately: true,
					]
					if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
						return UIImage(cgImage: cgThumb, scale: 1, orientation: .up)
					}
				} else if maxEdge > 0 {
					let options: [CFString: Any] = [
						kCGImageSourceShouldCacheImmediately: true,
					]
					if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
						let rawOrientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
						return UIImage(cgImage: cgImage, scale: 1, orientation: Self.uiOrientation(from: rawOrientation))
					}
				}
			}
			guard let loaded = UIImage(contentsOfFile: fileURL.path) else { return nil }
			return loaded.preparingForDisplay() ?? loaded
		}
	}
	
	private static func uiOrientation(from cgValue: UInt32?) -> UIImage.Orientation {
		guard let cgValue, let cgOrientation = CGImagePropertyOrientation(rawValue: cgValue) else {
			return .up
		}
		switch cgOrientation {
		case .up: return .up
		case .down: return .down
		case .left: return .left
		case .right: return .right
		case .upMirrored: return .upMirrored
		case .downMirrored: return .downMirrored
		case .leftMirrored: return .leftMirrored
		case .rightMirrored: return .rightMirrored
		}
	}
	
	static func renderOutlined(_ image: UIImage, radius: CGFloat) -> UIImage {
		let size = image.size
		guard size.width > 0, size.height > 0 else { return image }
		let strokePx = max(2, (radius / 40.0) * min(size.width, size.height)).rounded()
		let format = UIGraphicsImageRendererFormat()
		format.scale = image.scale
		format.opaque = false
		let mask = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
			let rect = CGRect(origin: .zero, size: size)
			image.draw(in: rect)
			UIColor.white.setFill()
			ctx.fill(rect, blendMode: .sourceIn)
		}
		return UIGraphicsImageRenderer(size: size, format: format).image { _ in
			let rect = CGRect(origin: .zero, size: size)
			let steps = 12
			for step in 0..<steps {
				let angle = (CGFloat(step) / CGFloat(steps)) * (.pi * 2)
				mask.draw(in: rect.offsetBy(dx: cos(angle) * strokePx, dy: sin(angle) * strokePx))
			}
			image.draw(in: rect)
		}
	}
}

// MARK: - Actor Pipeline

private enum ImageLoadError: Error {
	case decodeFailed
}

private actor Pipeline {
	private struct DecodeKey: Hashable {
		let image: AssetImage
		let bucket: ImageBucket
		let radiusTenths: Int?
	}
	
	fileprivate static let versionDefaultsKey = "ImageManager.version"
	private static let maxConcurrentRevalidations = 3
	
	private let memoryCache: ImageMemoryCache
	private let onImageReplaced: @Sendable (AssetImage?) -> Void
	
	private var currentVersion: String
	private var clearGeneration: UInt64 = 0
	private var inFlightDownloads: [AssetImage: Task<Void, Error>] = [:]
	private var inFlightDecodes: [DecodeKey: Task<UIImage?, Never>] = [:]
	
	private var revalidated: Set<AssetImage> = []
	private var revalidating: Set<AssetImage> = []
	private var revalidationQueue: [AssetImage] = []
	private var activeRevalidations = 0
	private var prewarmTask: Task<Void, Never>?
	
	init(
		memoryCache: ImageMemoryCache,
		onImageReplaced: @escaping @Sendable (AssetImage?) -> Void
	) {
		self.memoryCache = memoryCache
		self.onImageReplaced = onImageReplaced
		self.currentVersion = UserDefaults.standard.string(forKey: Self.versionDefaultsKey) ?? ""
	}
	
	func setVersion(_ newVersion: String) {
		guard newVersion != currentVersion else { return }
		currentVersion = newVersion
		UserDefaults.standard.set(newVersion, forKey: Self.versionDefaultsKey)
		revalidated.removeAll()
		revalidating.removeAll()
		revalidationQueue.removeAll()
	}
	
	func loadImage(
		for image: AssetImage,
		bucket: ImageBucket,
		outlineRadius: CGFloat?,
		forceRetry: Bool,
		onDownloadStart: (@Sendable () -> Void)?
	) async throws -> UIImage? {
		try Task.checkCancellation()
		let radiusTenths = outlineRadius.map { Int(($0 * 10).rounded()) }
		
		if !forceRetry, let cached = memoryCache.image(for: image, bucket: bucket, outlineRadius: outlineRadius) {
			scheduleRevalidationIfNeeded(for: image)
			return cached
		}
		
		if !forceRetry {
			let diskExists = await Task.detached(priority: .userInitiated) {
				FileManager.default.fileExists(atPath: image.localURL.path)
			}.value
			try Task.checkCancellation()
			if diskExists {
				if let decoded = await decodeCoalesced(
					image: image,
					bucket: bucket,
					outlineRadius: outlineRadius,
					radiusTenths: radiusTenths
				) {
					scheduleRevalidationIfNeeded(for: image)
					return decoded
				}
				// Corrupt file on disk: clean it up before downloading again.
				await Task.detached(priority: .utility) {
					try? FileManager.default.removeItem(at: image.localURL)
					try? FileManager.default.removeItem(at: image.metadataURL)
				}.value
				try Task.checkCancellation()
			}
		} else {
			memoryCache.removeImages(for: image)
		}
		
		onDownloadStart?()
		try await downloadCoalesced(image: image)
		try Task.checkCancellation()
		
		let decoded = await decodeCoalesced(
			image: image,
			bucket: bucket,
			outlineRadius: outlineRadius,
			radiusTenths: radiusTenths
		)
		guard let decoded else {
			throw ImageLoadError.decodeFailed
		}
		return decoded
	}
	
	private func decodeCoalesced(
		image: AssetImage,
		bucket: ImageBucket,
		outlineRadius: CGFloat?,
		radiusTenths: Int?
	) async -> UIImage? {
		if let cached = memoryCache.image(for: image, bucket: bucket, outlineRadius: outlineRadius) {
			return cached
		}
		let key = DecodeKey(image: image, bucket: bucket, radiusTenths: radiusTenths)
		if let existing = inFlightDecodes[key] {
			return await existing.value
		}
		let task = Task<UIImage?, Never> {
			await self.performDecode(
				key: key,
				outlineRadius: outlineRadius
			)
		}
		inFlightDecodes[key] = task
		return await task.value
	}
	
	private func performDecode(key: DecodeKey, outlineRadius: CGFloat?) async -> UIImage? {
		defer { inFlightDecodes[key] = nil }
		
		let image = key.image
		let bucket = key.bucket
		let radiusTenths = key.radiusTenths
		let baseCached = memoryCache.image(for: image, bucket: bucket, outlineRadius: nil)
		
		let baseImage: UIImage?
		if let baseCached {
			baseImage = baseCached
		} else {
			let decoded = await Task.detached(priority: .userInitiated) {
				ImageDecoder.decode(at: image.localURL, bucket: bucket)
			}.value
			if let decoded {
				memoryCache.store(decoded, for: image, bucket: bucket)
			}
			baseImage = decoded
		}
		
		guard let baseImage else { return nil }
		guard let outlineRadius, let radiusTenths else {
			return baseImage
		}
		
		if let existingOutlined = memoryCache.image(for: image, bucket: bucket, outlineRadius: outlineRadius) {
			return existingOutlined
		}
		let outlined = await Task.detached(priority: .userInitiated) {
			ImageDecoder.renderOutlined(baseImage, radius: outlineRadius)
		}.value
		memoryCache.storeOutlined(outlined, for: image, radiusTenths: radiusTenths)
		return outlined
	}
	
	private func downloadCoalesced(image: AssetImage) async throws {
		if let existing = inFlightDownloads[image] {
			try await existing.value
			try Task.checkCancellation()
			return
		}
		let task = Task<Void, Error> {
			try await self.performDownload(image: image)
		}
		inFlightDownloads[image] = task
		try await task.value
		try Task.checkCancellation()
	}
	
	private func performDownload(image: AssetImage) async throws {
		defer { inFlightDownloads[image] = nil }
		try await image.downloadToDisk()
		memoryCache.removeImages(for: image)
		let version = currentVersion
		if !version.isEmpty {
			await Task.detached(priority: .utility) {
				let meta = ImageMetadata(versionDownloaded: version, lastVersionCheckedAgainst: version)
				try? image.save(meta)
			}.value
			revalidated.insert(image)
		}
	}
	
	func scheduleRevalidationIfNeeded(for image: AssetImage) {
		guard !currentVersion.isEmpty else { return }
		guard !revalidated.contains(image), !revalidating.contains(image) else { return }
		revalidating.insert(image)
		revalidationQueue.append(image)
		drainRevalidationQueue()
	}
	
	private func drainRevalidationQueue() {
		while activeRevalidations < Self.maxConcurrentRevalidations, !revalidationQueue.isEmpty {
			let next = revalidationQueue.removeFirst()
			let expectedVersion = currentVersion
			let generation = clearGeneration
			activeRevalidations += 1
			Task.detached(priority: .utility) { [weak self] in
				await self?.runRevalidation(
					for: next,
					expectedVersion: expectedVersion,
					expectedGeneration: generation
				)
			}
		}
	}
	
	private nonisolated func runRevalidation(
		for image: AssetImage,
		expectedVersion: String,
		expectedGeneration: UInt64
	) async {
		var wasReplaced = false
		do {
			if let meta = try? image.loadMetadata(), meta.lastVersionCheckedAgainst == expectedVersion {
				await finishRevalidation(for: image, expectedGeneration: expectedGeneration, replaced: false)
				return
			}
			guard let existingSize = FileManager.default.sizeOfItem(atPath: image.localURL.path) else {
				await finishRevalidation(for: image, expectedGeneration: expectedGeneration, replaced: false)
				return
			}
			let remoteSize = try await AssetImageClient.shared.sizeOfImage(at: image.url)
			let stillValidGen = await isSameGeneration(expectedGeneration)
			guard stillValidGen else {
				await finishRevalidation(for: image, expectedGeneration: expectedGeneration, replaced: false)
				return
			}
			if let remoteSize, remoteSize != existingSize {
				try await image.downloadToDisk()
				let stillValidAfterDownload = await isSameGeneration(expectedGeneration)
				if stillValidAfterDownload {
					let meta = ImageMetadata(versionDownloaded: expectedVersion, lastVersionCheckedAgainst: expectedVersion)
					try? image.save(meta)
					memoryCache.removeImages(for: image)
					wasReplaced = true
				}
			} else {
				var meta = (try? image.loadMetadata()) ?? ImageMetadata(
					versionDownloaded: expectedVersion,
					lastVersionCheckedAgainst: expectedVersion
				)
				meta.lastVersionCheckedAgainst = expectedVersion
				try? image.save(meta)
			}
		} catch {
			// Background check: keep displaying cached disk image silently.
		}
		await finishRevalidation(for: image, expectedGeneration: expectedGeneration, replaced: wasReplaced)
	}
	
	private func isSameGeneration(_ expected: UInt64) -> Bool {
		clearGeneration == expected
	}
	
	private func finishRevalidation(
		for image: AssetImage,
		expectedGeneration: UInt64,
		replaced: Bool
	) {
		activeRevalidations = max(0, activeRevalidations - 1)
		if clearGeneration == expectedGeneration {
			revalidating.remove(image)
			revalidated.insert(image)
			if replaced {
				onImageReplaced(image)
			}
			drainRevalidationQueue()
		}
	}
	
	func prewarm(items: [(AssetImage, ImageBucket)]) {
		prewarmTask?.cancel()
		let cache = memoryCache
		prewarmTask = Task.detached(priority: .utility) {
			for (image, bucket) in items {
				if Task.isCancelled { break }
				if cache.image(for: image, bucket: bucket, outlineRadius: nil) != nil {
					continue
				}
				guard FileManager.default.fileExists(atPath: image.localURL.path) else {
					continue
				}
				if let decoded = ImageDecoder.decode(at: image.localURL, bucket: bucket) {
					cache.store(decoded, for: image, bucket: bucket)
				}
				await Task.yield()
			}
		}
	}
	
	func clear() async {
		clearGeneration &+= 1
		prewarmTask?.cancel()
		prewarmTask = nil
		revalidated.removeAll()
		revalidating.removeAll()
		revalidationQueue.removeAll()
		memoryCache.removeAll()
		await Task.detached(priority: .utility) {
			try? AssetImage.removeCachedFiles()
		}.value
		onImageReplaced(nil)
	}
}

private struct ImageMetadata: Codable {
	var versionDownloaded: String
	var lastVersionCheckedAgainst: String
}

private extension AssetImage {
	var metadataURL: URL {
		localURL.deletingPathExtension().appendingPathExtension("json")
	}
	
	func loadMetadata() throws -> ImageMetadata {
		try JSONDecoder().decode(ImageMetadata.self, from: Data(contentsOf: metadataURL))
	}
	
	func save(_ metadata: ImageMetadata) throws {
		try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
	}
}
