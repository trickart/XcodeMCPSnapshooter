// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XcodeMCPSnapshooter",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "xmsnap", targets: ["XcodeMCPSnapshooter"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "XcodeMCPSnapshooter",
            dependencies: [
                "Model",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(name: "Model"),
        .testTarget(
            name: "ModelTests",
            dependencies: ["Model"]
        ),
    ]
)
