// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarApps",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MenuBarApps", targets: ["MenuBarApps"])
    ],
    targets: [
        .executableTarget(
            name: "MenuBarApps",
            path: "Sources"
        )
    ]
)
