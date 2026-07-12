// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SolixBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SolixBar", targets: ["SolixBar"]),
        .executable(name: "SolixBarCoreChecks", targets: ["SolixBarCoreChecks"])
    ],
    targets: [
        .target(
            name: "SolixBarCore",
            path: "Sources/SolixBarCore"
        ),
        .executableTarget(
            name: "SolixBar",
            dependencies: ["SolixBarCore"],
            path: "Sources/SolixBar"
        ),
        .executableTarget(
            name: "SolixBarCoreChecks",
            dependencies: ["SolixBarCore"],
            path: "Sources/SolixBarCoreChecks"
        )
    ]
)
