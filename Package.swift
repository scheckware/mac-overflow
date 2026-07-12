// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOverflow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacOverflow",
            targets: ["MacOverflow"]
        )
    ],
    dependencies: [],
    targets: [
        // Thin executable: app lifecycle + UI only.
        .executableTarget(
            name: "MacOverflow",
            dependencies: ["MacOverflowCore"],
            path: "Sources/MacOverflow"
        ),
        // Testable library: models, monitoring, and pure geometry.
        .target(
            name: "MacOverflowCore",
            path: "Sources/MacOverflowCore"
        ),
        .testTarget(
            name: "MacOverflowTests",
            dependencies: ["MacOverflowCore"],
            path: "Tests"
        )
    ]
)
