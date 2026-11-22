import SwiftUI
import ImageIO
import HandyOperators
import UserDefault
import Combine

@MainActor
final class ImageManager: ObservableObject {
	private var states: [AssetImage: ImageState] = [:]
	private var requestedDownloads: Set<AssetImage> = []
	private var requestedOutlines: Set<OutlinedKey> = []
	private var largeImageTasks: [AssetImage: Task<UIImage?, Never>] = [:]
	private let largeImages = NSCache<NSURL, UIImage>() <- {
		$0.countLimit = 12
	}
	
	private let cache: ImageCache
	private let updater: Updater
	private var stateUpdateToken: AnyCancellable?
	
	// can't have a nonisolated wrapped property
	private enum VersionHolder {
		@UserDefault("ImageManager.version")
		static var version = ""
	}
	
	@MainActor
	init() {
		cache = .init()
		updater = .init(cache: cache)
		stateUpdateToken = updater.stateUpdates
			.collect(.byTime(RunLoop.main, .milliseconds(50)))
			.sink { [weak self] updates in
				self?.apply(updates)
			}
	}
	
	func setVersion(_ version: AssetVersion) {
		guard version.riotClientVersion != VersionHolder.version else { return }
		VersionHolder.version = version.riotClientVersion
		states = [:] // make images re-check for the new version
		requestedDownloads = []
		requestedOutlines = []
		largeImageTasks.values.forEach { $0.cancel() }
		largeImageTasks = [:]
		largeImages.removeAllObjects()
		cache.reset()
		Task { await updater.resetCompleted() }
	}
	
	func state(for image: AssetImage) -> ImageState? {
		states[image]
	}
	
	/// Starts a download task at most once per image without mutating published state during view body evaluation.
	func ensureDownloadStarted(for image: AssetImage, retrying: Bool = false) {
		if retrying {
			requestedDownloads.remove(image)
		}
		guard shouldDownload(image), requestedDownloads.insert(image).inserted else { return }
		Task { await updater.download(image) }
	}
	
	func ensureOutlinedPrepared(for image: AssetImage, radius: CGFloat) {
		let key = OutlinedKey(image: image, radiusTenths: Int((radius * 10).rounded()))
		guard cache.outlinedImage(for: key) == nil else { return }
		guard requestedOutlines.insert(key).inserted else { return }
		Task {
			await updater.prepareOutlined(image: image, key: key, radius: radius)
		}
	}
	
	func outlinedImage(for image: AssetImage, radius: CGFloat) -> UIImage? {
		let key = OutlinedKey(image: image, radiusTenths: Int((radius * 10).rounded()))
		return cache.outlinedImage(for: key)
	}
	
	func largeImage(for image: AssetImage) -> UIImage? {
		largeImages.object(forKey: image.localURL as NSURL)
	}
	
