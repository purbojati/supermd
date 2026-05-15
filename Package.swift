// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperMD",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "SuperMD",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/SuperMD"
        )
    ]
)
