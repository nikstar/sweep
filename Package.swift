// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sweep",
    platforms: [
        .macOS(.v15),
        .iOS("26.0")
    ],
    products: [
        .library(name: "SweepCore", targets: ["SweepCore"]),
        .library(name: "SweepRQBitBridge", targets: ["SweepRQBitBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.6.1")
    ],
    targets: [
        .systemLibrary(
            name: "sweep_rqbitFFI",
            path: "Sources/SweepRustFFI"
        ),
        .target(
            name: "SweepCore",
            dependencies: [
                .product(name: "SQLiteData", package: "sqlite-data")
            ],
            path: "Sources/SweepCore"
        ),
        .target(
            name: "SweepRQBitBridge",
            dependencies: [
                "SweepCore",
                "sweep_rqbitFFI"
            ],
            path: "Sources/SweepRQBitBridge",
            sources: [
                "Generated/sweep_rqbit.swift",
                "RqbitEngine.swift"
            ]
        ),
        .testTarget(
            name: "SweepCoreTests",
            dependencies: ["SweepCore"],
            path: "Tests/SweepCoreTests"
        )
    ]
)
