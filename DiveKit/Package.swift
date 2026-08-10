// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiveKit",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "DiveKit", targets: ["DiveKit"])
    ],
    targets: [
        .target(name: "DiveKit"),
        // Command Line Tools (no Xcode) ships neither swift-testing nor XCTest,
        // so tests run as a plain executable: `swift run divekit-tests`.
        .executableTarget(
            name: "divekit-tests",
            dependencies: ["DiveKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
