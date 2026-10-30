// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GamepadKeymapper",
    products: [
        .library(name: "GamepadKeymapperCore", targets: ["GamepadKeymapperCore"])
    ],
    targets: [
        .target(
            name: "GamepadKeymapperCore",
            path: "Sources/GamepadKeymapperCore"
        ),
        .testTarget(
            name: "GamepadKeymapperCoreTests",
            dependencies: ["GamepadKeymapperCore"],
            path: "Tests/GamepadKeymapperCoreTests"
        )
    ]
)
