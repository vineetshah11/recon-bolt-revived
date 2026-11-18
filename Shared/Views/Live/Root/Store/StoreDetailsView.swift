import SwiftUI
import ValorantAPI

struct StoreDetailsView: View {
	var updateTime: Date
	var storefront: Storefront
	var wallet: StoreWallet

	@State private var isNightMarketExpanded = false
	@State private var dailyCountdownStart = Date()
	@State private var nightMarketCountdownStart = Date()

	@Environment(\.assets) private var assets

	private static let currencies: [Currency.ID] = [
		.valorantPoints,
		.radianitePoints,
		.kingdomCredits
	]

	private let backgroundColor = Color(
		red: 15 / 255,
		green: 25 / 255,
		blue: 35 / 255
	)

	private let cardColor = Color(
		red: 20 / 255,
		green: 34 / 255,
		blue: 49 / 255
	)

	private let valorantRed = Color(
		red: 255 / 255,
		green: 70 / 255,
		blue: 85 / 255
	)

	private let gridColumns = [
		GridItem(.flexible(), spacing: 12),
		GridItem(.flexible(), spacing: 12)
	]

	var body: some View {
		ScrollView(showsIndicators: false) {
			VStack(alignment: .leading, spacing: 26) {

				// MARK: Header

				header

				// MARK: Featured Bundles

				if !storefront.featuredBundle.bundles.isEmpty {
					VStack(alignment: .leading, spacing: 14) {
						sectionHeader(
							title: "FEATURED",
							subtitle: "Limited-time collection"
						)

						ForEach(storefront.featuredBundle.bundles) { bundle in
							NavigationLink {
								BundleDetailsView(bundle: bundle)
							} label: {
								bundleCell(for: bundle)
									.clipShape(
										RoundedRectangle(
											cornerRadius: 16,
											style: .continuous
										)
									)
									.overlay {
										RoundedRectangle(
											cornerRadius: 16,
											style: .continuous
										)
										.stroke(
											valorantRed.opacity(0.25),
											lineWidth: 1
										)
									}
									.shadow(
										color: valorantRed.opacity(0.10),
										radius: 14,
										y: 5
									)
							}
							.buttonStyle(.plain)
						}
					}
				}

				// MARK: Accessories Store

				if let offers = storefront.accessoryStore.offers {
					VStack(alignment: .leading, spacing: 14) {
						sectionHeader(
							title: "ACCESSORIES",
							subtitle: "Kingdom credits collection"
						)

						NavigationLink {
							AccessoryStoreView(
								accessoryStore: storefront.accessoryStore
							) {
								HStack {
									remainingTimeLabel(storefront.accessoryStore.remainingDuration)
										.foregroundColor(.primary)
									Spacer()
									CurrencyLabel(amount: wallet[.kingdomCredits], currencyID: .kingdomCredits)
								}
							}
						} label: {
							accessoryStoreCell(offers: offers)
								.background(cardColor)
								.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
								.overlay {
									RoundedRectangle(cornerRadius: 14, style: .continuous)
										.stroke(Color.white.opacity(0.08), lineWidth: 1)
								}
								.tint(.primary)
						}
						.buttonStyle(.plain)
					}
				}

				// MARK: Night Market

				if let nightMarket = storefront.nightMarket {
					VStack(spacing: 14) {
						Button {
							withAnimation(.spring(
								response: 0.35,
								dampingFraction: 0.82
							)) {
								isNightMarketExpanded.toggle()
							}
						} label: {
							HStack(spacing: 12) {
								Image(systemName: "moon.stars.fill")
									.font(.title3)
									.foregroundStyle(
										Color.purple.opacity(0.95)
									)

								VStack(alignment: .leading, spacing: 3) {
									Text("NIGHT MARKET")
										.font(.headline)
										.foregroundStyle(.white)

									Text("Exclusive discounted skins")
										.font(.caption)
										.foregroundStyle(
											.white.opacity(0.55)
										)
								}

								Spacer()

								VStack(alignment: .trailing, spacing: 4) {
									countdown(
										nightMarket.remainingDuration,
										startedAt: nightMarketCountdownStart
									)

									Image(systemName: "chevron.down")
										.font(.caption.weight(.bold))
										.foregroundStyle(.white.opacity(0.5))
										.rotationEffect(
											.degrees(
												isNightMarketExpanded ? 180 : 0
											)
										)
								}
							}
							.padding(16)
							.background(cardColor)
							.clipShape(
								RoundedRectangle(
									cornerRadius: 14,
									style: .continuous
								)
							)
							.overlay {
								RoundedRectangle(
									cornerRadius: 14,
									style: .continuous
								)
								.stroke(
									Color.purple.opacity(0.2),
									lineWidth: 1
								)
							}
						}
						.buttonStyle(.plain)

						if isNightMarketExpanded {
							nightMarketView(for: nightMarket)
								.transition(.opacity.combined(with: .move(edge: .top)))
						}
					}
				}

				// MARK: Daily Store

				VStack(alignment: .leading, spacing: 16) {
					HStack(alignment: .center) {
						VStack(alignment: .leading, spacing: 4) {
							Text("DAILY OFFERS")
								.font(.title3.weight(.heavy))
								.tracking(1.2)
								.foregroundStyle(.white)

							Text("Your personal weapon rotation")
								.font(.caption)
								.foregroundStyle(.white.opacity(0.55))
						}

						Spacer()

						countdown(
							storefront.dailySkinStore.remainingDuration,
							startedAt: dailyCountdownStart
						)
					}

					LazyVGrid(columns: gridColumns, spacing: 12) {
						ForEach(storefront.dailySkinStore.offers) { offer in
							OfferCell(offer: offer)
								.padding(8)
								.frame(maxWidth: .infinity)
								.background(cardColor)
								.clipShape(
									RoundedRectangle(
										cornerRadius: 14,
										style: .continuous
									)
								)
								.overlay {
									RoundedRectangle(
										cornerRadius: 14,
										style: .continuous
									)
									.stroke(
										Color.white.opacity(0.08),
										lineWidth: 1
									)
								}
						}
					}
				}
			}
			.padding(.horizontal, 18)
			.padding(.top, 20)
			.padding(.bottom, 24)
		}
		.background(backgroundColor.ignoresSafeArea())
		.safeAreaInset(edge: .bottom, spacing: 0) {
			walletBar
		}
		.preferredColorScheme(.dark)
		.onChange(of: storefront.dailySkinStore.remainingDuration) { _ in
			dailyCountdownStart = Date()
		}
		.onChange(of: storefront.nightMarket?.remainingDuration) { _ in
			nightMarketCountdownStart = Date()
		}
	}

