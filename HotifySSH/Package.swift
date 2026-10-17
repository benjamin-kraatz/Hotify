// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "HotifySSH",
    platforms: [
        .macOS(.v26),
        .iOS(.v18),
    ],
    products: [
        .library(name: "HotifySSH", targets: ["HotifySSH"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", .upToNextMinor(from: "0.15.0")),
    ],
    targets: [
        .target(
            name: "HotifySSH",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        ),
        .testTarget(
            name: "HotifySSHTests",
            dependencies: ["HotifySSH"]
        ),
    ]
)
