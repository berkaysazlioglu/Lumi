import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// Refactor plan 2.6 — **overlay bütünlüğü**: modele yeni bir alan eklenip
/// `ConfigCodec` overlay'i güncellenmezse alan sessizce diske yazılmaz
/// (karar 9 ihlali; derleyici yakalayamaz). Bu testler `Mirror` ile modelin
/// alanlarını sayar ve overlay anahtarlarıyla karşılaştırır.
///
/// Alan adı ↔ JSON anahtarı eşlemesi bugün BİREBİR (camelCase); ayrıksı
/// durumlar aşağıdaki tablolarda açıkça listelenir ve gerekçelendirilir.
final class ConfigCodecIntegrityTests: XCTestCase {
    // MARK: - Bilinçli istisnalar

    /// Diske YAZILMAYAN `UIState` alanları ve gerekçeleri.
    /// - `legacyGridColumns`: yalnız OKUNUR (v1 `gridColumns` migration girdisi);
    ///   ham anahtar bilinmeyen-anahtar korumasıyla diskte aynen kalır.
    private static let uiStateWriteExemptFields: [String: String] = [
        "legacyGridColumns": "yalnız okuma — v1 gridColumns migration girdisi",
    ]

    /// Alan adı → JSON anahtarı (yalnız camelCase eşleşmeyenler). Bugün BOŞ.
    private static let configKeyMapping: [String: String] = [:]
    private static let uiStateKeyMapping: [String: String] = [:]

    private func fieldNames(of value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }

    // MARK: - AppConfig ⊆ configOverlay

    func testEveryAppConfigFieldIsWrittenToOverlay() {
        let fields = fieldNames(of: AppConfig.defaults)
        XCTAssertFalse(fields.isEmpty, "Mirror alan üretmedi — test anlamsız olurdu")

        let overlayKeys = Set(ConfigCodec.configOverlay(.defaults).keys)
        let missing = fields
            .map { Self.configKeyMapping[$0] ?? $0 }
            .filter { !overlayKeys.contains($0) }

        XCTAssertTrue(
            missing.isEmpty,
            "configOverlay bu alanları diske yazmıyor (karar 9): \(missing.sorted())"
        )
    }

    /// Ters yön: overlay'de modelde karşılığı olmayan anahtar kalmasın
    /// (silinen alanın overlay artığı bayat veri yazar).
    func testOverlayHasNoOrphanKeys() {
        let fields = Set(fieldNames(of: AppConfig.defaults).map { Self.configKeyMapping[$0] ?? $0 })
        let orphans = ConfigCodec.configOverlay(.defaults).keys.filter { !fields.contains($0) }
        XCTAssertTrue(orphans.isEmpty, "configOverlay'de modelde olmayan anahtar: \(orphans.sorted())")
    }

    // MARK: - UIState ⊆ uiStateOverlay

    func testEveryUIStateFieldIsWrittenToOverlay() {
        // Opsiyonel alanlar (windowBounds/windowMaximized) yalnız DOLU iken
        // overlay'e girer — bu yüzden tam dolu bir state ile bakılır.
        let state = Self.fullyPopulatedUIState
        let fields = fieldNames(of: state)
        XCTAssertFalse(fields.isEmpty)

        let overlayKeys = Set(ConfigCodec.uiStateOverlay(state).keys)
        let missing = fields
            .filter { Self.uiStateWriteExemptFields[$0] == nil }
            .map { Self.uiStateKeyMapping[$0] ?? $0 }
            .filter { !overlayKeys.contains($0) }

        XCTAssertTrue(
            missing.isEmpty,
            "uiStateOverlay bu alanları diske yazmıyor (karar 9): \(missing.sorted())"
        )
    }

    func testUIStateOverlayHasNoOrphanKeys() {
        let state = Self.fullyPopulatedUIState
        let fields = Set(fieldNames(of: state).map { Self.uiStateKeyMapping[$0] ?? $0 })
        let orphans = ConfigCodec.uiStateOverlay(state).keys.filter { !fields.contains($0) }
        XCTAssertTrue(orphans.isEmpty, "uiStateOverlay'de modelde olmayan anahtar: \(orphans.sorted())")
    }

