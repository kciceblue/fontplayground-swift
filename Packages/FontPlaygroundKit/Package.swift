// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FontPlaygroundKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FPCore", targets: ["FPCore"]),
        .library(name: "FPEngineClient", targets: ["FPEngineClient"]),
        .executable(name: "fpctl", targets: ["fpctl"]),
    ],
    targets: [
        .target(name: "FPCore"),
        .target(name: "FPEngineClient", dependencies: ["FPCore"]),
        .executableTarget(name: "fpctl", dependencies: ["FPCore", "FPEngineClient"]),
        .testTarget(name: "FPCoreTests", dependencies: ["FPCore"]),
        .testTarget(name: "FPEngineClientTests", dependencies: ["FPEngineClient"], resources: [.copy("Resources")]),
        .testTarget(name: "FPCTLTests", dependencies: ["fpctl"]),
    ],
    swiftLanguageModes: [.v6]
)
