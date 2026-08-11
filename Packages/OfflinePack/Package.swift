// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OfflinePack",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "OfflinePack", targets: ["OfflinePack"])],
    dependencies: [.package(path: "../CompanionCore")],
    targets: [
        .target(name: "OfflinePack", dependencies: ["CompanionCore"]),
        .testTarget(name: "OfflinePackTests", dependencies: ["OfflinePack", "CompanionCore"]),
    ],
    swiftLanguageModes: [.v6]
)
