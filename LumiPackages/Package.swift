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
        .library(name: "LumiRemote", targets: ["LumiRemote"]),
        .executable(name: "Lumi", targets: ["LumiApp"]),
    ],
    dependencies: [
        // v1.13.0 sonrası release'lenmemiş kritik düzeltmeler için revision pin'i:
        // 94b6356 CSI T alt-screen scroll (yukarı scroll'da bayat satırlar),
        // 9446f60/468d0a8 DEC 2026 synchronized output render, 551bfcc Shift+mouse
        // ile raporlama baypası (TUI çalışırken text seçimi).
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            revision: "24a68bcadc479d945c7ca32f21ac0a8ab895c690"
        ),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        // Remote dashboard'un HTTP + WebSocket sunucusu (kullanıcı onayı 2026-07-20):
        // hafif, saf Swift, transitive bağımlılık getirmez.
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.27.0"),
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
        .target(
            name: "LumiRemote",
            dependencies: [
                "LumiKit",
                .product(name: "FlyingFox", package: "FlyingFox"),
            ],
            resources: [.copy("Resources/dashboard.html")]
        ),
        .executableTarget(
            name: "LumiApp",
            dependencies: ["LumiKit", "LumiTerminal", "LumiServices", "LumiState", "LumiUI", "LumiRemote"],
            resources: [.copy("Resources/icon.png")]
        ),
        .testTarget(name: "LumiKitTests", dependencies: ["LumiKit"]),
        .testTarget(name: "LumiTerminalTests", dependencies: ["LumiTerminal"]),
        .testTarget(name: "LumiServicesTests", dependencies: ["LumiServices"]),
        .testTarget(name: "LumiStateTests", dependencies: ["LumiState"]),
        .testTarget(name: "LumiRemoteTests", dependencies: ["LumiRemote"]),
        .testTarget(name: "LumiUITests", dependencies: ["LumiUI"]),
    ]
)
