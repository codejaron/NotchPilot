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
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts.git",
            from: "2.4.0"
        ),
    ],
    targets: [
        .target(
            name: "NotchPilotKit",
            dependencies: [
                .product(name: "LyricsKit", package: "lyricskit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            resources: [
                .copy("Resources/notch-bridge.py"),
                .copy("Resources/MediaRemoteAdapter"),
                .copy("Resources/Sounds"),
                .process("Resources/Icons"),
            ]
        ),
        .testTarget(
            name: "NotchPilotKitTests",
            dependencies: [
                "NotchPilotKit",
                .product(name: "LyricsKit", package: "lyricskit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
    ]
)
