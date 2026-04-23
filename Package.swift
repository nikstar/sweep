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
        .library(name: "SweepRQBitBridge", targets: ["SweepRQBitBridge"]),
        .executable(name: "Sweep", targets: ["Sweep"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.6.1")
    ],
    targets: [
        .target(
            name: "SweepCore",
            dependencies: [
                .product(name: "SQLiteData", package: "sqlite-data")
            ],
            path: "Sources/SweepCore"
        ),
        .target(
            name: "SweepRQBitBridge",
            dependencies: ["SweepCore"],
            path: "Sources/SweepRQBitBridge",
            swiftSettings: [
                .unsafeFlags([
                    "-I", "Sources/SweepRQBitBridge/Generated",
                    "-Xcc", "-fmodule-map-file=Sources/SweepRQBitBridge/Generated/module.modulemap"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "rust/target/debug",
                    "-lsweep_rqbit",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../../../rust/target/debug"
                ])
            ]
        ),
        .executableTarget(
            name: "Sweep",
            dependencies: ["SweepCore", "SweepRQBitBridge"],
            path: "Sources/SweepMac",
            exclude: ["Resources"],
            swiftSettings: [
                .unsafeFlags([
                    "-I", "Sources/SweepRQBitBridge/Generated",
                    "-Xcc", "-fmodule-map-file=Sources/SweepRQBitBridge/Generated/module.modulemap"
                ])
            ]
        ),
        .testTarget(
            name: "SweepCoreTests",
            dependencies: ["SweepCore"],
            path: "Tests/SweepCoreTests"
        )
    ]
)
