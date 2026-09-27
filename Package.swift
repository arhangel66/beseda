// swift-tools-version: 6.0

import PackageDescription
import Foundation

let store = ProcessInfo.processInfo.environment["BESEDA_STORE"] == "1"

let package = Package(
    name: "Beseda",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(name: "Beseda", targets: ["Beseda"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.4")
    ] + (store ? [] : [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ]),
    targets: [
        // transcribe.cpp's native library, pinned to the release the vendored wrapper was taken from
        .binaryTarget(
            name: "CTranscribe",
            url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.2.3/TranscribeCpp.xcframework.zip",
            checksum: "944be4d5232f39c99608f676a2ddda2516e0ed3c9fb6db50685ffa8d20a8b9c9"
        ),
        // the project's own Swift wrapper, vendored because it has no SwiftPM mirror yet
        .target(
            name: "TranscribeCpp",
            dependencies: ["CTranscribe"],
            path: "Vendor/TranscribeCpp",
            exclude: ["LICENSE"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit")
            ]
        ),
        .executableTarget(
            name: "Beseda",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "TranscribeCpp"
            ] + (store ? [] : [
                .product(name: "Sparkle", package: "Sparkle")
            ]),
            exclude: store ? ["Runtime/AppUpdater.swift"] : [],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: store ? [.define("BESEDA_STORE")] : [],
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("EventKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "BesedaTests",
            dependencies: ["Beseda"],
            swiftSettings: store ? [.define("BESEDA_STORE")] : []
        )
    ]
)
