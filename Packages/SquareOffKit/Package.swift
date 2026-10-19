// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SquareOffKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SquareOffCore", targets: ["SquareOffCore"]),
        .library(name: "SquareOffNet", targets: ["SquareOffNet"]),
    ],
    targets: [
        // Pure game rules. Port of hero-client/src/modules (board-logic.ts, game-move-engine.ts, game-end-ranking.ts).
        .target(name: "SquareOffCore"),
        // REST contract with the FastAPI server, mirroring hero-client/src/services/*.ts.
        .target(name: "SquareOffNet", dependencies: ["SquareOffCore"]),
        .testTarget(name: "SquareOffCoreTests", dependencies: ["SquareOffCore"]),
        .testTarget(
            name: "SquareOffNetTests",
            dependencies: ["SquareOffNet"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
