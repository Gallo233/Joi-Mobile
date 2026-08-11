// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CharacterRuntime",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "CharacterRuntime", targets: ["CharacterRuntime"])],
    dependencies: [.package(path: "../CompanionCore")],
    targets: [
        .target(name: "CharacterRuntime", dependencies: ["CompanionCore"]),
        .testTarget(name: "CharacterRuntimeTests", dependencies: ["CharacterRuntime", "CompanionCore"]),
    ],
    swiftLanguageModes: [.v6]
)
