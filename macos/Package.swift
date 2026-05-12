// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Claudario",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Claudario",
            path: "Sources/Claudario"
        )
    ]
)
