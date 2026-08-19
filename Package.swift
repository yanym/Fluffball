// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Furball",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Furball", targets: ["Furball"])
    ],
    targets: [
        .executableTarget(
            name: "Furball",
            path: "Sources/Furball2D",
            resources: [
                .copy("Assets"),
                .copy("CreatorSkill")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
