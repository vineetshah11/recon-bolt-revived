import Foundation
import SwiftUI
import Protoquest
import HandyOperators

private let fileManager = FileManager.default

struct AssetImage: Hashable, Identifiable, Sendable {
	var url: URL
	
	var id: Self { self }
	
	@ViewBuilder
	func view(
		renderingMode: Image.TemplateRenderingMode? = nil,
		aspectRatio: CGFloat? = nil,
		maxScale: CGFloat? = nil,
		outlineRadius: CGFloat? = nil,
		preferFullResolution: Bool = false,
		shouldLoadImmediately: Bool = false,
		bucket: ImageBucket? = nil
	) -> some View {
		let resolvedBucket: ImageBucket = {
			if let bucket {
				return bucket
			} else if preferFullResolution || maxScale != nil {
				return .full
			} else if shouldLoadImmediately {
				return (aspectRatio ?? 0) >= 2.2 ? .banner : .icon
			} else {
				return (aspectRatio ?? 0) >= 2.2 ? .banner : .medium
			}
		}()
		
		ImageView(
			image: self,
			bucket: resolvedBucket,
			renderingMode: renderingMode,
			aspectRatio: aspectRatio,
			maxScale: maxScale,
			outlineRadius: outlineRadius
		)
		.id(self)
	}
	
#if WIDGETS
	static var used: Set<Self> = []
	@MainActor
	static var preloaded: [Self: Image] = [:]
#endif
	
	var localURL: URL {
		Self.localFolder.appendingPathComponent(url.path, isDirectory: false)
	}
	
	func load() -> UIImage? {
		.init(contentsOfFile: localURL.path)
	}
	
	private static let oldLocalFolder = try! fileManager
		.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true
		)
		.appendingPathComponent("AssetImage", isDirectory: true)
	
	static var cacheFolderURL: URL { localFolder }
	
	private static let localFolder: URL = {
		if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.juliand665.Recon-Bolt.shared") {
			return groupURL
				.appendingPathComponent("Library", isDirectory: true)
				.appendingPathComponent("Caches", isDirectory: true)
				.appendingPathComponent("AssetImage", isDirectory: true)
		}
		return oldLocalFolder
	}()
	<- migrate(to:)
	
	private static func migrate(to localFolder: URL) {
		guard localFolder.standardizedFileURL != oldLocalFolder.standardizedFileURL else { return }
		guard fileManager.fileExists(atPath: oldLocalFolder.path) else { return }
		do {
			try fileManager.moveItem(at: oldLocalFolder, to: localFolder)
			print("migration succeeded!")
		} catch {
			print("migration failed!", error)
			try? fileManager.removeItem(at: oldLocalFolder) // oh well
		}
	}
	
	static func removeCachedFiles() throws {
		try fileManager.removeItem(at: localFolder)
	}
	
	private struct ImageView: View {
		let image: AssetImage
		let bucket: ImageBucket
		var renderingMode: Image.TemplateRenderingMode?
		/// aspect ratio for the placeholder shown when the image is not loaded
		var aspectRatio: CGFloat?
		var maxScale: CGFloat?
		var outlineRadius: CGFloat?
		
#if !WIDGETS
		@Environment(\.imageManager) private var manager
		
		@State private var loadedImage: UIImage?
		@State private var isDownloading = false
		@State private var loadError: Error?
		@State private var isShowingErrorAlert = false
		@State private var reloadToken = 0
		@State private var forceRetry = false
		
		private struct TaskKey: Equatable {
			let image: AssetImage
			let bucket: ImageBucket
			let outlineRadiusTenths: Int?
			let reloadToken: Int
		}
		
		private var outlineRadiusTenths: Int? {
			outlineRadius.map { Int(($0 * 10).rounded()) }
		}
		
		private var taskKey: TaskKey {
			TaskKey(
				image: image,
				bucket: bucket,
				outlineRadiusTenths: outlineRadiusTenths,
				reloadToken: reloadToken
			)
		}
#endif
		
		var body: some View {
#if WIDGETS
			let _ = used.insert(image)
			if let loaded = preloaded[image] {
				loaded
					.renderingMode(renderingMode)
					.resizable()
					.scaledToFit()
			} else {
				Color.primary.opacity(0.1)
					.aspectRatio(aspectRatio, contentMode: .fit)
			}
#else
			let cachedExact = manager.cachedImage(for: image, bucket: bucket, outlineRadius: outlineRadius)
			let cachedBase = (outlineRadius != nil && cachedExact == nil)
				? manager.cachedImage(for: image, bucket: bucket, outlineRadius: nil)
				: nil
			let previewImage = (isInSwiftUIPreview && loadedImage == nil && cachedExact == nil && cachedBase == nil)
				? manager.syncPreviewImage(for: image, bucket: bucket, outlineRadius: outlineRadius)
				: nil
			let displayed = loadedImage ?? cachedExact ?? cachedBase ?? previewImage
			
			Group {
				if let displayed {
					Image(uiImage: displayed)
						.renderingMode(renderingMode)
						.resizable()
						.scaledToFit()
						.frame(
							maxWidth: maxScale.map { $0 * displayed.size.width },
							maxHeight: maxScale.map { $0 * displayed.size.height }
						)
				} else {
					Color.primary.opacity(0.1)
						.aspectRatio(aspectRatio, contentMode: .fit)
						.overlay {
							if isDownloading {
								ProgressView()
							} else if loadError != nil {
								Image(systemName: "xmark.octagon.fill")
							}
						}
						.onTapGesture {
							guard let loadError else { return }
							isShowingErrorAlert = true
							self.loadError = loadError
							forceRetry = true
							reloadToken &+= 1
						}
						.alert(
							"Image failed to load!",
							isPresented: $isShowingErrorAlert,
							presenting: loadError
						) { error in
							Button("Copy Error Details") {
								UIPasteboard.general.string = error.localizedDescription
							}
							Button("OK") {}
						}
				}
			}
			.task(id: taskKey) {
				let shouldRetry = forceRetry
				if shouldRetry {
					forceRetry = false
				}
				if !shouldRetry, manager.cachedImage(for: image, bucket: bucket, outlineRadius: outlineRadius) != nil {
					manager.scheduleRevalidationIfNeeded(for: image)
					return
				}
				do {
					let result = try await manager.loadImage(
						for: image,
						bucket: bucket,
						outlineRadius: outlineRadius,
						forceRetry: shouldRetry,
						onDownloadStart: {
							Task { @MainActor in
								isDownloading = true
							}
						}
					)
					guard !Task.isCancelled else { return }
					loadedImage = result
					isDownloading = false
					loadError = nil
				} catch is CancellationError {
					isDownloading = false
				} catch {
					guard !Task.isCancelled else { return }
					isDownloading = false
					loadError = error
				}
			}
			.onReceive(manager.imageDidUpdate) { updated in
				guard updated == nil || updated == image else { return }
				loadedImage = nil
				loadError = nil
				isDownloading = false
				forceRetry = false
				reloadToken &+= 1
			}
#endif
		}
	}
}

