// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DateKit",
    platforms: [
        // FormatStyle (used by `AppDates.dateString` / `dateTimeString`) needs iOS 16 / macOS 13.
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
        .tvOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "DateKit",
            targets: ["DateKit"]
        )
    ],
    targets: [
        .target(
            name: "DateKit",
            swiftSettings: [
                // Make the strict-concurrency contract self-documenting (and guard against a future
                // tools-version downgrade) rather than relying on the tools-version 6.0 default.
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DateKitTests",
            dependencies: ["DateKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
