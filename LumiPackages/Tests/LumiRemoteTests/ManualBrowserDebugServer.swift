import LumiKit
import XCTest
@testable import LumiRemote

/// Elle tarayıcı debug'ı için kısa ömürlü sunucu — yalnız LUMI_SERVE_DEBUG=1
/// ortam değişkeniyle çalışır, normal test koşusunda atlanır.
final class ManualBrowserDebugServer: XCTestCase {
    @MainActor
    func testServeForBrowserDebug() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMI_SERVE_DEBUG"] == "1",
            "yalnız elle debug için"
        )
        let terminalID = "11111111-1111-1111-1111-111111111111"
        let screen: [[TerminalScreenRun]] = [
            [
                TerminalScreenRun(text: "● ", foreground: "#7c6cf0"),
                TerminalScreenRun(text: "Claude Code çalışıyor", flags: 1),
            ],
            [],
            [
                TerminalScreenRun(text: "  src/main.swift", foreground: "#3fb950"),
                TerminalScreenRun(text: "  +42 -7", foreground: "#f5a623", flags: 8),
            ],
            [TerminalScreenRun(text: "❯ ", foreground: "#e5484d"), TerminalScreenRun(text: "onay bekliyor")],
        ]
        let snapshot = TerminalScreenSnapshot(
            history: (1...60).map { "geçmiş satırı \($0)" }.joined(separator: "\n"),
            screen: screen
        )
        let provider = FakeRemoteProvider(
            summaries: [makeSummary(id: terminalID)],
            screens: [terminalID: snapshot]
        )
        let server = RemoteDashboardServer(provider: provider, port: 58486)
        try await server.start()
        print("DEBUG SERVER: http://127.0.0.1:58486 — 120 sn açık")
        try await Task.sleep(for: .seconds(120))
        await server.stop()
    }
}
