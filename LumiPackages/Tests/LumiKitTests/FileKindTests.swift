import XCTest
@testable import LumiKit

/// Dosya adı/uzantı → ikon sınıfı eşlemesi (Explorer ikon tablosu).
final class FileKindTests: XCTestCase {
    private func kind(_ name: String) -> FileKind {
        FileKind.classify(name: name, isFolder: false, isExpanded: false)
    }

    // MARK: - Klasör

    func testFolderUsesExpansionState() {
        XCTAssertEqual(FileKind.classify(name: "Sources", isFolder: true, isExpanded: false), .folder)
        XCTAssertEqual(FileKind.classify(name: "Sources", isFolder: true, isExpanded: true), .folderOpen)
    }

    func testFolderWinsOverExtensionLookingName() {
        // `MyApp.xcassets` bir klasördür; uzantı tablosuna düşmemeli.
        XCTAssertEqual(FileKind.classify(name: "Assets.xcassets", isFolder: true, isExpanded: false), .folder)
    }

    // MARK: - Kaynak kodu

    func testSourceExtensionsAreClassified() {
        XCTAssertEqual(kind("main.swift"), .swift)
        XCTAssertEqual(kind("Player.cs"), .csharp)
        XCTAssertEqual(kind("app.ts"), .typescript)
        XCTAssertEqual(kind("App.tsx"), .typescript)
        XCTAssertEqual(kind("index.js"), .javascript)
        XCTAssertEqual(kind("view.jsx"), .javascript)
        XCTAssertEqual(kind("script.py"), .python)
        XCTAssertEqual(kind("build.sh"), .shell)
    }

    func testExtensionMatchingIsCaseInsensitive() {
        XCTAssertEqual(kind("Main.SWIFT"), .swift)
        XCTAssertEqual(kind("PHOTO.PNG"), .image)
    }

    // MARK: - Veri / doküman

    func testDataAndDocumentExtensions() {
        XCTAssertEqual(kind("package.json"), .json)
        XCTAssertEqual(kind("config.yaml"), .yaml)
        XCTAssertEqual(kind("ci.yml"), .yaml)
        XCTAssertEqual(kind("README.md"), .markdown)
        XCTAssertEqual(kind("notes.txt"), .text)
        XCTAssertEqual(kind("Info.plist"), .config)
        XCTAssertEqual(kind("Cargo.toml"), .config)
    }

    // MARK: - Medya

    func testMediaExtensions() {
        XCTAssertEqual(kind("logo.png"), .image)
        XCTAssertEqual(kind("icon.svg"), .image)
        XCTAssertEqual(kind("clip.mp4"), .video)
        XCTAssertEqual(kind("theme.mp3"), .audio)
        XCTAssertEqual(kind("JetBrainsMono-Regular.ttf"), .font)
        XCTAssertEqual(kind("bundle.zip"), .archive)
    }

    // MARK: - Unity

    func testUnityExtensionsGetTheirOwnKinds() {
        XCTAssertEqual(kind("Main.unity"), .unityScene)
        XCTAssertEqual(kind("Player.prefab"), .unityPrefab)
        XCTAssertEqual(kind("LevelConfig.asset"), .unityScriptableObject)
        XCTAssertEqual(kind("Ground.mat"), .unityMaterial)
        XCTAssertEqual(kind("Player.cs.meta"), .unityMeta)
        XCTAssertEqual(kind("Water.shader"), .shader)
    }

    // MARK: - Tam ad tablosu

    func testExactNamesBeatExtensionTable() {
        XCTAssertEqual(kind("Makefile"), .shell)
        XCTAssertEqual(kind("Dockerfile"), .config)
        XCTAssertEqual(kind("dockerfile.dev"), .config)
        XCTAssertEqual(kind(".gitignore"), .git)
        XCTAssertEqual(kind(".gitattributes"), .git)
        XCTAssertEqual(kind(".editorconfig"), .config)
        XCTAssertEqual(kind(".env.local"), .config)
    }

    func testPackageSwiftStaysSwift() {
        XCTAssertEqual(kind("Package.swift"), .swift)
    }

    func testLockFilesAreLockKind() {
        XCTAssertEqual(kind("Package.resolved"), .lock)
        XCTAssertEqual(kind("package-lock.json"), .lock)
        XCTAssertEqual(kind("yarn.lock"), .lock)
        XCTAssertEqual(kind("Cargo.lock"), .lock)
    }

    // MARK: - Geri düşüş

    func testUnknownAndExtensionlessNamesAreGeneric() {
        XCTAssertEqual(kind("LICENSE"), .generic)
        XCTAssertEqual(kind("data.qwerty"), .generic)
        XCTAssertEqual(kind(""), .generic)
        XCTAssertEqual(kind(".hidden"), .generic)
    }

    func testEveryCaseIsReachableFromTheScale() {
        XCTAssertEqual(Set(FileKind.allCases).count, FileKind.allCases.count)
        XCTAssertTrue(FileKind.allCases.contains(.generic))
    }
}
