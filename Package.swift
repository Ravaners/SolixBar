// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SolixBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SolixBar", targets: ["SolixBar"])
    ],
    targets: [
        .target(
            name: "SolixBarKit",
            path: "Sources/SolixBarKit"
        ),
        .executableTarget(
            name: "SolixBar",
            dependencies: ["SolixBarKit"],
            path: "Sources/SolixBar"
        ),
        .testTarget(
            name: "SolixBarTests",
            dependencies: ["SolixBarKit"],
            path: "Tests/SolixBarTests"
        )
    ]
)
