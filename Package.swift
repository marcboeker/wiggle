// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "wiggle",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0")
    ],
    targets: [
        .target(name: "WiggleKit", dependencies: ["KeyboardShortcuts"], path: "Sources/WiggleKit"),
        .executableTarget(name: "wiggle", dependencies: ["WiggleKit"], path: "Sources/wiggle"),
        .testTarget(name: "WiggleKitTests", dependencies: ["WiggleKit"], path: "Tests/WiggleKitTests"),
    ]
)