	// MARK: - Header

	private var header: some View {
		HStack(alignment: .center) {
			VStack(alignment: .leading, spacing: 5) {
				HStack(spacing: 7) {
					RoundedRectangle(cornerRadius: 2)
						.fill(valorantRed)
						.frame(width: 4, height: 23)

					Text("STORE")
						.font(.system(size: 30, weight: .black))
						.tracking(2)
						.foregroundStyle(.white)
				}

				Text("YOUR DAILY LOADOUT")
					.font(.system(size: 10, weight: .semibold))
					.tracking(2)
					.foregroundStyle(.white.opacity(0.45))
			}

			Spacer()

			VStack(alignment: .trailing, spacing: 6) {
				HStack(spacing: 5) {
					Circle()
						.fill(Color.green)
						.frame(width: 6, height: 6)

					Text("LIVE ROTATION")
						.font(.system(size: 9, weight: .bold))
						.tracking(1)
						.foregroundStyle(.white.opacity(0.7))
				}

				countdown(
					storefront.dailySkinStore.remainingDuration,
					startedAt: dailyCountdownStart
				)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(valorantRed.opacity(0.10))
			.clipShape(RoundedRectangle(cornerRadius: 10))
			.overlay {
				RoundedRectangle(cornerRadius: 10)
					.stroke(valorantRed.opacity(0.2), lineWidth: 1)
			}
		}
	}

	// MARK: - Section Header

	private func sectionHeader(
		title: String,
		subtitle: String
	) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.headline.weight(.heavy))
				.tracking(1.2)
				.foregroundStyle(.white)

