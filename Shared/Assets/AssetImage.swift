import Foundation
import SwiftUI
import Protoquest
import HandyOperators

private let fileManager = FileManager.default

struct AssetImage: Hashable, Identifiable {
	var url: URL
	
	var id: Self { self }
	
	@ViewBuilder
	func view(
		renderingMode: Image.TemplateRenderingMode? = nil,
		aspectRatio: CGFloat? = nil,
		maxScale: CGFloat? = nil,
		outlineRadius: CGFloat? = nil,
		preferFullResolution: Bool = false,
		shouldLoadImmediately: Bool = false
	) -> some View {
		ImageView(
			image: self,
			renderingMode: renderingMode,
			aspectRatio: aspectRatio,
			maxScale: maxScale,
			outlineRadius: outlineRadius,
			preferFullResolution: preferFullResolution || maxScale != nil,
			shouldLoadImmediately: isInSwiftUIPreview || shouldLoadImmediately
		)
		.id(self)
#if DEBUG
		.modifier(ImageManagerProvider())
#endif
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
		var renderingMode: Image.TemplateRenderingMode?
		/// aspect ratio for the placeholder shown when the image is not loaded
		var aspectRatio: CGFloat?
		var maxScale: CGFloat?
		var outlineRadius: CGFloat?
		var preferFullResolution: Bool = false
		var shouldLoadImmediately: Bool = false
		@State var loaded: UIImage?
		@State private var isLoadingLarge = false
		
		@State private var isShowingErrorAlert = false
		@State private var loadError: Error?
		
		@EnvironmentObject private var manager: ImageManager
		
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
			switch manager.state(for: image) {
			case nil:
				// onAppear/task may lag while scrolling in List; start deduplicated download safely
				let _ = manager.ensureDownloadStarted(for: image)
				content
			case .downloading:
				content
					.overlay { ProgressView() }
			case .errored(let error):
				content
					.overlay { Image(systemName: "xmark.octagon.fill") }
					.onTapGesture {
						loadError = error
						isShowingErrorAlert = true
						manager.ensureDownloadStarted(for: image, retrying: true)
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
			case .available:
				content
			}
#endif
		}
		
#if !WIDGETS
		@ViewBuilder
		var content: some View {
			if let displayed = displayedImage {
				Image(uiImage: displayed)
					.renderingMode(renderingMode)
					.resizable()
					.scaledToFit()
					.onChange(of: manager.cacheState(for: image)) { _ in
						self.loaded = nil
						self.isLoadingLarge = false
					}
					.frame(
						maxWidth: maxScale.map { $0 * displayed.size.width },
						maxHeight: maxScale.map { $0 * displayed.size.height }
					)
			} else {
				let _ = loadLargeIfNeeded()
				Color.primary.opacity(0.1)
					.aspectRatio(aspectRatio, contentMode: .fit)
			}
		}
		
		private var displayedImage: UIImage? {
			if preferFullResolution {
				if let full = loaded ?? manager.largeImage(for: image) {
					return full
				}
				if case .available = manager.state(for: image) {
					loadLargeIfNeeded(evenWhenCached: true)
				}
			}
			let cachedImage = cached
			if let outlineRadius {
				if let outlined = manager.outlinedImage(for: image, radius: outlineRadius) {
					return outlined
				}
				let isAvailable: Bool
				if case .available = manager.state(for: image) {
					isAvailable = true
				} else {
					isAvailable = false
				}
				if cachedImage != nil || isAvailable {
					manager.ensureOutlinedPrepared(for: image, radius: outlineRadius)
				}
			}
			return loaded ?? cachedImage ?? manager.largeImage(for: image)
		}
		
		private var cached: UIImage? {
			let state = manager.cacheState(for: image, loadImmediately: shouldLoadImmediately)
			guard case .cached(let image) = state else { return nil }
			return image
		}
		
		private func loadLargeIfNeeded(evenWhenCached: Bool = false) {
			let cacheState = manager.cacheState(for: image)
			guard cacheState == .tooLarge || evenWhenCached else { return }
			guard !isLoadingLarge, loaded == nil else { return }
			DispatchQueue.main.async {
				guard !self.isLoadingLarge, self.loaded == nil else { return }
				self.isLoadingLarge = true
				Task {
					let result = await manager.loadLargeImage(for: image)
					self.loaded = result
					self.isLoadingLarge = false
				}
			}
		}
#endif
	}
}

extension Optional where Wrapped == AssetImage {
	@ViewBuilder
	func view() -> some View {
		if let self {
			self.view()
		} else {
			Color.gray
		}
	}
}

#if DEBUG
@MainActor
let sharedManager: ImageManager? = isInSwiftUIPreview ? .init() : nil

private struct ImageManagerProvider: ViewModifier {
	func body(content: Content) -> some View {
		if isInSwiftUIPreview, let sharedManager {
			content.environmentObject(sharedManager)
		} else {
			content
		}
	}
}
#endif

extension AssetImage {
	/// - returns: whether a new image was downloaded (false means old image is still correct)
	func ensureDownloaded() async throws -> Bool {
		let client = AssetImageClient.shared
		
		// don't download images that we already have (assuming size will always change when the image changes)
		if let existingSize = fileManager.sizeOfItem(atPath: localURL.path) {
			print("\(url) found existing size \(existingSize)")
			let newSize = try await client.sizeOfImage(at: url)
			guard newSize != existingSize else { return false }
		} else {
			assert(!fileManager.fileExists(atPath: localURL.path))
		}
		
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
	
	let networkLayer = Protolayer.urlSession()
	
	// TODO: use a hash instead
	func sizeOfImage(at url: URL) async throws -> Int {
		let request = URLRequest(url: url) <- {
			$0.httpMethod = "HEAD"
		}
		let response = try await networkLayer.send(request)
		return .init(response.httpMetadata!.expectedContentLength)
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
