// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceZ",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        // Umbrella product: capture + rules + overlay + remote inspector.
        .library(name: "SpaceZ", targets: ["SpaceZ"]),
        // Core-only product for hosts that ship a custom UI or transport.
        .library(name: "SpaceZCore", targets: ["SpaceZCore"]),
    ],
    targets: [
        .target(
            name: "SpaceZCore"
        ),
        .target(
            name: "SpaceZUIKit",
            dependencies: ["SpaceZCore"]
        ),
        .target(
            name: "SpaceZSwiftUI",
            dependencies: ["SpaceZCore", "SpaceZUIKit"]
        ),
        .target(
            name: "SpaceZRules",
            dependencies: ["SpaceZCore"]
        ),
        .target(
            name: "SpaceZRemote",
            dependencies: ["SpaceZCore", "SpaceZRules"],
            resources: [
                .copy("Resources/inspector.html"),
            ]
        ),
        .target(
            name: "SpaceZOverlay",
            dependencies: ["SpaceZCore", "SpaceZUIKit", "SpaceZRules"]
        ),
        .target(
            name: "SpaceZ",
            dependencies: [
                "SpaceZCore",
                "SpaceZUIKit",
                "SpaceZSwiftUI",
                "SpaceZRules",
                "SpaceZRemote",
                "SpaceZOverlay",
            ]
        ),
        .testTarget(
            name: "SpaceZCoreTests",
            dependencies: ["SpaceZCore", "SpaceZUIKit"]
        ),
        .testTarget(
            name: "SpaceZRulesTests",
            dependencies: ["SpaceZRules"]
        ),
        .testTarget(
            name: "SpaceZRemoteTests",
            dependencies: ["SpaceZRemote"]
        ),
    ]
)
