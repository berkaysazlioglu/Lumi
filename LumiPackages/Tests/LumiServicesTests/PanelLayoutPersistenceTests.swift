import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// K34: `panelLayout` + `visibleSlots` additive anahtarları ve eski
/// `leftSidebarOpen`/`rightSidebarOpen` bool'larının projeksiyon olarak
/// yaşamaya devam etmesi (karar 9).
final class PanelLayoutPersistenceTests: XCTestCase {
    private func decode(_ dict: [String: Any]) -> UIState {
        ConfigCodec.decodeUIState(from: dict)
    }

    private func overlay(_ state: UIState) -> [String: Any] {
        ConfigCodec.uiStateOverlay(state)
    }

    // MARK: - Migration (yeni anahtar yok)

    /// K42: sağ yuvada kalıcı 280 eski default'tur (resize UI'ı hiç olmadı),
    /// yeni proje paneli genişliğine taşınır; diğer değerler aynen kalır.
    func testLegacyRightWidthMigratesToProjectPanelWidth() {
        let legacy = decode(["panelLayout": ["widths": ["left": 280, "right": 280]], "visibleSlots": ["left"]])
        XCTAssertEqual(legacy.panelLayout?.width(for: .left), 280)
        XCTAssertEqual(legacy.panelLayout?.width(for: .right), PanelLayout.projectPanelWidth)

        let custom = decode(["panelLayout": ["widths": ["right": 320]], "visibleSlots": ["left"]])
        XCTAssertEqual(custom.panelLayout?.width(for: .right), 320, "280 dışındaki değerler korunur")
    }

    func testMissingPanelLayoutKeyDecodesAsNil() {
        let state = decode(["leftSidebarOpen": false, "rightSidebarOpen": true])
        XCTAssertNil(state.panelLayout, "yeni anahtar yoksa nil — migration LayoutStore'da")
        XCTAssertFalse(state.leftSidebarOpen)
        XCTAssertTrue(state.rightSidebarOpen)
    }

    /// Yerleşim var ama görünürlük anahtarı yoksa eski bool'lar otoritedir
    /// (yarım yazılmış dosya).
    func testPanelLayoutWithoutVisibleSlotsFallsBackToLegacyBooleans() {
        let state = decode([
            "leftSidebarOpen": false,
            "rightSidebarOpen": true,
            "panelLayout": ["slots": ["left": ["sessions"]], "widths": ["left": 300]],
        ])
        XCTAssertEqual(state.panelLayout?.visibleSlots, [.right])
        XCTAssertEqual(state.panelLayout?.items(in: .left), [.sessions])
        XCTAssertEqual(state.panelLayout?.width(for: .left), 300)
        XCTAssertEqual(
            state.panelLayout?.items(in: .right),
            [.projectTools],
            "yazılmamış yuva default'undan gelir"
        )
    }

    func testVisibleSlotsKeyWinsWhenPresent() {
        let state = decode([
            "leftSidebarOpen": true,
            "rightSidebarOpen": false,
            "panelLayout": ["slots": [:], "widths": [:]],
            "visibleSlots": ["right"],
        ])
        XCTAssertEqual(state.panelLayout?.visibleSlots, [.right])
    }

    func testUnknownSlotAndItemNamesAreIgnored() {
        let state = decode([
            "panelLayout": ["slots": ["left": ["sessions", 42], "ufo": ["x"]], "widths": ["ufo": 100]],
            "visibleSlots": ["left", "ufo"],
        ])
        XCTAssertEqual(state.panelLayout?.items(in: .left), [.sessions], "string olmayan id atlanır")
        XCTAssertEqual(state.panelLayout?.visibleSlots, [.left], "bilinmeyen yuva adı atlanır")
    }

    // MARK: - Yazım (karar 9 projeksiyonu)

    func testOverlayOmitsPanelKeysWhenLayoutIsNil() {
        let keys = Set(overlay(.defaults).keys)
        XCTAssertFalse(keys.contains("panelLayout"), "nil alan diske yeni anahtar açmaz")
        XCTAssertFalse(keys.contains("visibleSlots"))
        XCTAssertTrue(keys.contains("leftSidebarOpen"), "eski alanlar her zaman yazılır")
    }

    func testOverlayWritesBothKeysAndKeepsLegacyBooleans() {
        var state = UIState.defaults
        state.leftSidebarOpen = false
        state.rightSidebarOpen = true
        state.panelLayout = PanelLayout.migrating(leftOpen: false, rightOpen: true)

        let written = overlay(state)
        XCTAssertNotNil(written["panelLayout"])
        XCTAssertEqual(written["visibleSlots"] as? [String], ["right"])
        XCTAssertEqual(written["leftSidebarOpen"] as? Bool, false)
        XCTAssertEqual(written["rightSidebarOpen"] as? Bool, true)
    }

    /// Genişlikler Electron paritesiyle tam sayı yazılır ("280", "280.0" değil).
    func testIntegralWidthsAreWrittenAsIntegers() {
        var state = UIState.defaults
        state.panelLayout = PanelLayout.defaults
        let widths = (overlay(state)["panelLayout"] as? [String: Any])?["widths"] as? [String: Any]
        XCTAssertEqual(widths?["left"] as? Int, 280)
    }

    func testVisibleSlotsOrderIsDeterministic() {
        var state = UIState.defaults
        state.panelLayout = PanelLayout.defaults
            .settingVisible(.bottom, true)
            .settingVisible(.right, true)
        XCTAssertEqual(
            overlay(state)["visibleSlots"] as? [String],
            ["left", "right", "bottom"],
            "PanelSlot.allCases sırası — Set'in rastgele sırası diske sızmaz"
        )
    }

    // MARK: - Auto-reveal (karar 44, additive `panelLayout.autoReveal`)

    func testMissingAutoRevealKeyDecodesAsEmpty() {
        let state = decode(["panelLayout": ["slots": [:], "widths": [:]], "visibleSlots": ["left"]])
        XCTAssertEqual(state.panelLayout?.autoRevealSlots, [])
    }

    func testAutoRevealKeyIsDecodedAndUnknownNamesIgnored() {
        let state = decode([
            "panelLayout": ["slots": [:], "widths": [:], "autoReveal": ["right", "ufo", 7]],
            "visibleSlots": ["left"],
        ])
        XCTAssertEqual(state.panelLayout?.autoRevealSlots, [.right])
    }

    func testAutoRevealIsWrittenInsidePanelLayoutInDeterministicOrder() {
        var state = UIState.defaults
        state.panelLayout = PanelLayout.defaults
            .settingAutoReveal(.right, true)
            .settingAutoReveal(.left, true)
        let panel = overlay(state)["panelLayout"] as? [String: Any]
        XCTAssertEqual(panel?["autoReveal"] as? [String], ["left", "right"])
    }

    // MARK: - Round-trip

    func testPanelLayoutRoundTripsThroughJSON() throws {
        var state = UIState.defaults
        state.panelLayout = PanelLayout.defaults
            .moving(.fileTree, to: .right, index: 1)
            .settingVisible(.right, true)
            .settingWidth(321.5, for: .left)
            .settingAutoReveal(.left, true)
        state.leftSidebarOpen = state.panelLayout!.isVisible(.left)
        state.rightSidebarOpen = state.panelLayout!.isVisible(.right)

        let data = try JSONSerialization.data(withJSONObject: overlay(state))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(decode(dict).panelLayout, state.panelLayout)
    }
}
