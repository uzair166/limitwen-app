// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Limitwen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Limitwen", targets: ["Limitwen"]),
        .executable(name: "LimitwenRelay", targets: ["LimitwenRelay"]),
        .executable(name: "LimitwenProbe", targets: ["LimitwenProbe"])
    ],
    targets: [
        .target(name: "LimitwenCore"),
        .executableTarget(name: "Limitwen", dependencies: ["LimitwenCore"]),
        .executableTarget(name: "LimitwenRelay", dependencies: ["LimitwenCore"]),
        .executableTarget(name: "LimitwenProbe", dependencies: ["LimitwenCore"]),
        .testTarget(name: "LimitwenCoreTests", dependencies: ["LimitwenCore"]),
        .testTarget(name: "LimitwenAppTests", dependencies: ["Limitwen"])
    ],
    swiftLanguageModes: [.v6]
)
