// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Zinc",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ZincCore", targets: ["ZincCore"]),
    ],
    targets: [
        .target(
            name: "ZincCore",
            path: "Sources/ZincCore"
        ),
        .executableTarget(
            name: "Zinc",
            dependencies: ["ZincCore"],
            path: "Sources/Zinc"
        ),
    ]
)
