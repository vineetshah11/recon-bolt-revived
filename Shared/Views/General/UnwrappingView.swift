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
	
	@Environment(\.assets) private var environmentAssets: AssetCollection?
	@EnvironmentObject private var assetManager: AssetManager
	
	private var assets: AssetCollection? {
		environmentAssets ?? assetManager.assets
	}
	
	var body: some View {
		if let resolvedAssets = assets {
			content(resolvedAssets)
		} else if assetManager.isDownloading {
			VStack(spacing: 12) {
				ProgressView()
				Text(String(localized: "Loading assets…", comment: "Asset loading: shown while assetManager.isDownloading is true"))
					.font(.subheadline)
					.foregroundColor(.secondary)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if let error = assetManager.error {
			VStack(spacing: 16) {
				Image(systemName: "exclamationmark.triangle")
					.font(.largeTitle)
					.foregroundColor(.secondary)
				Text(String(localized: "Couldn't load assets", comment: "Asset loading: shown when assetManager.error is set"))
					.font(.headline)
				Text(error.localizedDescription)
					.font(.caption)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal)
				AsyncButton(
					String(localized: "Try Again", comment: "Asset loading: retry button")
				) {
					await assetManager.tryLoadAssets()
				}
				.buttonStyle(.borderedProminent)
			}
			.padding()
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			// idle and empty: the environment hasn't handed us anything and the manager hasn't errored,
			// so kick off a load and keep showing the loading state until isDownloading turns off.
			VStack(spacing: 12) {
				ProgressView()
				Text(String(localized: "Assets not loaded!", comment: "Asset loading: shown when assets are missing and idle; triggers tryLoadAssets"))
					.font(.subheadline)
					.foregroundColor(.secondary)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.task {
				await assetManager.tryLoadAssets()
			}
		}
	}
}