			Text(subtitle)
				.font(.caption)
				.foregroundStyle(.white.opacity(0.5))
		}
	}

	// MARK: - Countdown

	private func countdown(
		_ duration: TimeInterval,
		startedAt: Date
	) -> some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			let elapsed = context.date.timeIntervalSince(startedAt)
			let remaining = max(0, Int(duration - elapsed))

			let hours = remaining / 3600
			let minutes = (remaining % 3600) / 60
			let seconds = remaining % 60

			HStack(spacing: 4) {
				Image(systemName: "clock")
					.font(.system(size: 10, weight: .bold))

				Text(
					String(
						format: "%02dh %02dm %02ds",
						hours,
						minutes,
						seconds
					)
				)
				.font(.system(size: 11, weight: .bold, design: .monospaced))
				.monospacedDigit()
			}
			.foregroundStyle(valorantRed)
		}
	}

	// MARK: - Wallet

	private var walletBar: some View {
		HStack(spacing: 0) {
			Image(systemName: "wallet.pass.fill")
				.font(.title3)
				.foregroundStyle(valorantRed)
				.padding(.trailing, 14)

			ForEach(Self.currencies, id: \.self) { currency in
				CurrencyLabel(
					amount: wallet[currency],
					currencyID: currency
				)
				.frame(maxWidth: .infinity)
			}
		}
		.padding(.horizontal, 18)
		.padding(.vertical, 15)
		.background {
			Rectangle()
				.fill(.ultraThinMaterial)
				.overlay {
					Rectangle()
						.fill(backgroundColor.opacity(0.65))
				}
				.overlay(alignment: .top) {
					Rectangle()
						.fill(Color.white.opacity(0.10))
						.frame(height: 1)
				}
				.ignoresSafeArea(edges: .bottom)
		}
	}

	// MARK: - Helpers

	@ViewBuilder
	func bundleCell(for bundle: StoreBundle) -> some View {
		VStack(spacing: 0) {
			if let info = assets?.bundles[bundle.assetID] {
				info.displayIcon.view()
					.aspectRatio(1648/804, contentMode: .fill)
				
				HStack {
					Text(info.displayName)
						.fontWeight(.medium)
						.multilineTextAlignment(.leading)
					
					Spacer()
					
					remainingTimeLabel(bundle.remainingDuration)
					
					Image(systemName: "chevron.forward")
						.foregroundStyle(.secondary)
						.imageScale(.small)
				}
				.padding(12)
			} else {
				Text("Unknown Bundle", comment: "placeholder")
					.padding(12)
			}
		}
	}

	@ViewBuilder
	func nightMarketView(for market: Storefront.NightMarket) -> some View {
		ForEach(market.offers) { offer in
			let reward = offer.offer.rewards.first!
			let resolved = assets?.resolveSkin(.init(rawID: reward.itemID))
			let discountText = Text("-\(offer.discountPercent)%", comment: "Store: night market discount")

			// MARK: Offer pricing
			// `StoreOffer.cost` and `discountedCosts` are keyed by currency, but a night market
			// offer is only ever priced in one currency, so a single `CurrencyLabel` is enough.
			let originalPrice = offer.offer.cost.first
			let discountedPrice = offer.discountedCosts.first

			NavigationLink {
				if let resolved {
					SkinDetailsView(skin: resolved.skin)
				}
			} label: {
				HStack(spacing: 14) {
					// MARK: Skin preview
					ZStack {
						if let icon = resolved?.displayIcon {
							icon.view()
								.aspectRatio(contentMode: .fill)
						} else {
							Rectangle()
								.fill(Color.white.opacity(0.06))
						}
						LinearGradient(
							gradient: Gradient(colors: [
								Color.purple.opacity(0.55),
								Color.purple.opacity(0.12)
							]),
							startPoint: .top,
							endPoint: .bottom
						)
					}
					.frame(width: 120, height: 120)
					.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

					// MARK: Offer details
					VStack(alignment: .leading, spacing: 8) {
						if let name = resolved?.skin.displayName {
							Text(name)
								.font(.system(size: 17, weight: .bold, design: .rounded))
								.foregroundColor(.white)
								.lineLimit(2)
								.multilineTextAlignment(.leading)
						}

						HStack(spacing: 8) {
							VStack(alignment: .leading, spacing: 2) {
								Text("Original price", comment: "Store: night market original price label")
									.font(.caption2.weight(.medium))
									.foregroundColor(.white.opacity(0.5))

								if let (currencyID, amount) = originalPrice {
									CurrencyLabel(amount: amount, currencyID: currencyID)
										.strikethrough(color: .white.opacity(0.45))
										.foregroundColor(.white.opacity(0.55))
								}
							}

							Spacer()

							VStack(alignment: .trailing, spacing: 2) {
								Text("Discounted price", comment: "Store: night market discounted price label")
									.font(.caption2.weight(.medium))
									.foregroundColor(valorantRed.opacity(0.8))

								if let (currencyID, amount) = discountedPrice {
									CurrencyLabel(amount: amount, currencyID: currencyID)
										.font(.system(size: 14, weight: .bold, design: .rounded))
										.foregroundColor(valorantRed)
								}
							}
						}
						.padding(.horizontal, 2)

						// MARK: Discount badge
					HStack {
						discountText
							.font(.caption.weight(.bold))
							.foregroundColor(.white)
						Spacer()
					}
					.padding(.horizontal, 10)
					.padding(.vertical, 5)
					.frame(minHeight: 28)
					.background(
						RoundedRectangle(cornerRadius: 7, style: .continuous)
							.fill(Color.purple)
					)
					.overlay(
						RoundedRectangle(cornerRadius: 7, style: .continuous)
							.stroke(Color.white.opacity(0.18), lineWidth: 1)
					)
				}
				.padding(14)
			}
			.background(cardColor)
			.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.stroke(Color.purple.opacity(0.35), lineWidth: 1)
			)
			.shadow(color: Color.purple.opacity(0.08), radius: 8, y: 4)
		}
	}

	func remainingTimeLabel(_ seconds: TimeInterval) -> some View {
		HStack(spacing: 4) {
			CountdownText(target: updateTime + seconds)
			
			Image(systemName: "clock")
		}
		.font(.caption.weight(.medium))
		.foregroundStyle(.secondary)
	}

	func accessoryStoreCell(offers: [Storefront.AccessoryStore.Offer]) -> some View {
		VStack(spacing: 12) {
			HStack {
				ForEach(offers, id: \.offer.id) { offer in
					icon(for: offer.offer.rewards.first!)
						.frame(width: 60, height: 60)
				}
			}
			
			Divider()
			
			HStack {
				Text("Accessories", comment: "Store: accessory section")
				
				Spacer()
				
				remainingTimeLabel(storefront.accessoryStore.remainingDuration)
				Image(systemName: "chevron.right")
					.foregroundStyle(.secondary)
			}
		}
		.font(.body.weight(.medium))
		.imageScale(.small)
		.padding(12)
	}

	@ViewBuilder
	func icon(for reward: StoreOffer.Reward) -> some View {
		switch reward.itemTypeID {
		case .buddies:
			(assets?.resolveBuddy(.init(rawID: reward.itemID))?.displayIcon).view()
		case .sprays:
			(assets?.sprays[.init(rawID: reward.itemID)]?.bestIcon).view()
		case .cards:
			(assets?.playerCards[.init(rawID: reward.itemID)]?.smallArt).view()
				.cornerRadius(8)
		case .titles:
			Image("Player Title")
				.resizable()
				.foregroundStyle(.secondary)
		default:
			EmptyView()
		}
	}
}

