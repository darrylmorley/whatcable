// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Plugin target path: if the submodule provides Sources/WhatCablePlugins,
// compile from there. Otherwise compile the no-op stub in the public repo.
let pluginPath = FileManager.default.fileExists(
    atPath: "app/Sources/WhatCablePlugins"
) ? "app/Sources/WhatCablePlugins" : "Sources/WhatCablePlugins"

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
    .target(
        name: "WhatCableAppKit",
        dependencies: ["WhatCableCore"],
        path: "Sources/WhatCableAppKit"
    ),
    .target(
        name: "WhatCablePlugins",
        dependencies: ["WhatCableCore", "WhatCableDarwinBackend", "WhatCableAppKit"],
        path: pluginPath
    ),
    .executableTarget(
        name: "WhatCable",
        dependencies: ["WhatCableCore", "WhatCableDarwinBackend", "WhatCableAppKit", "WhatCablePlugins"],
        path: "Sources/WhatCable",
        resources: [.process("Resources")]
    ),
    .executableTarget(
        name: "WhatCableCLI",
        dependencies: ["WhatCableCore", "WhatCableDarwinBackend", "WhatCableAppKit", "WhatCablePlugins"],
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

if FileManager.default.fileExists(atPath: "app/Tests/WhatCablePluginsTests") {
    targets.append(
        .testTarget(
            name: "WhatCablePluginsTests",
            dependencies: ["WhatCablePlugins"],
            path: "app/Tests/WhatCablePluginsTests"
        )
    )
}

let package = Package(
    name: "WhatCable",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhatCable", targets: ["WhatCable"]),
        .executable(name: "whatcable-cli", targets: ["WhatCableCLI"]),
        .library(name: "WhatCableCore", targets: ["WhatCableCore"]),
        .library(name: "WhatCableAppKit", targets: ["WhatCableAppKit"])
    ],
    targets: targets
)
