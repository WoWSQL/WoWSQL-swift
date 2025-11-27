// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WOWSQL",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6),
        .tvOS(.v13)
    ],
    products: [
        .library(
            name: "WOWSQL",
            targets: ["WOWSQL"]
        ),
    ],
    dependencies: [
        // No external dependencies - using Foundation and URLSession
    ],
    targets: [
        .target(
            name: "WOWSQL",
            dependencies: [],
            path: "Sources/WOWSQL"
        ),
        .testTarget(
            name: "WOWSQLTests",
            dependencies: ["WOWSQL"],
            path: "Tests/WOWSQLTests"
        ),
    ]
)

