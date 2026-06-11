// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumiPackages",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LumiKit", targets: ["LumiKit"]),
        .library(name: "LumiTerminal", targets: ["LumiTerminal"]),
        .library(name: "LumiServices", targets: ["LumiServices"]),
        .library(name: "LumiState", targets: ["LumiState"]),
        .library(name: "LumiUI", targets: ["LumiUI"]),
        .executable(name: "lumi-skeleton", targets: ["LumiSkeleton"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(name: "LumiKit"),
        .target(
            name: "LumiTerminal",
            dependencies: [
                "LumiKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .target(name: "LumiServices", dependencies: ["LumiKit"]),
        .target(name: "LumiState", dependencies: ["LumiKit"]),
        .target(name: "LumiUI", dependencies: ["LumiKit", "LumiState"]),
        .executableTarget(
            name: "LumiSkeleton",
            dependencies: ["LumiKit", "LumiTerminal", "LumiServices", "LumiState", "LumiUI"]
        ),
        .testTarget(name: "LumiKitTests", dependencies: ["LumiKit"]),
        .testTarget(name: "LumiTerminalTests", dependencies: ["LumiTerminal"]),
        .testTarget(name: "LumiServicesTests", dependencies: ["LumiServices"]),
        .testTarget(name: "LumiStateTests", dependencies: ["LumiState"]),
    ]
)
