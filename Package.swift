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
            name: "NotchPilotKit"
        ),
        .testTarget(
            name: "NotchPilotKitTests",
            dependencies: ["NotchPilotKit"]
        ),
    ]
)
