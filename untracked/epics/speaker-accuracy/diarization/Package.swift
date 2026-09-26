// swift-tools-version: 6.0

import PackageDescription

// Runs FluidAudio's diarizers (offline pyannote/VBx, Sortformer, LS-EEND) on the system channel of the
// speaker-accuracy eval set. Newer than the app's 0.15.6 on purpose: Sortformer and LS-EEND need it.
let package = Package(
    name: "Diarize",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4")
    ],
    targets: [
        .executableTarget(name: "Diarize", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])
    ]
)