extension Optional where Wrapped == AssetImage {
	@ViewBuilder
	func view(
		renderingMode: Image.TemplateRenderingMode? = nil,
		bucket: ImageBucket? = nil
	) -> some View {
		if let self {
			self.view(renderingMode: renderingMode, bucket: bucket)
		} else {
			Color.gray
		}
	}
}

extension AssetImage {
	func downloadToDisk() async throws {
		let client = AssetImageClient.shared
		let imageData = try await client.imageData(at: url)
		guard !imageData.isEmpty else {
			print("got empty image data for \(self)")
			throw FetchError.noDataReceived
		}
		try fileManager.createDirectory(
			at: localURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try imageData.write(to: localURL, options: .atomic)
	}
	
	/// - returns: whether a new image was downloaded (false means old image is still correct)
	@discardableResult
	func ensureDownloaded() async throws -> Bool {
		let client = AssetImageClient.shared
		
		// don't download images that we already have (assuming size will always change when the image changes)
		if let existingSize = fileManager.sizeOfItem(atPath: localURL.path) {
			if let newSize = try await client.sizeOfImage(at: url) {
				guard newSize != existingSize else { return false }
			} else {
				return false
			}
		} else {
			assert(!fileManager.fileExists(atPath: localURL.path))
		}
		
		try await downloadToDisk()
		return true
	}
	
	private enum FetchError: Error {
		case noDataReceived
	}
}

extension FileManager {
	func sizeOfItem(atPath path: String) -> Int? {
		guard let size = try? attributesOfItem(atPath: path)[.size] else { return nil }
		return (size as! NSNumber).intValue
	}
}

struct AssetImageClient {
	static let shared = Self()
	
	let networkLayer: Protolayer = {
		let config = URLSessionConfiguration.ephemeral
		config.urlCache = nil
		config.timeoutIntervalForRequest = 20
		config.timeoutIntervalForResource = 60
		config.httpMaximumConnectionsPerHost = 6
		return Protolayer.urlSession(URLSession(configuration: config))
	}()
	
	// TODO: use a hash instead
	func sizeOfImage(at url: URL) async throws -> Int? {
		let request = URLRequest(url: url) <- {
			$0.httpMethod = "HEAD"
		}
		let response = try await networkLayer.send(request)
		guard let expected = response.httpMetadata?.expectedContentLength, expected > 0 else {
			return nil
		}
		return Int(expected)
	}
	
	func imageData(at url: URL) async throws -> Data {
		try await networkLayer.send(URLRequest(url: url)).body
	}
}

extension AssetImage: Codable {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		url = try container.decode(URL.self)
	}
	
	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(url)
	}
}
