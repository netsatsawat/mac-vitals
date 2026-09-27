// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-vitals",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VitalsCore", targets: ["VitalsCore"]),
        .executable(name: "vitals", targets: ["vitals"]),
        .executable(name: "MacVitals", targets: ["MacVitals"]),
    ],
    targets: [
        .target(name: "CSMC"),
        .target(name: "VitalsCore", dependencies: ["CSMC"]),
        .executableTarget(
            name: "vitals",
            dependencies: ["VitalsCore"]
        ),
        .executableTarget(
            name: "MacVitals",
            dependencies: ["VitalsCore"],
            // Companion character packs (folders of PNG/GIF/config.json). SwiftPM
            // emits them as mac-vitals_MacVitals.bundle beside the binary, and
            // scripts/build-app.sh copies that bundle into Contents/Resources.
            resources: [.copy("Resources/Companion")]
        ),
        .testTarget(
            name: "VitalsCoreTests",
            dependencies: ["VitalsCore"]
        ),
    ]
)
