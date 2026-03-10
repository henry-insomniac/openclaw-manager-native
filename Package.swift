// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "openclaw-manager-native",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "OpenClawManagerNative",
            targets: ["OpenClawManagerNative"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenClawManagerNative",
            path: "Sources/OpenClawManagerNative",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)
