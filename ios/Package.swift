// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MosaicMemories",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MosaicCore", targets: ["MosaicCore"]),
        .library(name: "MosaicPersistence", targets: ["MosaicPersistence"]),
        .library(name: "MosaicPrivacy", targets: ["MosaicPrivacy"]),
        .library(name: "MosaicFeatures", targets: ["MosaicFeatures"]),
    ],
    targets: [
        .target(name: "MosaicCore"),
        .target(name: "MosaicPersistence", dependencies: ["MosaicCore"]),
        .target(name: "MosaicPrivacy", dependencies: ["MosaicCore"]),
        .target(name: "MosaicFeatures", dependencies: ["MosaicCore"]),
        .testTarget(name: "MosaicCoreTests", dependencies: ["MosaicCore"]),
        .testTarget(name: "MosaicPersistenceTests", dependencies: ["MosaicCore", "MosaicPersistence"]),
        .testTarget(name: "MosaicPrivacyTests", dependencies: ["MosaicCore", "MosaicPrivacy"]),
        .testTarget(name: "MosaicFeaturesTests", dependencies: ["MosaicCore", "MosaicFeatures"]),
    ]
)

