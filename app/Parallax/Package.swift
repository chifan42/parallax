// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Parallax",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Parallax", targets: ["Parallax"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Parallax",
            dependencies: [],
            path: ".",
            exclude: ["Package.swift"],
            resources: []
        ),
    ]
)
