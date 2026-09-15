// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TGLogger",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "TGLogger",
            targets: ["TGLogger"]
        ),
    ],
    targets: [
        .target(
            name: "TGLogger"
        ),
        .testTarget(
            name: "TGLoggerTests",
            dependencies: ["TGLogger"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
