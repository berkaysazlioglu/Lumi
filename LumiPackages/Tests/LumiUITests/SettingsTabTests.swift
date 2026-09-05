import Foundation
import XCTest
@testable import LumiUI

/// Settings sekmelerinin kaydı (Faz 7.3): "yeni sekme = 1 dosya + 1 case".
@MainActor
final class SettingsTabTests: XCTestCase {
    func testEveryTabHasStableIdentityIconAndTitle() {
        for tab in SettingsTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue)
            XCTAssertFalse(tab.icon.isEmpty, "\(tab) ikonsuz")
            XCTAssertFalse(tab.title.isEmpty, "\(tab) başlıksız")
        }
    }

    func testIdentifiersAreUnique() {
        let ids = SettingsTab.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testIconsAreUnique() {
        // Navigasyonda ikon tek ayırt edici işaret; tekrarı kullanıcıyı yanıltır.
        let icons = SettingsTab.allCases.map(\.icon)
        XCTAssertEqual(Set(icons).count, icons.count)
    }

    func testTabOrderIsTheDeclaredOne() {
        XCTAssertEqual(
            SettingsTab.allCases,
            [.general, .terminal, .appearance, .notifications, .session, .usage, .shortcuts]
        )
    }

    /// Her sekmenin gövdesi kendi `SettingsTabContent` birimidir ve hangi
    /// sekmeye ait olduğunu bilir — kayıt ile gövde ayrışmaz.
    func testEachTabContentDeclaresItsOwnTab() {
        XCTAssertEqual(GeneralSettingsTab.tab, .general)
        XCTAssertEqual(TerminalSettingsTab.tab, .terminal)
        XCTAssertEqual(AppearanceSettingsTab.tab, .appearance)
        XCTAssertEqual(NotificationsSettingsTab.tab, .notifications)
        XCTAssertEqual(SessionSettingsTab.tab, .session)
        XCTAssertEqual(UsageSettingsTab.tab, .usage)
        XCTAssertEqual(ShortcutsSettingsTab.tab, .shortcuts)
    }

    /// Her sekme dosyası ayrıdır ve makul boyutta kalır (820 satırlık
    /// `SettingsView`'a geri dönülmesin diye).
    func testEachTabLivesInItsOwnFileUnder200Lines() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LumiUI/Settings/Tabs")
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertEqual(files.count, SettingsTab.allCases.count)
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).count
            XCTAssertLessThanOrEqual(lines, 200, "\(file.lastPathComponent) çok büyüdü")
        }
    }

    /// Kabuk yalnız kompozisyondur.
    func testSettingsShellStaysSmall() throws {
        let shell = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LumiUI/Settings/SettingsShell.swift")
        let lines = try String(contentsOf: shell, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).count
        XCTAssertLessThanOrEqual(lines, 120)
    }
}
