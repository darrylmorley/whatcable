// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Mac App Store build flag. When `WHATCABLE_MAS=1` is in the environment at
// build time, the WhatCable executable target is compiled with the
// `WHATCABLE_MAS` Swift define. That gates out the self-hosted update path
// (App Review forbids self-updaters) so the same source tree produces both
// the OSS GitHub/Homebrew build and the App Store build.
//
// The flag is intentionally only consulted by Package.swift (and a small
// set of source files marked in CLAUDE.md). If you find yourself wanting
// to read it elsewhere, reread the discipline rule first.
let isMASBuild = ProcessInfo.processInfo.environment["WHATCABLE_MAS"] == "1"
let appSwiftSettings: [SwiftSetting] = isMASBuild ? [.define("WHATCABLE_MAS")] : []

let package = Package(
    name: "WhatCable",
    platforms: [.macOS(.v14)],
    products: [
        // Explicit executable product so the binary name (whatcable-cli)
        // can differ from the Swift module name (WhatCableCLI). The
        // module name needs to be a valid Swift identifier so it can be
        // imported by tests.
        .executable(name: "WhatCable", targets: ["WhatCable"]),
        .executable(name: "whatcable-cli", targets: ["WhatCableCLI"])
    ],
    targets: [
        .target(
            name: "WhatCableCore",
            path: "Sources/WhatCableCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "WhatCableDarwinBackend",
            dependencies: ["WhatCableCore"],
            path: "Sources/WhatCableDarwinBackend"
        ),
        .executableTarget(
            name: "WhatCable",
            dependencies: ["WhatCableCore", "WhatCableDarwinBackend"],
            path: "Sources/WhatCable",
            swiftSettings: appSwiftSettings
        ),
        .executableTarget(
            name: "WhatCableCLI",
            dependencies: ["WhatCableCore", "WhatCableDarwinBackend"],
            path: "Sources/WhatCableCLI"
        ),
        .testTarget(
            name: "WhatCableCoreTests",
            dependencies: ["WhatCableCore"],
            path: "Tests/WhatCableCoreTests"
        ),
        .testTarget(
            name: "WhatCableDarwinTests",
            dependencies: ["WhatCableCore", "WhatCable", "WhatCableDarwinBackend"],
            path: "Tests/WhatCableDarwinTests"
        )
    ]
)
