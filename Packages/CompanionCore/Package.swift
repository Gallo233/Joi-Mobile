// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CompanionCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "CompanionCore", targets: ["CompanionCore"])],
    targets: [
        .target(name: "CompanionCore"),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
    ],
    swiftLanguageModes: [.v6]
)
