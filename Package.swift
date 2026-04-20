// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "NotchPilot",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "NotchPilotKit",
            targets: ["NotchPilotKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/MxIris-LyricsX-Project/LyricsKit.git",
            revision: "9e52e0986b89df6d8815c823fac23b6a775c3b49"
        ),
    ],
    targets: [
        .target(
            name: "NotchPilotKit",
            dependencies: [
                .product(name: "LyricsKit", package: "LyricsKit"),
            ],
            resources: [
                .copy("Resources/notch-bridge.py"),
                .copy("Resources/MediaRemoteAdapter"),
                .process("Resources/Icons"),
            ]
        ),
        .testTarget(
            name: "NotchPilotKitTests",
            dependencies: [
                "NotchPilotKit",
                .product(name: "LyricsKit", package: "LyricsKit"),
            ]
        ),
    ]
)
