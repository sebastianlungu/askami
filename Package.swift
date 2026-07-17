// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "justasec",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "justasec"
        ),
        .testTarget(
            name: "justasecTests",
            dependencies: ["justasec"]
        )
    ]
)
