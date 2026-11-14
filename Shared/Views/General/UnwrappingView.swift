import SwiftUI

struct UnwrappingView<Value, Content: View>: View {
	let value: Value?
	let placeholder: Text
	@ViewBuilder var content: (Value) -> Content
	
	init(value: Value?, placeholder: LocalizedStringKey, @ViewBuilder content: @escaping (Value) -> Content) {
		self.init(value: value, placeholder: Text(placeholder), content: content)
	}
	
	init(value: Value?, placeholder: Text, @ViewBuilder content: @escaping (Value) -> Content) {
		self.value = value
		self.placeholder = placeholder
		self.content = content
	}
	
	init(value: Value?, placeholder: Text) where Value == String, Content == Text {
		self.init(value: value, placeholder: placeholder) { Text($0) }
	}
	
	var body: some View {
		if let value {
			content(value)
		} else {
			placeholder
				.foregroundColor(.secondary)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}

struct AssetsUnwrappingView<Content: View>: View {
	@ViewBuilder var content: (_ assets: AssetCollection) -> Content
	
	@Environment(\.assets) private var assets
	@EnvironmentObject private var assetManager: AssetManager
	
	var body: some View {
		if let assets {
			content(assets)
		} else if let error = assetManager.error {
			VStack(spacing: 16) {
				Image(systemName: "exclamationmark.triangle")
					.font(.largeTitle)
					.foregroundColor(.secondary)
				Text("Couldn't load assets")
					.font(.headline)
				Text(error.localizedDescription)
					.font(.caption)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal)
				AsyncButton("Try Again") {
					await assetManager.tryLoadAssets()
				}
				.buttonStyle(.borderedProminent)
			}
			.padding()
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			VStack(spacing: 12) {
				ProgressView()
				Text("Loading assets…")
					.font(.subheadline)
					.foregroundColor(.secondary)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}

