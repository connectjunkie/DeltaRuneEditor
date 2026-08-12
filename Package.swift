// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DeltaruneCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DeltaruneCore", targets: ["DeltaruneCore"]),
        .executable(name: "DeltaruneEditor", targets: ["DeltaruneEditor"]),
    ],
    targets: [
        .target(
            name: "DeltaruneCore",
            resources: [.copy("Resources/gamedata.json")]
        ),
        .executableTarget(
            name: "DeltaruneEditor",
            dependencies: ["DeltaruneCore"]
        ),
        .testTarget(
            name: "DeltaruneCoreTests",
            dependencies: ["DeltaruneCore"],
            // .copy preserves the fixture bytes verbatim. Never use .process here:
            // the whole suite is meaningless if the CRLF line endings get rewritten.
            resources: [.copy("Fixtures")]
        ),
    ]
)
