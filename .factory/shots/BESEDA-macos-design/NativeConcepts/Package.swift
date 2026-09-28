// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeConcepts",
    platforms: [.macOS("14.2")],
    products: [.library(name: "NativeConcepts", targets: ["NativeConcepts"])],
    targets: [.target(name: "NativeConcepts")]
)
