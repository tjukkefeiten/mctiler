// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "McTiler",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "McTilerAgent", targets: ["McTiler"]),
        .executable(name: "mctiler", targets: ["McTilerCLI"])
    ],
    targets: [
        .target(name: "TilerCore"),
        .target(name: "TilerIPC", dependencies: ["TilerCore"]),
        .target(name: "MacAdapter", dependencies: ["TilerCore"]),
        .executableTarget(name: "McTiler", dependencies: ["TilerCore", "TilerIPC", "MacAdapter"]),
        .executableTarget(name: "McTilerCLI", dependencies: ["TilerCore", "TilerIPC", "MacAdapter"]),
        .testTarget(name: "TilerCoreTests", dependencies: ["TilerCore", "TilerIPC", "MacAdapter"])
    ],
    swiftLanguageModes: [.v5]
)
