// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KimiStatusbar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "kimi-statusbar", targets: ["KimiStatusbar"])
    ],
    targets: [
        .executableTarget(
            name: "KimiStatusbar",
            path: "Sources/KimiStatusbar"
        )
    ]
)