	func loadLargeImage(for image: AssetImage) async -> UIImage? {
		let cacheKey = image.localURL as NSURL
		if let cached = largeImages.object(forKey: cacheKey) {
			return cached
		}
		if let existingTask = largeImageTasks[image] {
			return await existingTask.value
		}
		let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
			guard let loaded = image.load() else { return nil }
			return loaded.preparingForDisplay() ?? loaded
		}
		largeImageTasks[image] = task
		let loaded = await task.value
		largeImageTasks[image] = nil
		if let loaded, !Task.isCancelled {
			largeImages.setObject(loaded, forKey: cacheKey)
		}
		return loaded
	}
	
	/// gets an image's current state and starts a download task if appropriate
	func image(for image: AssetImage?) -> UIImage? {
		guard let image else { return nil }
		ensureDownloadStarted(for: image)
		
		switch cache.state(for: image) {
		case .cached(let image):
			return image
		case .tooLarge:
			return largeImage(for: image) ?? image.load()
		case .missing, nil:
			return nil
		}
	}
	
	func download(_ image: AssetImage) async {
		guard shouldDownload(image) else { return }
		await updater.download(image)
	}
	
	func shouldDownload(_ image: AssetImage) -> Bool {
		switch state(for: image) {
		case nil, .errored:
			return true
		case .downloading, .available:
			return false
		}
	}
	
	func awaitImage(for image: AssetImage?) async -> UIImage? {
		guard let image else { return nil }
		await download(image)
		return self.image(for: image)
	}
	
	func cacheState(for image: AssetImage, loadImmediately: Bool = false) -> CacheState? {
		if loadImmediately, cache.state(for: image) == nil {
			cache.updateState(for: image, forceUpdate: false)
		}
		return cache.state(for: image)
	}
	
	private func apply(_ updates: some Sequence<StateUpdate>) {
		// batch updates to reduce CA commits
		objectWillChange.send()
		for update in updates {
			states[update.image] = update.state
			if case .errored = update.state {
				requestedDownloads.remove(update.image)
			}
		}
	}
	
	@MainActor
	func clear() {
		states = [:]
		requestedDownloads = []
		requestedOutlines = []
		largeImageTasks.values.forEach { $0.cancel() }
		largeImageTasks = [:]
		largeImages.removeAllObjects()
		cache.reset()
		try? AssetImage.removeCachedFiles()
		Task { await updater.resetCompleted() }
		// if any loads are in progress, they might still set the state right after this, but i've decided i don't care
	}
	
	enum ImageState {
		case downloading
		case errored(Error)
		case available
	}
	
	enum CacheState: Equatable {
		case missing
		case cached(UIImage)
		case tooLarge
	}
	
	private struct StateUpdate {
		var image: AssetImage
		var state: ImageState
	}
	
	struct OutlinedKey: Hashable {
		var image: AssetImage
		var radiusTenths: Int
	}
	
	@MainActor
	private final class ImageCache {
		// caching these helps a lot with performance
		private var cached: [AssetImage: CacheState] = [:]
		private var outlined: [OutlinedKey: UIImage] = [:]
		
		private nonisolated static let cacheSizeLimit = 256 * 256 // pixels
		private nonisolated static let maxDownsampledSourcePixels = 1024 * 1024 // downsamples e.g. 1024x1024 agent icons
		private nonisolated static let downsampleMaxPixelEdge = 256
		
		func state(for image: AssetImage) -> CacheState? {
			cached[image]
		}
		
		func outlinedImage(for key: OutlinedKey) -> UIImage? {
			outlined[key]
		}
		
		func storeOutlined(_ image: UIImage, for key: OutlinedKey) {
			outlined[key] = image
		}
		
		func store(_ state: CacheState, for image: AssetImage, forceUpdate: Bool) {
			if !forceUpdate, cached[image] != nil { return }
			cached[image] = state
			if forceUpdate {
				outlined = outlined.filter { $0.key.image != image }
			}
		}
		
		func updateState(for image: AssetImage, forceUpdate: Bool) {
			if !forceUpdate, cached[image] != nil { return }
			store(Self.loadStateOffMain(for: image), for: image, forceUpdate: forceUpdate)
		}
		
		nonisolated static func loadStateOffMain(for image: AssetImage) -> CacheState {
			let fileURL = image.localURL as CFURL
			if
				let source = CGImageSourceCreateWithURL(fileURL, nil),
				let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
				let width = properties[kCGImagePropertyPixelWidth] as? Int,
				let height = properties[kCGImagePropertyPixelHeight] as? Int
			{
				let pixels = width * height
				if pixels <= Self.cacheSizeLimit {
					guard let loaded = image.load() else { return .missing }
					return .cached(loaded.preparingForDisplay() ?? loaded)
				} else if pixels <= Self.maxDownsampledSourcePixels {
					let options: [CFString: Any] = [
						kCGImageSourceCreateThumbnailFromImageAlways: true,
						kCGImageSourceThumbnailMaxPixelSize: Self.downsampleMaxPixelEdge,
						kCGImageSourceCreateThumbnailWithTransform: true,
						kCGImageSourceShouldCacheImmediately: true,
					]
					if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
						return .cached(UIImage(cgImage: cgThumb))
					}
					return .tooLarge
				} else {
					return .tooLarge
				}
			}
			guard let loaded = image.load() else { return .missing }
			guard let raw = loaded.cgImage, raw.width * raw.height <= Self.cacheSizeLimit else {
				return .tooLarge
			}
			return .cached(loaded.preparingForDisplay() ?? loaded)
		}
		
		nonisolated static func renderOutlined(_ image: UIImage, radius: CGFloat) -> UIImage {
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
			let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
				let rect = CGRect(origin: .zero, size: size)
				let steps = 12
				for step in 0..<steps {
					let angle = (CGFloat(step) / CGFloat(steps)) * (.pi * 2)
					mask.draw(in: rect.offsetBy(dx: cos(angle) * strokePx, dy: sin(angle) * strokePx))
				}
				image.draw(in: rect)
			}
			return rendered
		}
		
		func reset() {
			cached = [:]
			outlined = [:]
		}
	}
	
	private final actor Updater {
		private var inProgress: [AssetImage: [CheckedContinuation<Void, Never>]] = [:]
		private var completed: Set<AssetImage> = []
		
		let stateUpdates = PassthroughSubject<StateUpdate, Never>()
		let cache: ImageCache
		
		init(cache: ImageCache) {
			self.cache = cache
		}
		
		func resetCompleted() {
			completed = []
		}
		
		func prepareOutlined(image: AssetImage, key: OutlinedKey, radius: CGFloat) async {
			var cacheState = await cache.state(for: image)
			if cacheState == nil {
				await download(image)
				cacheState = await cache.state(for: image)
			}
			guard case .cached(let base) = cacheState else { return }
			let outlined = ImageCache.renderOutlined(base, radius: radius)
			await cache.storeOutlined(outlined, for: key)
			enqueueUpdate(of: image, to: .available)
		}
		
		func download(_ image: AssetImage) async {
			guard !completed.contains(image) else { return }
			if inProgress[image] != nil {
				await withCheckedContinuation {
					inProgress[image]!.append($0)
				}
				return
			}
			inProgress[image] = []
			defer {
				let toMark = inProgress[image]!
				inProgress[image] = nil
				for continuation in toMark {
					continuation.resume()
				}
			}
			
			if image.hasMetadata {
				do {
					let meta = try image.loadMetadata()
					// already checked against this version
					if meta.lastVersionCheckedAgainst == VersionHolder.version {
						let predecoded = ImageCache.loadStateOffMain(for: image)
						await cache.store(predecoded, for: image, forceUpdate: false)
						enqueueUpdate(of: image, to: .available)
						completed.insert(image)
						return
					}
				} catch {
					print("could not load metadata for \(image): \(error)")
				}
			}
			
			do {
				enqueueUpdate(of: image, to: .downloading)
				let wasReplaced = try await image.ensureDownloaded()
				let predecoded = ImageCache.loadStateOffMain(for: image)
				await cache.store(predecoded, for: image, forceUpdate: wasReplaced)
				enqueueUpdate(of: image, to: .available)
			} catch {
				print("error loading image from \(image.url) stored at \(image.localURL):")
				dump(error)
				enqueueUpdate(of: image, to: .errored(error))
				return
			}
			
			completed.insert(image)
			
			var meta = (try? image.loadMetadata()) ?? .init(
				versionDownloaded: VersionHolder.version,
				lastVersionCheckedAgainst: VersionHolder.version
			)
			meta.lastVersionCheckedAgainst = VersionHolder.version
			do {
				try image.save(meta)
			} catch {
				print("could not save metadata for \(image): \(error)")
			}
		}
		
		private func enqueueUpdate(of image: AssetImage, to state: ImageState) {
			stateUpdates.send(.init(image: image, state: state))
		}
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
	
	var hasMetadata: Bool {
		FileManager.default.fileExists(atPath: metadataURL.path)
	}
	
	func loadMetadata() throws -> ImageMetadata {
		try JSONDecoder().decode(ImageMetadata.self, from: Data(contentsOf: metadataURL))
	}
	
	func save(_ metadata: ImageMetadata) throws {
		try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
	}
}

extension ImageManager.CacheState: CustomStringConvertible {
	var description: String {
		switch self {
		case .missing:
			return "CacheState.missing"
		case .tooLarge:
			return "CacheState.tooLarge"
		case .cached:
			return "CacheState.cached"
		}
	}
}
