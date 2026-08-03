// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Zinc",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Zinc",
            path: "Sources/Zinc"
        ),
    ]
)
