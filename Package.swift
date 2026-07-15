// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Governor",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "GovernorCore", targets: ["GovernorCore"]),
        .executable(name: "Governor", targets: ["Governor"]),
    ],
    targets: [
        .target(
            name: "GovernorCore",
            path: "Sources/GovernorCore"
        ),
        .executableTarget(
            name: "Governor",
            dependencies: ["GovernorCore"],
            path: "Sources/Governor"
        ),
        .testTarget(
            name: "GovernorCoreTests",
            dependencies: ["GovernorCore"],
            path: "Tests/GovernorCoreTests"
        ),
        .testTarget(
            name: "GovernorServiceTests",
            dependencies: ["Governor"],
            path: "Tests/GovernorServiceTests"
        ),
    ]
)