struct OfferCell: View {
	var offer: StoreOffer
	
	@Environment(\.assets) private var assets
	@Environment(\.colorScheme) private var colorScheme
	
	var body: some View {
		let reward = offer.rewards.first!
		let resolved = assets?.resolveSkin(.init(rawID: reward.itemID))
		let tier = resolved?.skin.contentTierID.flatMap { assets?.contentTiers[$0] }
		
		NavigationLink {
			if let resolved {
				SkinDetailsView(skin: resolved.skin)
			}
		} label: {
			VStack(spacing: 8) {
				let chroma = resolved?.skin.chromas.first
				(chroma?.fullRender ?? chroma?.displayIcon ?? resolved?.displayIcon)?.view()
					.aspectRatio(contentMode: .fit)
					.frame(height: 55)
				
				VStack(alignment: .leading, spacing: 4) {
					(resolved?.skin).label()
						.font(.system(size: 13, weight: .bold, design: .rounded))
						.foregroundColor(.white)
						.multilineTextAlignment(.leading)
						.lineLimit(2)
						.fixedSize(horizontal: false, vertical: true)
					
					HStack {
						if let tierIcon = tier?.displayIcon {
							tierIcon.view()
								.frame(width: 14, height: 14)
						}
						
						Spacer()
						
						CurrencyLabel.multiple(for: offer.cost)
							.font(.system(size: 12, weight: .semibold, design: .monospaced))
					}
				}
			}
			.padding(10)
		}
		.disabled(resolved == nil)
	}
}

