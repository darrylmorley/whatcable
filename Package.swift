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
            path: "Sources/WhatCableCore"
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
            dependencies: [
                "WhatCableCore",
                .target(name: "WhatCableDarwinBackend", condition: .when(platforms: [.macOS]))
            ],
            path: "Sources/WhatCableCLI"
        ),
        .testTarget(
            name: "WhatCableTests",
            dependencies: [
                "WhatCable",
                "WhatCableCore",
                "WhatCableCLI",
                .target(name: "WhatCableDarwinBackend", condition: .when(platforms: [.macOS]))
            ],
            path: "Tests/WhatCableTests"
        )
    ]
)
