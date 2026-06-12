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
        .executable(name: "Lumi", targets: ["LumiApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
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
        .target(
            name: "LumiServices",
            dependencies: [
                "LumiKit",
                .product(name: "Yams", package: "Yams"),
            ],
            resources: [
                .copy("Resources/default-actions"),
                .copy("Resources/default-personas"),
            ]
        ),
        .target(name: "LumiState", dependencies: ["LumiKit"]),
        .target(
            name: "LumiUI",
            dependencies: [
                "LumiKit",
                "LumiState",
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/logo.png"),
            ]
        ),
        .executableTarget(
            name: "LumiApp",
            dependencies: ["LumiKit", "LumiTerminal", "LumiServices", "LumiState", "LumiUI"],
            resources: [.copy("Resources/icon.png")]
        ),
        .testTarget(name: "LumiKitTests", dependencies: ["LumiKit"]),
        .testTarget(name: "LumiTerminalTests", dependencies: ["LumiTerminal"]),
        .testTarget(name: "LumiServicesTests", dependencies: ["LumiServices"]),
        .testTarget(name: "LumiStateTests", dependencies: ["LumiState"]),
        .testTarget(name: "LumiUITests", dependencies: ["LumiUI"]),
    ]
)