    /// İstisna listesi belgelenmiş halde kalsın: alan modelden kalkarsa
    /// muafiyet de kalkmalı (bayat muafiyet yeni bir alanı sessizce örtebilir).
    func testExemptFieldsStillExistOnModel() {
        let fields = Set(fieldNames(of: Self.fullyPopulatedUIState))
        for (name, reason) in Self.uiStateWriteExemptFields {
            XCTAssertTrue(fields.contains(name), "muafiyet bayat: \(name) (\(reason))")
        }
    }

    // MARK: - Round-trip (defaults'tan FARKLI her alan)

    func testAppConfigRoundTripsThroughOverlayAndJSON() throws {
        let config = Self.nonDefaultConfig
        // Her alan gerçekten default'tan farklı mı? (Aksi halde test bir şey kanıtlamaz.)
        for (label, value) in Mirror(reflecting: config).children {
            guard let label else { continue }
            let defaultValue = Mirror(reflecting: AppConfig.defaults).children
                .first { $0.label == label }?.value
            XCTAssertFalse(
                "\(value)" == "\(defaultValue ?? "")",
                "\(label) default ile aynı — round-trip bu alanı kanıtlamıyor"
            )
        }

        let decoded = ConfigCodec.decodeConfig(from: try jsonRoundTrip(ConfigCodec.configOverlay(config)))
        XCTAssertEqual(decoded, config)
    }

    func testUIStateRoundTripsThroughOverlayAndJSON() throws {
        // legacyGridColumns yazılmadığı için round-trip'e nil ile girer.
        let state = Self.fullyPopulatedUIState
        let decoded = ConfigCodec.decodeUIState(from: try jsonRoundTrip(ConfigCodec.uiStateOverlay(state)))
        XCTAssertEqual(decoded, state)
    }

    /// Overlay doğrudan (JSONSerialization'dan geçmeden) decode edilince de
    /// aynı sonucu vermeli — `boolValue`/`intValue` köprüsü Swift tiplerinde de çalışır.
    func testAppConfigRoundTripsWithoutJSONSerialization() {
        let config = Self.nonDefaultConfig
        XCTAssertEqual(ConfigCodec.decodeConfig(from: ConfigCodec.configOverlay(config)), config)
    }

    // MARK: - Fixture'lar

    private func jsonRoundTrip(_ overlay: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: overlay)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static let nonDefaultConfig = AppConfig(
        projectsRoot: "/tmp/projects",
        additionalPaths: [
            AdditionalPath(id: "id-1", path: "/tmp/extra", type: .root, label: "Extra"),
            AdditionalPath(id: "id-2", path: "/tmp/solo", type: .repo),
        ],
        aiProvider: .codex,
        theme: "light",
        terminalFontSize: 17,
        terminalFontFamily: "Menlo",
        terminalCursorStyle: TerminalCursorShape.bar.rawValue,
        terminalCursorBlink: false,
        notifications: NotificationSettings(
            unseenEnabled: false,
            unseenIntervalMinutes: 7,
            seenEnabled: false,
            seenIntervalMinutes: 11
        ),
        autoMinimizeOnSend: true,
        sessionTrigger: SessionTrigger(enabled: true, hour: 22, minute: 45, prompt: "go"),
        usageAutoRefresh: UsageAutoRefresh(enabled: true, intervalMinutes: 1),
        usageIndicators: UsageIndicators(claude: false, codex: true)
    )

    private static let fullyPopulatedUIState = UIState(
        openTabs: ["/r/alpha", "/r/beta"],
        activeTab: "/r/beta",
        leftSidebarOpen: false,
        rightSidebarOpen: true,
        projectGridLayouts: [
            "/r/alpha": GridLayout(mode: .columns, count: 3, heightMode: .fit, heightRatio: .third),
        ],
        windowBounds: WindowBounds(x: 10, y: 20, width: 1200, height: 800),
        windowMaximized: true,
        resumeSessions: [ResumeSession(repoPath: "/r/alpha", sessionID: "s-1")],
        legacyGridColumns: nil
    )
}
