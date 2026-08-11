// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChatFeature",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "ChatFeature", targets: ["ChatFeature"])],
    dependencies: [.package(path: "../CompanionCore")],
    targets: [
        .target(name: "ChatFeature", dependencies: ["CompanionCore"]),
        .testTarget(name: "ChatFeatureTests", dependencies: ["ChatFeature", "CompanionCore"]),
    ],
    swiftLanguageModes: [.v6]
)
