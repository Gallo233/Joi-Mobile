// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SyncClient",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "SyncClient", targets: ["SyncClient"])],
    dependencies: [.package(path: "../CompanionCore")],
    targets: [
        .target(name: "SyncClient", dependencies: ["CompanionCore"]),
        .testTarget(name: "SyncClientTests", dependencies: ["SyncClient", "CompanionCore"]),
    ],
    swiftLanguageModes: [.v6]
)
