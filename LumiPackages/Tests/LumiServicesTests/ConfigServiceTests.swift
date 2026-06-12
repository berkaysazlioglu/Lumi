import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// Format-parite golden testleri (karar 9, design/04 faz 2 çıkış kriteri).
/// Fixture'lar makinedeki GERÇEK Electron çıktısından (path'ler anonimleştirilmiş)
/// türetildi — legacy/bilinmeyen alanlar (`gridColumns`, `activeView`) dahil.
final class ConfigServiceTests: XCTestCase {
    private var tempHome: URL!
    private var paths: LumiPaths!

    /// Gerçek config.json'ın birebir şekli — `notifications` anahtarı YOK (infill testi).
    private let realConfigFixture = """
    {
      "projectsRoot": "/Users/dev/wkspaces/Unity",
      "additionalPaths": [
        {
          "id": "3709c3cf-a13f-4af4-80cf-e58a57e90080",
          "path": "/Users/dev/wkspaces/Github",
          "type": "root"
        }
      ],
      "aiProvider": "claude",
      "maxTerminals": 12,
      "theme": "dark",
      "terminalFontSize": 13
    }
    """

    /// Gerçek ui-state.json'ın birebir şekli — legacy `gridColumns`/`activeView`
    /// alanları ve açık `activeTab: null` dahil.
    private let realUIStateFixture = """
    {
      "openTabs": [],
      "activeTab": null,
      "leftSidebarOpen": true,
      "rightSidebarOpen": false,
      "gridColumns": "auto",
      "activeView": "terminals",
      "windowBounds": {
        "x": 580,
        "y": 214,
        "width": 1400,
        "height": 900
      },
      "windowMaximized": false
    }
    """

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-test-\(UUID().uuidString)")
        paths = LumiPaths(mode: .development, homeDirectory: tempHome)
        try paths.ensureDirectoriesExist()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
        try super.tearDownWithError()
    }

    private func makeService(
        writeDebounce: Duration = .milliseconds(20)
    ) -> ConfigService {
        ConfigService(paths: paths, writeDebounce: writeDebounce)
    }

    private func writeFixture(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readJSONDict(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func awaitFirstEvent(
        _ stream: AsyncStream<ConfigEvent>,
        timeout: Duration = .seconds(2)
    ) async -> ConfigEvent? {
        await withTaskGroup(of: ConfigEvent?.self) { group in
            group.addTask {
                for await event in stream { return event }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Config okuma / migration

    func testDecodesRealConfigWithNotificationInfill() async throws {
        try writeFixture(realConfigFixture, to: paths.configFile)
        let service = makeService()

        let config = await service.config()
        XCTAssertEqual(config.projectsRoot, "/Users/dev/wkspaces/Unity")
        XCTAssertEqual(config.additionalPaths.count, 1)
        XCTAssertEqual(config.additionalPaths.first?.type, .root)
        XCTAssertEqual(config.aiProvider, .claude)
        XCTAssertEqual(config.maxTerminals, 12)
        XCTAssertEqual(config.theme, "dark")
        XCTAssertEqual(config.terminalFontSize, 13)
        // Diskte olmayan alan default'tan tamamlanır (spec/13 §1.1)
        XCTAssertEqual(config.notifications, .defaults)
        XCTAssertFalse(config.terminalFontSmoothing, "alan yokken default false (ince çizgi)")
        // Terminal customization alanları yokken default'a düşer (additive, karar 9)
        XCTAssertEqual(config.terminalTheme, "lumi")
        XCTAssertEqual(config.terminalFontFamily, "")
        XCTAssertEqual(config.terminalCursorStyle, "block")
        XCTAssertTrue(config.terminalCursorBlink)
    }

    func testTerminalCustomizationFieldsDecode() async throws {
        let json = realConfigFixture.replacingOccurrences(
            of: "\"terminalFontSize\": 13",
            with: """
            "terminalFontSize": 13,
              "terminalTheme": "dracula",
              "terminalFontFamily": "Menlo",
              "terminalCursorStyle": "bar",
              "terminalCursorBlink": false
            """
        )
        try writeFixture(json, to: paths.configFile)
        let config = await makeService().config()
        XCTAssertEqual(config.terminalTheme, "dracula")
        XCTAssertEqual(config.terminalFontFamily, "Menlo")
        XCTAssertEqual(config.terminalCursorStyle, "bar")
        XCTAssertFalse(config.terminalCursorBlink)
    }

    func testTerminalCustomizationRoundTrip() async throws {
        try writeFixture(realConfigFixture, to: paths.configFile)
        let service = makeService()

        try await service.updateConfig {
            $0.terminalTheme = "nord"
            $0.terminalFontFamily = "SF Mono"
            $0.terminalCursorStyle = "underline"
            $0.terminalCursorBlink = false
        }

        let written = try readJSONDict(paths.configFile)
        XCTAssertEqual(written["terminalTheme"] as? String, "nord")
        XCTAssertEqual(written["terminalFontFamily"] as? String, "SF Mono")
        XCTAssertEqual(written["terminalCursorStyle"] as? String, "underline")
        XCTAssertEqual(written["terminalCursorBlink"] as? Bool, false)
        // Mevcut alanlar korunur (additive, karar 9)
        XCTAssertEqual(written["terminalFontSize"] as? Int, 13)

        let reloaded = await ConfigService(paths: paths).config()
        XCTAssertEqual(reloaded.terminalTheme, "nord")
        XCTAssertEqual(reloaded.terminalFontFamily, "SF Mono")
        XCTAssertEqual(reloaded.terminalCursorStyle, "underline")
        XCTAssertFalse(reloaded.terminalCursorBlink)
    }

    func testSessionTriggerDefaultsWhenAbsent() async throws {
        try writeFixture(realConfigFixture, to: paths.configFile)
        let config = await makeService().config()
        XCTAssertEqual(config.sessionTrigger, .defaults)
        XCTAssertFalse(config.sessionTrigger.enabled)
        XCTAssertEqual(config.sessionTrigger.hour, 9)
        XCTAssertEqual(config.sessionTrigger.prompt, "hello")
    }

    func testSessionTriggerRoundTrips() async throws {
        try writeFixture(realConfigFixture, to: paths.configFile)
        let service = makeService()

        try await service.updateConfig {
            $0.sessionTrigger = SessionTrigger(enabled: true, hour: 7, minute: 30, prompt: "go")
        }

        let written = try readJSONDict(paths.configFile)
        let nested = try XCTUnwrap(written["sessionTrigger"] as? [String: Any])
        XCTAssertEqual(nested["enabled"] as? Bool, true)
        XCTAssertEqual(nested["hour"] as? Int, 7)
        XCTAssertEqual(nested["minute"] as? Int, 30)
        XCTAssertEqual(nested["prompt"] as? String, "go")
        // Mevcut alanlar korunur (additive, karar 9)
        XCTAssertEqual(written["terminalFontSize"] as? Int, 13)

        let reloaded = await ConfigService(paths: paths).config()
        XCTAssertEqual(
            reloaded.sessionTrigger,
            SessionTrigger(enabled: true, hour: 7, minute: 30, prompt: "go")
        )
    }

    func testTerminalFontSmoothingRoundTrip() async throws {
        try writeFixture(realConfigFixture, to: paths.configFile)
        let service = makeService()

        try await service.updateConfig { $0.terminalFontSmoothing = true }

        let written = try readJSONDict(paths.configFile)
        XCTAssertEqual(written["terminalFontSmoothing"] as? Bool, true)
        // mevcut alanlar korunur (karar 9 — additive)
        XCTAssertEqual(written["terminalFontSize"] as? Int, 13)

        let reloaded = await ConfigService(paths: paths).config()
        XCTAssertTrue(reloaded.terminalFontSmoothing)
    }

    func testMigrationRules() async throws {
        try writeFixture(
            #"{"projectsRoot": "/p", "additionalPaths": "garbage", "aiProvider": "gpt5"}"#,
            to: paths.configFile
        )
        let service = makeService()
        let config = await service.config()
        XCTAssertEqual(config.additionalPaths, [])
        XCTAssertEqual(config.aiProvider, .claude)
        XCTAssertEqual(config.maxTerminals, 12)
    }

    func testCorruptConfigFallsBackToDefaults() async throws {
        try writeFixture("{{{ not json", to: paths.configFile)
        let service = makeService()
        let config = await service.config()
        XCTAssertEqual(config, .defaults)
    }

    func testIsFirstRun() async throws {
        let service = makeService()
        let missingFile = await service.isFirstRun()
        XCTAssertTrue(missingFile, "config.json yokken first-run olmalı")

        try writeFixture(#"{"projectsRoot": ""}"#, to: paths.configFile)
        let emptyRoot = await service.isFirstRun()
        XCTAssertTrue(emptyRoot, "projectsRoot boşken first-run olmalı")

        try writeFixture(realConfigFixture, to: paths.configFile)
        let configured = await service.isFirstRun()
        XCTAssertFalse(configured)
    }

    // MARK: - Config yazma / event

    func testUpdateEmitsEqualityDiffEventIncludingZero() async throws {
        // Electron truthiness bug'ı: maxTerminals=0 yan etkiyi atlar — bizde atlamaz
        try writeFixture(realConfigFixture, to: paths.configFile)
        let service = makeService()
        let stream = await service.events()

        try await service.updateConfig { $0.maxTerminals = 0 }

        guard case .configChanged(let old, let new)? = await awaitFirstEvent(stream) else {
            return XCTFail("configChanged event'i gelmedi")
        }
        XCTAssertEqual(old.maxTerminals, 12)
        XCTAssertEqual(new.maxTerminals, 0)

        let written = try readJSONDict(paths.configFile)
        XCTAssertEqual(written["maxTerminals"] as? Int, 0)
    }

    func testUpdatePreservesUnknownConfigKeys() async throws {
        let withFuture = realConfigFixture.replacingOccurrences(
            of: "\"theme\": \"dark\",",
            with: "\"theme\": \"dark\",\n  \"futureField\": \"electron-wrote-this\","
        )
        try writeFixture(withFuture, to: paths.configFile)
        let service = makeService()

        try await service.updateConfig { $0.maxTerminals = 8 }

        let written = try readJSONDict(paths.configFile)
        XCTAssertEqual(written["futureField"] as? String, "electron-wrote-this")
        XCTAssertEqual(written["maxTerminals"] as? Int, 8)
    }

    func testNoopUpdateEmitsNoEvent() async throws {
        try writeFixture(realConfigFixture, to: paths.configFile)
        let service = makeService()
        let stream = await service.events()

        try await service.updateConfig { _ in }
        try await service.updateConfig { $0.theme = "dark" } // değişiklik yok

        // Gerçek bir değişiklik yap; İLK gelen event bu olmalı (öncekiler yutulmadıysa fail)
        try await service.updateConfig { $0.terminalFontSize = 14 }
        guard case .configChanged(let old, let new)? = await awaitFirstEvent(stream) else {
            return XCTFail("event gelmedi")
        }
        XCTAssertEqual(old.terminalFontSize, 13)
        XCTAssertEqual(new.terminalFontSize, 14)
    }

    func testPathsWrittenWithoutEscapedSlashes() async throws {
        try writeFixture(realConfigFixture, to: paths.configFile)
        let service = makeService()
        try await service.updateConfig { $0.projectsRoot = "/Users/dev/new root" }

        let contents = try String(contentsOf: paths.configFile, encoding: .utf8)
        XCTAssertFalse(contents.contains("\\/"), "Electron düz / yazar; \\/ kaçışı parite bozar")
        XCTAssertTrue(contents.contains("/Users/dev/new root"))
    }

    // MARK: - UI state golden round-trip

    func testUIStateRoundTripPreservesLegacyKeys() async throws {
        try writeFixture(realUIStateFixture, to: paths.uiStateFile)
        let service = makeService()

        let state = await service.uiState()
        XCTAssertEqual(state.leftSidebarOpen, true)
        XCTAssertNil(state.activeTab)
        XCTAssertEqual(state.windowBounds?.x, 580)

        await service.updateUIState { $0.leftSidebarOpen = false }
        await service.flushPendingWrites()

        let written = try readJSONDict(paths.uiStateFile)
        // Tipli modelde olmayan legacy alanlar AYNEN korunmalı (karar 9)
        XCTAssertEqual(written["gridColumns"] as? String, "auto")
        XCTAssertEqual(written["activeView"] as? String, "terminals")
        XCTAssertEqual(written["leftSidebarOpen"] as? Bool, false)
        XCTAssertTrue(written["activeTab"] is NSNull, "activeTab açıkça null yazılmalı")

        let bounds = try XCTUnwrap(written["windowBounds"] as? [String: Any])
        XCTAssertEqual(bounds["x"] as? Int, 580)

        let contents = try String(contentsOf: paths.uiStateFile, encoding: .utf8)
        XCTAssertFalse(contents.contains("580.0"), "tam sayı bounds Electron gibi int yazılmalı")
    }

    func testActiveTabTransitionsToExplicitNull() async throws {
        let service = makeService()
        await service.updateUIState { $0.activeTab = "/repo/a" }
        await service.flushPendingWrites()
        var written = try readJSONDict(paths.uiStateFile)
        XCTAssertEqual(written["activeTab"] as? String, "/repo/a")

        await service.updateUIState { $0.activeTab = nil }
        await service.flushPendingWrites()
        written = try readJSONDict(paths.uiStateFile)
        XCTAssertTrue(written["activeTab"] is NSNull)
    }

    func testDebouncedWritesCoalesce() async throws {
        let service = makeService(writeDebounce: .milliseconds(30))
        await service.updateUIState { $0.openTabs = ["/a"] }
        await service.updateUIState { $0.openTabs = ["/a", "/b"] }

        try await Task.sleep(for: .milliseconds(200))
        let written = try readJSONDict(paths.uiStateFile)
        XCTAssertEqual(written["openTabs"] as? [String], ["/a", "/b"])
    }

    func testProjectGridLayoutsRoundTrip() async throws {
        let service = makeService()
        await service.updateUIState {
            $0.projectGridLayouts["/repo/x"] = GridLayout(
                mode: .columns, count: 3, heightMode: .scroll, heightRatio: .full
            )
        }
        await service.flushPendingWrites()

        let written = try readJSONDict(paths.uiStateFile)
        let layouts = try XCTUnwrap(written["projectGridLayouts"] as? [String: Any])
        let entry = try XCTUnwrap(layouts["/repo/x"] as? [String: Any])
        // mode/count korunur (karar 9), heightMode/heightRatio eklenir (additive)
        XCTAssertEqual(entry["mode"] as? String, "columns")
        XCTAssertEqual(entry["count"] as? Int, 3)
        XCTAssertEqual(entry["heightMode"] as? String, "scroll")
        XCTAssertEqual(entry["heightRatio"] as? String, "full")

        let fresh = ConfigService(paths: paths)
        let reloaded = await fresh.uiState()
        XCTAssertEqual(
            reloaded.projectGridLayouts["/repo/x"],
            GridLayout(mode: .columns, count: 3, heightMode: .scroll, heightRatio: .full)
        )
    }

    func testLegacyRowsModeMigratesToFit() async throws {
        // v1/eski dosyada mode:"rows" → auto + fit'e migrate edilir
        let json = """
        {"projectGridLayouts":{"/repo/r":{"mode":"rows","count":2}}}
        """
        try json.write(to: paths.uiStateFile, atomically: true, encoding: .utf8)
        let reloaded = await ConfigService(paths: paths).uiState()
        XCTAssertEqual(reloaded.projectGridLayouts["/repo/r"], GridLayout(mode: .auto, count: 2, heightMode: .fit))
    }

    func testMissingHeightFieldsDefaultToScrollAndHalf() async throws {
        // heightMode/heightRatio'suz eski girdi → scroll + half default'u
        let json = """
        {"projectGridLayouts":{"/repo/c":{"mode":"columns","count":4}}}
        """
        try json.write(to: paths.uiStateFile, atomically: true, encoding: .utf8)
        let reloaded = await ConfigService(paths: paths).uiState()
        XCTAssertEqual(
            reloaded.projectGridLayouts["/repo/c"],
            GridLayout(mode: .columns, count: 4, heightMode: .scroll, heightRatio: .half)
        )
    }
}
