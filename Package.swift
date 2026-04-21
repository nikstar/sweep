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
        )
    ]
)
