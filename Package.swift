// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "ZincCore", targets: ["ZincCore"]),
]

var targets: [Target] = [
    .target(
        name: "ZincCore",
        path: "Sources/ZincCore"
    ),
    .testTarget(
        name: "ZincCoreTests",
        dependencies: ["ZincCore"],
        path: "Tests/ZincCoreTests"
    ),
]

#if os(macOS)
products.insert(.executable(name: "Zinc", targets: ["Zinc"]), at: 0)
targets.insert(
    .executableTarget(
        name: "Zinc",
        dependencies: ["ZincCore"],
        path: "Sources/Zinc"
    ),
    at: 1
)
#endif

let package = Package(
    name: "Zinc",
    platforms: [
        .macOS(.v14),
    ],
    products: products,
    targets: targets
)
