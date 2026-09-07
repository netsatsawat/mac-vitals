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
        .target(name: "VitalsCore"),
        .executableTarget(
            name: "vitals",
            dependencies: ["VitalsCore"]
        ),
        .executableTarget(
            name: "MacVitals",
            dependencies: ["VitalsCore"]
        ),
        .testTarget(
            name: "VitalsCoreTests",
            dependencies: ["VitalsCore"]
        ),
    ]
)
