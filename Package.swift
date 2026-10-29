// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockMinimize",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DockMinimize", path: "Sources")
    ]
)
