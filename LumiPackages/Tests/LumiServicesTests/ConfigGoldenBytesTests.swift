import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// **Byte-byte format kilidi** (karar 9). `ConfigCodec` bölündüğünde (refactor
/// 5.7) diske yazılan metnin TEK bir baytı bile değişmemeli: anahtar sırası
/// (`.sortedKeys`), girinti (`.prettyPrinted`), `/` kaçışsızlığı
/// (`.withoutEscapingSlashes`), tam sayı biçimi (580, 580.0 değil) ve bilinmeyen
/// anahtarların korunması dahil.
///
/// Diğer golden testler alan-alan bakar; bu test dosyanın TAMAMINA bakar.
final class ConfigGoldenBytesTests: XCTestCase {
    private var tempHome: URL!
    private var paths: LumiPaths!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-golden-\(UUID().uuidString)")
        paths = LumiPaths(mode: .development, homeDirectory: tempHome)
        try paths.ensureDirectoriesExist()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
        try super.tearDownWithError()
    }

    /// Bilinmeyen/legacy anahtarlar (`maxTerminals`, `activeView`, `gridColumns`)
    /// dahil gerçek Electron çıktısı.
    private let configFixture = """
    {
      "projectsRoot": "/Users/dev/wkspaces/Unity",
      "aiProvider": "claude",
      "maxTerminals": 12,
      "theme": "dark",
      "terminalFontSize": 13
    }
    """

    private let uiStateFixture = """
    {
      "openTabs": [],
      "activeTab": null,
      "leftSidebarOpen": true,
      "rightSidebarOpen": false,
      "gridColumns": "auto",
      "activeView": "terminals",
      "windowMaximized": false
    }
    """

    func testConfigFileBytesAreStable() async throws {
        try configFixture.write(to: paths.configFile, atomically: true, encoding: .utf8)
        let service = ConfigService(paths: paths, writeDebounce: .zero)
        try await service.updateConfig { config in
            config.projectsRoot = "/Users/dev/wkspaces/Unity"
            config.additionalPaths = [
                AdditionalPath(id: "id-1", path: "/Users/dev/extra", type: .root, label: "Extra"),
                AdditionalPath(id: "id-2", path: "/Users/dev/solo", type: .repo),
            ]
            config.aiProvider = .codex
            config.theme = "light"
            config.terminalFontSize = 17
            config.terminalFontFamily = "Menlo"
            config.terminalCursorStyle = "bar"
            config.terminalCursorBlink = false
            config.notifications = NotificationSettings(
                unseenEnabled: false, unseenIntervalMinutes: 7,
                seenEnabled: false, seenIntervalMinutes: 11
            )
            config.autoMinimizeOnSend = true
            config.sessionTrigger = SessionTrigger(enabled: true, hour: 22, minute: 45, prompt: "go")
            config.usageAutoRefresh = UsageAutoRefresh(enabled: true, intervalMinutes: 5)
            config.usageIndicators = UsageIndicators(claude: false, codex: true)
        }

        let text = try String(contentsOf: paths.configFile, encoding: .utf8)
        XCTAssertEqual(text, Self.expectedConfigJSON)
    }

    func testUIStateFileBytesAreStable() async throws {
        try uiStateFixture.write(to: paths.uiStateFile, atomically: true, encoding: .utf8)
        let service = ConfigService(paths: paths, writeDebounce: .zero)
        await service.updateUIState { state in
            state.openTabs = ["/r/alpha", "/r/beta"]
            state.activeTab = "/r/beta"
            state.leftSidebarOpen = false
            state.rightSidebarOpen = true
            state.projectGridLayouts = [
                "/r/alpha": GridLayout(mode: .columns, count: 3, heightMode: .fit, heightRatio: .third),
            ]
            state.windowBounds = WindowBounds(x: 580, y: 214.5, width: 1400, height: 900)
            state.windowMaximized = true
            state.resumeSessions = [ResumeSession(repoPath: "/r/alpha", sessionID: "s-1")]
            state.activeRoute = "tasks"
            // K34 (additive): iki yeni anahtar — `panelLayout` + `visibleSlots`.
            // Eski `leftSidebarOpen`/`rightSidebarOpen` PROJEKSİYON olarak
            // yazılmaya devam eder (yukarıda set edildi).
            state.panelLayout = PanelLayout.defaults
                .moving(.projectTools, to: .right, index: 0)
                .settingVisible(.left, false)
                .settingVisible(.right, true)
                .settingWidth(320, for: .right)
        }
        await service.flushPendingWrites()

        let text = try String(contentsOf: paths.uiStateFile, encoding: .utf8)
        XCTAssertEqual(text, Self.expectedUIStateJSON)
    }

    private static let expectedConfigJSON = """
    {
      "additionalPaths" : [
        {
          "id" : "id-1",
          "label" : "Extra",
          "path" : "/Users/dev/extra",
          "type" : "root"
        },
        {
          "id" : "id-2",
          "path" : "/Users/dev/solo",
          "type" : "repo"
        }
      ],
      "aiProvider" : "codex",
      "autoMinimizeOnSend" : true,
      "maxTerminals" : 12,
      "notifications" : {
        "seenEnabled" : false,
        "seenIntervalMinutes" : 11,
        "unseenEnabled" : false,
        "unseenIntervalMinutes" : 7
      },
      "projectsRoot" : "/Users/dev/wkspaces/Unity",
      "sessionTrigger" : {
        "enabled" : true,
        "hour" : 22,
        "minute" : 45,
        "prompt" : "go"
      },
      "terminalCursorBlink" : false,
      "terminalCursorStyle" : "bar",
      "terminalFontFamily" : "Menlo",
      "terminalFontSize" : 17,
      "theme" : "light",
      "usageAutoRefresh" : {
        "enabled" : true,
        "intervalMinutes" : 5
      },
      "usageIndicators" : {
        "claude" : false,
        "codex" : true
      }
    }
    """
    private static let expectedUIStateJSON = """
    {
      "activeRoute" : "tasks",
      "activeTab" : "/r/beta",
      "activeView" : "terminals",
      "gridColumns" : "auto",
      "leftSidebarOpen" : false,
      "openTabs" : [
        "/r/alpha",
        "/r/beta"
      ],
      "panelLayout" : {
        "slots" : {
          "bottom" : [

          ],
          "left" : [
            "sessions"
          ],
          "right" : [
            "projectTools"
          ]
        },
        "widths" : {
          "bottom" : 280,
          "left" : 280,
          "right" : 320
        }
      },
      "projectGridLayouts" : {
        "/r/alpha" : {
          "count" : 3,
          "heightMode" : "fit",
          "heightRatio" : "third",
          "mode" : "columns"
        }
      },
      "resumeSessions" : [
        {
          "repoPath" : "/r/alpha",
          "sessionID" : "s-1"
        }
      ],
      "rightSidebarOpen" : true,
      "visibleSlots" : [
        "right"
      ],
      "windowBounds" : {
        "height" : 900,
        "width" : 1400,
        "x" : 580,
        "y" : 214.5
      },
      "windowMaximized" : true
    }
    """
}
