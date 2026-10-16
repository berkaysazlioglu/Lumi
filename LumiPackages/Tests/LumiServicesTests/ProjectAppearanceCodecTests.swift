import XCTest
import LumiKit
@testable import LumiServices

/// Karar 120: `projectAppearance` additive anahtarı.
final class ProjectAppearanceCodecTests: XCTestCase {
    func testFullEntryRoundTrips() {
        let map: [String: ProjectAppearance] = [
            "/p/game": ProjectAppearance(color: .teal, icon: .symbol("gamecontroller"), rootTitle: "dev"),
            "/p/tool": ProjectAppearance(icon: .emoji("🚀")),
            "/p/web": ProjectAppearance(color: .lime),
        ]
        XCTAssertEqual(ProjectAppearanceCodec.decodeMap(ProjectAppearanceCodec.overlayMap(map)), map)
    }

    func testOverlayWritesOnlyFilledFieldsAndSkipsEmptyEntries() {
        let overlay = ProjectAppearanceCodec.overlayMap([
            "/p/game": ProjectAppearance(color: .pink),
            "/p/empty": .none,
            "/p/emoji": ProjectAppearance(icon: .emoji("🚀"), rootTitle: "  dev  "),
        ])
        XCTAssertEqual(overlay, [
            "/p/game": ["color": "pink"],
            "/p/emoji": ["icon": "emoji:🚀", "title": "dev"],
        ])
    }

    func testInvalidFieldsAreDroppedOnRead() {
        let decoded = ProjectAppearanceCodec.decodeMap([
            "/p/a": ["color": "purple", "icon": "sf:trash", "title": "   "],
            "/p/b": ["color": "blue", "icon": "emoji:🚀🚀", "title": "ok"],
            "/p/c": ["icon": "emoji:a"],
            "/p/d": ["icon": "star"],
            "/p/e": ["icon": "sf:house", "title": "main"],
            "/p/f": ["icon": "emoji:👍🏽", "title": 3],
            "relative": ["color": "blue"],
            "/p/g": "blue",
        ])
        XCTAssertEqual(decoded, [
            "/p/b": ProjectAppearance(color: .blue, rootTitle: "ok"),
            "/p/f": ProjectAppearance(icon: .emoji("👍🏽")),
        ], "tanınmayan renk, izin listesi dışı SF Symbol, çok grapheme'li emoji, boş başlık ve varsayılanlar atılır")
    }

    func testOverlongTitleIsTrimmedToTheLimit() {
        let long = String(repeating: "x", count: ProjectRootTitle.maxLength + 10)
        let decoded = ProjectAppearanceCodec.decodeMap(["/p": ["title": long]])
        XCTAssertEqual(decoded["/p"]?.rootTitle?.count, ProjectRootTitle.maxLength)
    }

    func testAbsentOrMistypedKeyDecodesEmpty() {
        XCTAssertEqual(ProjectAppearanceCodec.decodeMap(nil), [:], "absent key is additive (karar 9)")
        XCTAssertEqual(ProjectAppearanceCodec.decodeMap(["/p"]), [:])
        XCTAssertEqual(ProjectAppearanceCodec.decodeMap("blue"), [:])
    }

    /// Diske yazılan adlar kilitlenir — yeniden adlandırma diskteki seçimi
    /// sessizce düşürür.
    func testPersistedNamesAreStable() {
        XCTAssertEqual(ProjectColor.allCases.map(\.rawValue), ["blue", "teal", "pink", "orange", "lime", "green", "fuchsia"])
        XCTAssertEqual(ProjectIcon.symbol("star").persisted, "sf:star")
        XCTAssertEqual(ProjectIcon.emoji("🚀").persisted, "emoji:🚀")
    }

    /// Boş harita da yazılır: sığ merge yazımı anahtarı atlarsa son sıfırlanan
    /// görünüm diskte kalırdı.
    func testResettingTheLastAppearanceClearsItOnDisk() {
        let raw: [String: Any] = ["projectAppearance": ["/p": ["color": "blue"]]]
        var config = ConfigCodec.decodeConfig(from: raw)
        XCTAssertEqual(config.projectAppearance["/p"]?.color, .blue)
        config.projectAppearance = [:]
        let merged = raw.merging(ConfigCodec.configOverlay(config)) { _, new in new }
        XCTAssertEqual(ConfigCodec.decodeConfig(from: merged).projectAppearance, [:])
    }
}
