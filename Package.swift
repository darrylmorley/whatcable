// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Pro features live in a private submodule at app/. The submodule is always
// present in release builds; open-source contributors can build the CLI and
// free app without it.
//
// Set WHATCABLE_PRO=1 in your environment (loaded from .env by build scripts)
// to include the pro module. Pro features are then gated at RUNTIME by a
// licence key, not at compile time. The define just controls whether the pro
// code is linked into the binary.
let includePro = ProcessInfo.processInfo.environment["WHATCABLE_PRO"] == "1"

var appSwiftSettings: [SwiftSetting] = []
var appDependencies: [Target.Dependency] = ["WhatCableCore", "WhatCableDarwinBackend"]
var cliSwiftSettings: [SwiftSetting] = []
var cliDependencies: [Target.Dependency] = ["WhatCableCore", "WhatCableDarwinBackend"]

if includePro {
    appDependencies.append("WhatCableProFeatures")
    appSwiftSettings.append(.define("WHATCABLE_PRO"))
    cliDependencies.append("WhatCableProFeatures")
    cliSwiftSettings.append(.define("WHATCABLE_PRO"))
}

var targets: [Target] = [
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
        name: "WhatCableCLI",
        dependencies: cliDependencies,
        path: "Sources/WhatCableCLI",
        swiftSettings: cliSwiftSettings.isEmpty ? nil : cliSwiftSettings
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

if includePro {
    targets.append(
        .target(
            name: "WhatCableProFeatures",
            dependencies: ["WhatCableCore", "WhatCableDarwinBackend"],
            path: "app/Sources/WhatCableProFeatures"
        )
    )
    targets.append(
        .testTarget(
            name: "WhatCableProFeaturesTests",
            dependencies: ["WhatCableProFeatures"],
            path: "app/Tests/WhatCableProFeaturesTests"
        )
    )
}

targets.append(
    .executableTarget(
        name: "WhatCable",
        dependencies: appDependencies,
        path: "Sources/WhatCable",
        resources: [.process("Resources")],
        swiftSettings: appSwiftSettings.isEmpty ? nil : appSwiftSettings
    )
)

let package = Package(
    name: "WhatCable",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhatCable", targets: ["WhatCable"]),
        .executable(name: "whatcable-cli", targets: ["WhatCableCLI"]),
        .library(name: "WhatCableCore", targets: ["WhatCableCore"])
    ],
    targets: targets
)
