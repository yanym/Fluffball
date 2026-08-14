// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Furball2D",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Furball2D", targets: ["Furball2D"])
    ],
    targets: [
        .executableTarget(
            name: "Furball2D",
            resources: [.copy("Assets")],
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
