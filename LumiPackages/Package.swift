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
        // v1.13.0 sonrası release'lenmemiş kritik düzeltmeler için revision pin'i:
        // 94b6356 CSI T alt-screen scroll (yukarı scroll'da bayat satırlar),
        // 9446f60/468d0a8 DEC 2026 synchronized output render, 551bfcc Shift+mouse
        // ile raporlama baypası (TUI çalışırken text seçimi).
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            revision: "24a68bcadc479d945c7ca32f21ac0a8ab895c690"
        ),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0"),
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
        .target(
            name: "LumiUI",
            dependencies: [
                "LumiKit",
                "LumiState",
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/Icons"),
                .copy("Resources/logo.png"),
            ]
        ),
        // Uygulama katmanı iki parçadır: test edilebilir kütüphane (`LumiAppCore`)
        // + yalnız `main.swift` içeren ince executable (`LumiApp` → ürün adı `Lumi`).
        .target(
            name: "LumiAppCore",
            dependencies: ["LumiKit", "LumiTerminal", "LumiServices", "LumiState", "LumiUI"],
            resources: [.copy("Resources/icon.png")]
        ),
        .executableTarget(name: "LumiApp", dependencies: ["LumiAppCore"]),
        // Paylaşılan el yazımı fake'ler (design/00 §3). Test-only olduğu için
        // Sources/ değil Tests/ altında durur; hiçbir ürün ona bağlı değildir.
        .target(name: "LumiTestSupport", dependencies: ["LumiKit"], path: "Tests/LumiTestSupport"),
        .testTarget(name: "LumiKitTests", dependencies: ["LumiKit", "LumiTestSupport"]),
        .testTarget(name: "LumiTerminalTests", dependencies: ["LumiTerminal", "LumiTestSupport"]),
        .testTarget(name: "LumiServicesTests", dependencies: ["LumiServices", "LumiTestSupport"]),
        .testTarget(name: "LumiStateTests", dependencies: ["LumiState", "LumiTestSupport"]),
        .testTarget(name: "LumiUITests", dependencies: ["LumiUI", "LumiTestSupport"]),
        .testTarget(name: "LumiAppTests", dependencies: ["LumiAppCore", "LumiTestSupport"]),
    ]
)
