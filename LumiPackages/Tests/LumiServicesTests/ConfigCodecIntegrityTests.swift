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
            // K34: `panelLayout` alanı diske İKİ anahtar olarak iner
            // (`panelLayout` + `visibleSlots`) — görünürlük eski bool'larla
            // aynı bilgi olduğu için tek başına okunabilir kalır.
            .union(["visibleSlots"])
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
        usageAutoRefresh: UsageAutoRefresh(enabled: true, intervalMinutes: 15),
        usageIndicators: UsageIndicators(claude: false, codex: true),
        computerAwakeMode: .auto,
        agentHooksEnabled: false,
        workspaces: [ProjectWorkspace(projectPath: "/p", path: "/w", name: "Feature", branch: "feature", scm: .git)]
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
        activeRoute: "tasks",
        panelLayout: PanelLayout.defaults
            .moving(.fileTree, to: .right, index: 0)
            .settingVisible(.right, true)
            .settingWidth(320, for: .left),
        legacyGridColumns: nil
    )
}

// MARK: - Alt codec'ler (refactor 5.7: bölüm başına decode/overlay çifti)

/// Kök overlay'ler alt codec'lere devredildiği için bütünlük kontrolü de alt
/// tip bazında yapılır: bir alt tipe alan eklenip o codec'in overlay'i
/// güncellenmezse alan sessizce diske yazılmaz (karar 9).
extension ConfigCodecIntegrityTests {
    private func fields(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    /// Tek bir alt codec için iki yönlü kontrol: alan ⊆ overlay ve overlay ⊆ alan.
    private func assertOverlayMatchesFields<T>(
        _ value: T,
        overlay: [String: Any],
        exempt: Set<String> = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let names = fields(of: value)
        XCTAssertFalse(names.isEmpty, "Mirror alan üretmedi", file: file, line: line)
        let keys = Set(overlay.keys)

        let missing = names.subtracting(exempt).subtracting(keys)
        XCTAssertTrue(
            missing.isEmpty,
            "overlay bu alanları yazmıyor (karar 9): \(missing.sorted())",
            file: file, line: line
        )
        let orphans = keys.subtracting(names)
        XCTAssertTrue(
            orphans.isEmpty,
            "overlay'de modelde olmayan anahtar: \(orphans.sorted())",
            file: file, line: line
        )
    }

    func testNotificationSettingsCodecCoversEveryField() {
        let value = NotificationSettings(
            unseenEnabled: false, unseenIntervalMinutes: 7,
            seenEnabled: false, seenIntervalMinutes: 11
        )
        assertOverlayMatchesFields(value, overlay: NotificationSettingsCodec.overlay(value))
        XCTAssertEqual(NotificationSettingsCodec.decode(NotificationSettingsCodec.overlay(value)), value)
    }

    func testSessionTriggerCodecCoversEveryField() {
        let value = SessionTrigger(enabled: true, hour: 22, minute: 45, prompt: "go")
        assertOverlayMatchesFields(value, overlay: SessionTriggerCodec.overlay(value))
        XCTAssertEqual(SessionTriggerCodec.decode(SessionTriggerCodec.overlay(value)), value)
    }

    func testUsageAutoRefreshCodecCoversEveryField() {
        let value = UsageAutoRefresh(enabled: true, intervalMinutes: 30)
        assertOverlayMatchesFields(value, overlay: UsageAutoRefreshCodec.overlay(value))
        XCTAssertEqual(UsageAutoRefreshCodec.decode(UsageAutoRefreshCodec.overlay(value)), value)
    }

    func testUsageIndicatorsCodecCoversEveryField() {
        let value = UsageIndicators(claude: false, codex: true)
        assertOverlayMatchesFields(value, overlay: UsageIndicatorsCodec.overlay(value))
        XCTAssertEqual(UsageIndicatorsCodec.decode(UsageIndicatorsCodec.overlay(value)), value)
    }

    func testAdditionalPathCodecCoversEveryField() {
        let value = AdditionalPath(id: "id-1", path: "/tmp/x", type: .root, label: "Extra")
        assertOverlayMatchesFields(value, overlay: AdditionalPathCodec.overlay(value))
        XCTAssertEqual(AdditionalPathCodec.decode(AdditionalPathCodec.overlay(value)), value)
    }

    /// `label` nil iken anahtar HİÇ yazılmaz (Electron paritesi) — bu yüzden
    /// muafiyetle bakılır.
    func testAdditionalPathOmitsNilLabel() {
        let value = AdditionalPath(id: "id-2", path: "/tmp/y", type: .repo, label: nil)
        let overlay = AdditionalPathCodec.overlay(value)
        XCTAssertNil(overlay["label"])
        assertOverlayMatchesFields(value, overlay: overlay, exempt: ["label"])
        XCTAssertEqual(AdditionalPathCodec.decode(overlay), value)
    }

    func testGridLayoutCodecCoversEveryField() {
        let value = GridLayout(mode: .columns, count: 3, heightMode: .fit, heightRatio: .third)
        assertOverlayMatchesFields(value, overlay: GridLayoutCodec.overlay(value))
        XCTAssertEqual(GridLayoutCodec.decode(GridLayoutCodec.overlay(value)), value)
    }

    func testWindowBoundsCodecCoversEveryField() {
        let value = WindowBounds(x: 10, y: 20.5, width: 1200, height: 800)
        assertOverlayMatchesFields(value, overlay: WindowBoundsCodec.overlay(value))
        XCTAssertEqual(WindowBoundsCodec.decode(WindowBoundsCodec.overlay(value)), value)
    }

    /// Tam sayı koordinatlar `Int` olarak yazılır (580, 580.0 değil).
    func testWindowBoundsWritesIntegralValuesAsIntegers() {
        let overlay = WindowBoundsCodec.overlay(
            WindowBounds(x: 580, y: 214.5, width: 1400, height: 900)
        )
        XCTAssertTrue(overlay["x"] is Int)
        XCTAssertTrue(overlay["width"] is Int)
        XCTAssertTrue(overlay["y"] is Double)
    }

    func testResumeSessionCodecCoversEveryField() {
        let value = ResumeSession(repoPath: "/r/alpha", sessionID: "s-1")
        assertOverlayMatchesFields(value, overlay: ResumeSessionCodec.overlay(value))
        XCTAssertEqual(ResumeSessionCodec.decode(ResumeSessionCodec.overlay(value)), value)
    }

    /// Kök `AppConfig` overlay'i alt bölümleri gerçekten alt codec'lerin
    /// ürettiği sözlüklerle doldurur (kopya tanım kalmadığının kanıtı).
    func testRootOverlayDelegatesToSectionCodecs() throws {
        let config = Self.nonDefaultConfig
        let overlay = ConfigCodec.configOverlay(config)

        let notifications = try XCTUnwrap(overlay["notifications"] as? [String: Any])
        XCTAssertEqual(
            notifications as NSDictionary,
            NotificationSettingsCodec.overlay(config.notifications) as NSDictionary
        )
        let trigger = try XCTUnwrap(overlay["sessionTrigger"] as? [String: Any])
        XCTAssertEqual(
            trigger as NSDictionary,
            SessionTriggerCodec.overlay(config.sessionTrigger) as NSDictionary
        )
        let autoRefresh = try XCTUnwrap(overlay["usageAutoRefresh"] as? [String: Any])
        XCTAssertEqual(
            autoRefresh as NSDictionary,
            UsageAutoRefreshCodec.overlay(config.usageAutoRefresh) as NSDictionary
        )
        let indicators = try XCTUnwrap(overlay["usageIndicators"] as? [String: Any])
        XCTAssertEqual(
            indicators as NSDictionary,
            UsageIndicatorsCodec.overlay(config.usageIndicators) as NSDictionary
        )
    }
}
