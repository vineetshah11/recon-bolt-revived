import SwiftUI
import ValorantAPI

struct ReferenceView: View {
	private let columns = [GridItem(.adaptive(minimum: 150, maximum: 280), spacing: 14)]

	var body: some View {
		AssetsUnwrappingView { assets in
			ScrollView {
				LazyVGrid(columns: columns, spacing: 14) {
					NavigationLink {
						MapListView()
					} label: {
						ReferenceCard(title: "Maps", systemImage: "map") {
							MapImage.splash(.ascent)
								.aspectRatio(contentMode: .fill)
						}
					}

					NavigationLink {
						AgentListView()
					} label: {
						ReferenceCard(title: "Agents", systemImage: "person") {
							Color(red: 0.16, green: 0.07, blue: 0.11)
								.overlay {
									AgentImage.fullPortrait(.jett)
										.aspectRatio(contentMode: .fill)
								}
						}
					}

					NavigationLink {
						WeaponListView()
					} label: {
						ReferenceCard(title: "Weapons", systemImage: "scope") {
							Color(red: 0.09, green: 0.11, blue: 0.15)
								.overlay {
									WeaponImage.displayIcon(.vandal)
										.aspectRatio(contentMode: .fill)
								}
						}
					}
				}
				.buttonStyle(.plain)
				.padding(16)

				Text("Version \(assets.version.version)", comment: "Reference")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.padding(.bottom, 16)
			}
			.background(Color(red: 0.04, green: 0.06, blue: 0.08).ignoresSafeArea())
		}
		.navigationTitle("Explore")
	}
}

/// A full-bleed artwork tile used by the reference grid.
struct ReferenceCard<Background: View>: View {
	var title: LocalizedStringKey
	var systemImage: String
	@ViewBuilder var background: Background

	private let cornerRadius: CGFloat = 16
	private let height: CGFloat = 160

	var body: some View {
		ZStack(alignment: .bottomLeading) {
			background
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.clipped()

			LinearGradient(
				colors: [.clear, .black.opacity(0.55), .black.opacity(0.9)],
				startPoint: .center,
				endPoint: .bottom
			)

			HStack(spacing: 6) {
				Image(systemName: systemImage)
					.font(.system(size: 13, weight: .bold))
					.foregroundStyle(Color.valorantRed)

				Text(title)
					.font(.system(size: 17, weight: .bold, design: .rounded))
					.foregroundStyle(.white)
			}
			.padding(12)
			.shadow(color: .black.opacity(0.6), radius: 4, y: 1)
		}
		.frame(maxWidth: .infinity)
		.frame(height: height)
		.background(Color(red: 20 / 255, green: 29 / 255, blue: 38 / 255))
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.strokeBorder(.white.opacity(0.12), lineWidth: 1)
		}
		.contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
	}
}

#if DEBUG
struct ReferenceView_Previews: PreviewProvider {
	static var previews: some View {
		ReferenceView()
			.withToolbar()
	}
}
#endif
