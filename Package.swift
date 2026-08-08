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
        .library(name: "ZincLib", targets: ["ZincLib"]),
    ],
    targets: [
        .target(
            name: "ZincCore",
            path: "Sources/ZincCore"
        ),
        .target(
            name: "ZincLib",
            dependencies: ["ZincCore"],
            path: "Sources/Zinc"
        ),
        .executableTarget(
            name: "Zinc",
            dependencies: ["ZincLib"],
            path: "Sources/ZincApp"
        ),
        .testTarget(
            name: "ZincCoreTests",
            dependencies: ["ZincCore", "ZincLib"],
            path: "Tests/ZincCoreTests"
        ),
    ]
)
