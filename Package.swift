// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NetworkMonitorKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetworkMonitorKit", targets: ["NetworkMonitorKit"])
    ],
    targets: [
        .target(
            name: "NetworkMonitorKit",
            path: ".",
            exclude: ["Package.swift", "README.md"]
        )
    ]
)
