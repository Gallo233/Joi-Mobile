// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CharacterRuntime",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "CharacterRuntime", targets: ["CharacterRuntime"])],
    dependencies: [
        .package(path: "../CompanionCore"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(
            name: "CharacterRuntime",
            dependencies: [
                "CompanionCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(
            name: "CharacterRuntimeTests",
            dependencies: [
                "CharacterRuntime",
                "CompanionCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
