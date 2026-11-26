import SwiftUI
import SwiftUIMissingPieces

#if DEBUG
var isInSwiftUIPreview: Bool {
	#if WIDGETS
	// i'm so sorry
	ProcessInfo.processInfo.environment["HOME"]?.contains("Previews") == true
	#else
	ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
	#endif
}
#else
let isInSwiftUIPreview = false
#endif

extension Color {
	static let separator = Color(.separator)
	static let groupedBackground = Self(.systemGroupedBackground)
	static let secondaryGroupedBackground = Self(.secondarySystemGroupedBackground)
	static let tertiaryGroupedBackground = Self(.tertiarySystemGroupedBackground)
	static let valorantBlue = adaptive(light: (0x12, 0xA0, 0x9F), dark: (0x66, 0xC2, 0xA9))
	static let valorantRed = adaptive(light: (0xDA, 0x2A, 0x58), dark: (0xF0, 0x5C, 0x57))
	static let valorantSelf = adaptive(light: (0x00, 0x2A, 0xA3), dark: (0xEA, 0xEE, 0xB2))
	
	private static func adaptive(
		light: (UInt8, UInt8, UInt8),
		dark: (UInt8, UInt8, UInt8)
	) -> Self {
		Self(uiColor: UIColor { traits in
			let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
			return UIColor(
				red: CGFloat(r) / 255,
				green: CGFloat(g) / 255,
				blue: CGFloat(b) / 255,
				alpha: 1
			)
		})
	}
}

extension View {
	func frame(size: CGFloat, alignment: Alignment = .center) -> some View {
		frame(width: size, height: size, alignment: alignment)
	}
}

extension View {
	@ViewBuilder
	func withToolbar(allowLargeTitles: Bool = true) -> some View {
		NavigationView {
			self.if(!allowLargeTitles) {
				$0.navigationBarTitleDisplayMode(.inline)
			}
		}
		.navigationViewStyle(.stack)
	}
}

private final class BundledAssetCache: @unchecked Sendable {
	static let shared = BundledAssetCache()
	
	private let images: NSCache<NSString, UIImage> = {
		let cache = NSCache<NSString, UIImage>()
		cache.countLimit = 128
		cache.totalCostLimit = 16 * 1024 * 1024
		return cache
	}()
	private let lock = NSLock()
	private var missingNames: Set<String> = []
	
	func lookup(_ name: String) -> (hit: Bool, image: UIImage?) {
		if let cached = images.object(forKey: name as NSString) {
			return (true, cached)
		}
		lock.lock()
		let isMissing = missingNames.contains(name)
		lock.unlock()
		return isMissing ? (true, nil) : (false, nil)
	}
	
	func store(_ image: UIImage?, for name: String) {
		guard let image else {
			lock.lock()
			missingNames.insert(name)
			lock.unlock()
			return
		}
		let cost: Int
		if let cgImage = image.cgImage {
			cost = max(1, cgImage.bytesPerRow * cgImage.height)
		} else {
			cost = max(1, Int(image.size.width * image.scale) * Int(image.size.height * image.scale) * 4)
		}
		images.setObject(image, forKey: name as NSString, cost: cost)
	}
}

extension UIImage {
	/// Loads an asset image from either the compiled asset catalog or `Bundle.module/BundledAssets`.
	static func bundledAsset(named name: String) -> UIImage? {
		let cached = BundledAssetCache.shared.lookup(name)
		if cached.hit {
			return cached.image
		}
		
		let resolved: UIImage?
		if let assetImage = UIImage(named: name) {
			resolved = assetImage
		} else if let baseURL = Bundle.module.url(forResource: "BundledAssets", withExtension: nil) {
			let fileURL = baseURL.appendingPathComponent("\(name).png")
			if let image = UIImage(contentsOfFile: fileURL.path) {
				resolved = image
			} else {
				let scaledURL = baseURL.appendingPathComponent("\(name)@3x.png")
				if let data = try? Data(contentsOf: scaledURL) {
					resolved = UIImage(data: data, scale: 3)
				} else {
					resolved = nil
				}
			}
		} else {
			resolved = nil
		}
		
		BundledAssetCache.shared.store(resolved, for: name)
		return resolved
	}
}

