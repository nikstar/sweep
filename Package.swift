// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sweep",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SweepCore", targets: ["SweepCore"]),
        .library(name: "SweepRQBitBridge", targets: ["SweepRQBitBridge"]),
        .executable(name: "Sweep", targets: ["Sweep"])
    ],
    targets: [
        .target(
            name: "SweepCore",
            path: "Sources/SweepCore"
        ),
        .target(
            name: "SweepRQBitBridge",
            dependencies: ["SweepCore"],
            path: "Sources/SweepRQBitBridge"
        ),
        .executableTarget(
            name: "Sweep",
            dependencies: ["SweepCore", "SweepRQBitBridge"],
            path: "Sources/SweepMac",
            exclude: ["Resources"]
        )
    ]
)
