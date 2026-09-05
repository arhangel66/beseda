// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Podushka",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Podushka", targets: ["Podushka"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
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
            name: "Podushka",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
                "TranscribeCpp"
            ],
            path: ".",
            exclude: [
                ".agents",
                ".gitignore",
                ".idea",
                ".venv",
                "AGENT.md",
                "dist",
                "MVP_PHASE_PLAN.md",
                "README.md",
                "Tests",
                "VERSION",
                "Vendor",
                "docs",
                "implementation_journal.md",
                "samples",
                "scripts",
                "skills-lock.json",
                "spikes",
                "untracked"
            ],
            sources: [
                "App",
                "Audio",
                "Calendar",
                "Storage",
                "Summarization",
                "Transcription",
                "Webhooks",
                "Runtime"
            ],
            resources: [
                .copy("Resources")
            ],
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
            name: "PodushkaTests",
            dependencies: ["Podushka"],
            path: "Tests/PodushkaTests"
        )
    ]
)
