// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptureSpike",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CaptureSpike",
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio")
            ]
        )
    ]
)

