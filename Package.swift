// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "justasec",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/Jud/kokoro-coreml.git", exact: "0.11.2")
    ],
    targets: [
        .executableTarget(
            name: "justasec",
            dependencies: [
                .product(name: "KokoroCoreML", package: "kokoro-coreml")
            ]
        ),
        .testTarget(
            name: "justasecTests",
            dependencies: ["justasec"]
        )
    ]
)
