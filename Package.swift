// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ghostlight",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CLibGhostty",
            path: "Sources/CLibGhostty",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Ghostlight",
            dependencies: ["CLibGhostty"],
            path: "Sources/Ghostlight"
        ),
    ]
)