extension Image {
	init?(at url: URL) {
		guard let image = UIImage(contentsOfFile: url.path) else { return nil }
		self.init(uiImage: image)
	}
	
	static func bundledAsset(_ name: String, renderingMode: TemplateRenderingMode? = nil) -> Self {
		let image = UIImage.bundledAsset(named: name).map(Image.init(uiImage:)) ?? Image(name)
		return image.renderingMode(renderingMode)
	}
}

extension ShapeStyle where Self == Color {
	// not sure why apple missed this tbh
	static var accentColor: Self { Color.accentColor }
}

extension Gradient {
	init(_ color: Color, opacities: [Double] = [1, 0]) {
		self.init(colors: opacities.map(color.opacity))
	}
}

extension View {
	func measuring<Key: PreferenceKey>(
		_ path: KeyPath<CGSize, CGFloat>, as key: Key.Type
	) -> some View where Key.Value == CGFloat {
		modifier(Measuring<Key>(measurePath: path))
	}
}

private struct Measuring<Key: PreferenceKey>: ViewModifier where Key.Value == CGFloat {
	let measurePath: KeyPath<CGSize, CGFloat>
	
	@State private var value = 0.0
	
	func body(content: Content) -> some View {
		content
			.measured { value = $0[keyPath: measurePath] }
			.preference(key: Key.self, value: value)
	}
}

extension View {
	func onSceneActivation(perform task: @escaping () async -> Void) -> some View {
		modifier(OnSceneActivationModifier(task: task))
	}
}

private struct OnSceneActivationModifier: ViewModifier {
	var task: () async -> Void
	
	@Environment(\.scenePhase) private var scenePhase
	@State private var lastPhase: ScenePhase?
	
	func body(content: Content) -> some View {
		content
			.task(id: scenePhase) {
				let previous = lastPhase
				lastPhase = scenePhase
				guard scenePhase == .active, let previous, previous != .active else { return }
				await task()
			}
	}
}

extension View {
	@ViewBuilder
	func aligningListRowSeparator() -> some View {
		if #available(iOS 16.0, *) {
			alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
		} else {
			self
		}
	}
}

extension Binding {
	func contains<T: Hashable>(_ value: T) -> Binding<Bool> where Value == Set<T> {
		.init(
			get: { wrappedValue.contains(value) },
			set: {
				if $0 {
					wrappedValue.insert(value)
				} else {
					wrappedValue.remove(value)
				}
			}
		)
	}
	
	/// - note: this cannot be set back to true when currently false
	func isSome<T>() -> Binding<Bool> where Value == T? {
		.init(
			get: { wrappedValue != nil },
			set: { wrappedValue = $0 ? wrappedValue : nil }
		)
	}
	
	func equals<T: Equatable>(_ value: T) -> Binding<Bool> where Value == T? {
		.init(
			get: { wrappedValue == value },
			set: { isEqual in
				guard (wrappedValue == value) != isEqual else { return }
				wrappedValue = isEqual ? value : nil
			}
		)
	}
}

extension View {
	/// ``sheet(item:onDismiss:content:)`` nils out the binding before calling onDismiss, but sometimes you still want to access it.
	func sheet<Item, Content>(
		caching item: Binding<Item?>,
		content: @escaping (Item) -> Content,
		onDismiss: @escaping (Item) -> Void
	) -> some View where Item: Identifiable, Content: View {
		let cached = item.wrappedValue
		return sheet(
			item: item,
			onDismiss: { onDismiss(cached!) },
			content: content
		)
	}
}

extension View {
	func placeholder(`if` isPlaceholder: Bool) -> some View {
		redacted(reason: isPlaceholder ? .placeholder : [])
	}
}

/// button that looks like a ``NavigationLink``
struct NavigationButton<Label: View>: View {
	var action: () -> Void
	@ViewBuilder var label: Label
	
	var body: some View {
		Button(action: action) {
			NavigationLink {} label: {
				HStack {
					label
				}
			}
			.tint(.primary)
		}
	}
}
