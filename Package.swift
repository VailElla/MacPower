// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Governor",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "GovernorCore", targets: ["GovernorCore"]),
        .library(name: "GovernorHelperSupport", targets: ["GovernorHelperSupport"]),
        .executable(name: "Governor", targets: ["Governor"]),
        .executable(name: "GovernorPowerHelper", targets: ["GovernorPowerHelper"]),
    ],
    targets: [
        .target(
            name: "GovernorCore",
            path: "Sources/GovernorCore"
        ),
        .target(
            name: "GovernorHelperSupport",
            path: "Sources/GovernorHelperSupport"
        ),
        .executableTarget(
            name: "Governor",
            dependencies: ["GovernorCore", "GovernorHelperSupport"],
            path: "Sources/Governor",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "GovernorPowerHelper",
            dependencies: ["GovernorHelperSupport"],
            path: "Sources/GovernorPowerHelper"
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
        .testTarget(
            name: "GovernorHelperSupportTests",
            dependencies: ["GovernorHelperSupport"],
            path: "Tests/GovernorHelperSupportTests"
        ),
    ]
)
