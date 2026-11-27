// swift-tools-version: 5.9

import PackageDescription

let package = Package(
	name: "ReconBolt",
	defaultLocalization: "en",
	platforms: [
		.iOS(.v16),
	],
	products: [
		.library(
			name: "Recon_Bolt",
			targets: ["Recon_Bolt"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/TMaume/ValorantAPI-Revived.git", revision: "349c41562aa142be57717fd72af33360af283742"),
		.package(url: "https://github.com/juliand665/CGeometry.git", from: "0.4.0"),
		.package(url: "https://github.com/juliand665/HandyOperators.git", from: "2.1.0"),
		.package(url: "https://github.com/juliand665/UserDefault.git", from: "1.0.2"),
		.package(url: "https://github.com/juliand665/SwifUI-Missing-Pieces.git", revision: "b61ba8552b0ebc21e82efa7f92b24c533f0a3072"),
		.package(url: "https://github.com/apple/swift-algorithms.git", from: "1.0.0"),
	],
	targets: [
		.target(
			name: "Recon_Bolt",
			dependencies: [
				.product(name: "ValorantAPI", package: "ValorantAPI-Revived"),
				.product(name: "CGeometry", package: "CGeometry"),
				.product(name: "HandyOperators", package: "HandyOperators"),
				.product(name: "UserDefault", package: "UserDefault"),
				.product(name: "SwiftUIMissingPieces", package: "SwifUI-Missing-Pieces"),
				.product(name: "Algorithms", package: "swift-algorithms"),
			],
			path: "Shared",
			exclude: [
				"Assets.xcassets",
				"BundledIcons",
				"Preview Content/Preview Assets.xcassets",
				"Preview Content/Data",
				"Products.storekit",
			],
			resources: [
				.process("Strings"),
				.copy("BundledAssets"),
			],
			linkerSettings: [
				.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "ios", "-Xlinker", "16.0", "-Xlinker", "26.0"]),
			]
		),
	]
)
