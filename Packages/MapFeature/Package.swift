// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MapFeature",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "MapFeature", targets: ["MapFeature"])],
    dependencies: [
        .package(path: "../CompanionCore"),
        .package(path: "../OfflinePack"),
    ],
    targets: [
        .target(name: "MapFeature", dependencies: ["CompanionCore", "OfflinePack"]),
        .testTarget(name: "MapFeatureTests", dependencies: ["MapFeature", "CompanionCore"]),
    ],
    swiftLanguageModes: [.v6]
)
