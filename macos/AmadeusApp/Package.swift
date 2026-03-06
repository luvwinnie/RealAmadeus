// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AmadeusApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AmadeusApp",
            path: "AmadeusApp",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "AmadeusAppTests",
            dependencies: ["AmadeusApp"],
            path: "AmadeusAppTests"
        ),
    ]
)
