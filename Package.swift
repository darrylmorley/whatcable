// swift-tools-version: 5.9
import PackageDescription

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
            path: "Sources/WhatCable"
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