struct AccessoryStoreView<Footer: View>: View {
	var accessoryStore: Storefront.AccessoryStore
	@ViewBuilder var footer: Footer
	@State var fullscreenImages: AssetImageCollection?
	
	@Environment(\.assets) private var assets
	
	var body: some View {
		List {
			Section {
				ForEach(accessoryStore.offers ?? [], id: \.offer.id, content: row(for:))
			} footer: {
				footer
			}
		}
		.navigationTitle(Text("Accessory Store", comment: "Store: Accessory List: title"))
		.lightbox(for: $fullscreenImages)
	}
	
	@ViewBuilder
	func row(for accessoryOffer: Storefront.AccessoryStore.Offer) -> some View {
		let offer = accessoryOffer.offer
		StoreItemView(item: offer.rewards.first!, fullscreenImages: $fullscreenImages) {
			let (currency, amount) = offer.cost.first!
			CurrencyLabel(amount: amount, currencyID: currency)
		}
	}
}

extension WeaponSkin? {
	func label() -> some View {
		UnwrappingView(
			value: self?.displayName,
			placeholder: Text("Unknown Skin", comment: "placeholder")
		)
	}
}

struct CurrencyLabel: View {
	var amount: Int
	var currencyID: Currency.ID
	
	@Environment(\.assets) private var assets
	@ScaledMetric(relativeTo: .body) private var iconSize = 20.0
	
	var body: some View {
		HStack(spacing: 4) {
			Text("\(amount)")
				.foregroundColor(.white)
			let currency = assets?.currencies[currencyID]
			currency?.displayIcon.view(renderingMode: .template)
				.frame(width: iconSize, height: iconSize)
				.foregroundColor(.white)
		}
	}
	
	static func multiple(for costs: [Currency.ID: Int]) -> some View {
		ForEach(costs.sorted(on: \.key.description), id: \.key) { currencyID, amount in
			CurrencyLabel(amount: amount, currencyID: currencyID)
				.layoutPriority(1)
		}
	}
}
