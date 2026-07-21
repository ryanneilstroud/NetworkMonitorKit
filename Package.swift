// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PeriscopeKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PeriscopeKit", targets: ["PeriscopeKit"])
    ],
    targets: [
        .target(
            name: "PeriscopeKit",
            path: ".",
            exclude: ["Package.swift", "README.md", "PeriscopeKit.podspec", "LICENSE", "Tests"]
        ),
        .testTarget(
            name: "PeriscopeKitTests",
            dependencies: ["PeriscopeKit"],
            path: "Tests/PeriscopeKitTests"
        )
    ]
)
