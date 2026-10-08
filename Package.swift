// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VeggieLoops",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VLStudio", targets: ["VLStudio"]),
        .executable(name: "VLSmoke", targets: ["VLSmoke"])
    ],
    targets: [
        .target(name: "VLCore"),
        .target(name: "VLDSP", dependencies: ["VLCore"]),
        .target(name: "VLNativeDSP", cxxSettings: [.unsafeFlags([
            "-ffp-contract=off", "-fno-fast-math", "-fno-builtin-sin",
            "-fno-builtin-cos", "-fno-builtin-exp"
        ])]),
        .target(name: "VLAudio", dependencies: ["VLCore", "VLDSP", "VLNativeDSP"]),
        .executableTarget(name: "VLStudio", dependencies: ["VLCore", "VLAudio"]),
        .executableTarget(name: "VLSmoke", dependencies: ["VLCore", "VLAudio"]),
        .testTarget(name: "VLCoreTests", dependencies: ["VLCore"]),
        .testTarget(name: "VLDSPTests", dependencies: ["VLCore", "VLDSP"]),
        .testTarget(name: "VLAudioTests", dependencies: ["VLCore", "VLAudio"])
    ],
    swiftLanguageVersions: [.v5],
    cxxLanguageStandard: .cxx20
)
