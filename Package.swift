// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WOWSQL",
    version: "1.4.0",
    license: {
        name: "MIT",
        text: "Copyright (c) 2025 WowSQL"
    },
    authors: [
        { name: "WowSQL Team", email: "support@wowsql.com" }
    ],
    homepage: "https://wowsql.com",
    documentation: "https://wowsql.com/docs",
    issueTracker: "https://github.com/wowsql/wowsql/issues",
    swiftLanguageVersions: [.v5],
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

