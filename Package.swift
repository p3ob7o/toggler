// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Toggler",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Toggler", targets: ["Toggler"])
    ],
    targets: [
        .executableTarget(
            name: "Toggler",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "TogglerTests",
            dependencies: ["Toggler"]
        )
    ]
)
