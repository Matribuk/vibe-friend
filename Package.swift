// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeFriend",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VibeFriend",
            path: "Sources/VibeFriend",
            resources: [.process("Resources")]
        )
    ]
)
