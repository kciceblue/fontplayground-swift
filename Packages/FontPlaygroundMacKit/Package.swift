// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FontPlaygroundMacKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "fpmac-harness", targets: ["FPMacHarness"]),
        .library(name: "FPMacServices", targets: ["FPMacServices"]),
        .library(name: "FPAppUI", targets: ["FPAppUI"]),
    ],
    dependencies: [.package(path: "../FontPlaygroundKit")],
    targets: [
        .target(
            name: "FPMacServices",
            dependencies: [
                .product(name: "FPCore", package: "FontPlaygroundKit"),
                .product(name: "FPEngineClient", package: "FontPlaygroundKit"),
            ]
        ),
        .target(
            name: "FPAppUI",
            dependencies: [
                "FPMacServices",
                .product(name: "FPCore", package: "FontPlaygroundKit"),
                .product(name: "FPEngineClient", package: "FontPlaygroundKit"),
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "FPMacHarness",
            dependencies: ["FPMacServices", .product(name: "FPEngineClient", package: "FontPlaygroundKit")]),
        .testTarget(name: "FPMacServicesTests", dependencies: ["FPMacServices"]),
        .testTarget(
            name: "FPMacHarnessTests",
            dependencies: ["FPMacHarness", "FPMacServices", .product(name: "FPCore", package: "FontPlaygroundKit")]),
        .testTarget(name: "FPAppUITests", dependencies: ["FPAppUI"]),
    ],
    swiftLanguageModes: [.v6]
)
