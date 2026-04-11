// swift-tools-version: 6.2
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
    targets: [
        .target(
            name: "NotchPilotKit",
            resources: [
                .copy("Resources/notch-bridge.py"),
                .process("Resources/Icons"),
            ]
        ),
        .testTarget(
            name: "NotchPilotKitTests",
            dependencies: ["NotchPilotKit"]
        ),
    ]
)
