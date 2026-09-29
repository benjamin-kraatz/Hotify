// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "CoolifyAPI",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "CoolifyAPI", targets: ["CoolifyAPI"]),
    ],
    targets: [
        .target(
            name: "CoolifyAPI",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "CoolifyAPITests",
            dependencies: ["CoolifyAPI"]
        ),
    ]
)
