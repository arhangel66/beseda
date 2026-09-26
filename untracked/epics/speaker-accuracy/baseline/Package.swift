// swift-tools-version: 6.0

import PackageDescription

// Runs Beseda's speaker and ASR pipeline on the speaker-accuracy eval set. The app target is an
// executable, so it cannot be imported: Sources/Baseline/AppCopy holds its files copied verbatim.
let package = Package(
    name: "Baseline",
    platforms: [.macOS(.v14)],
    dependencies: [
        // same revision as the app's Package.resolved
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.6")
    ],
    targets: [
        .binaryTarget(
            name: "CTranscribe",
            url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.2.3/TranscribeCpp.xcframework.zip",
            checksum: "944be4d5232f39c99608f676a2ddda2516e0ed3c9fb6db50685ffa8d20a8b9c9"
        ),
        // symlink to the app's Vendor/TranscribeCpp
        .target(
            name: "TranscribeCpp",
            dependencies: ["CTranscribe"],
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
            name: "Baseline",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "TranscribeCpp"
            ]
        ),
        // speaker counts on Mikhail's archived calls, old vs new assignment (../real_calls.sh)
        .executableTarget(
            name: "RealCalls",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        )
    ]
)
