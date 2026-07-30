import LumiKit
import XCTest
@testable import LumiTerminal

/// Gerçek PTY + view-attached SwiftTerm oturumuyla screenSnapshot yolunun
/// uçtan uca doğrulaması — remote dashboard'un gördüğü gerçek veri budur.
@MainActor
final class ScreenSnapshotIntegrationTests: XCTestCase {
    func testRealSessionSnapshotContainsColoredOutput() async throws {
        let manager = TerminalSessionManager()
        // %s'ler boş string'le doldurulur: çıktı "KIRMIZI"/"KALIN" içerir ama
        // shell'in echo'ladığı komut satırı içermez — assert'ler yalnız gerçek
        // çıktıyı yakalar.
        let meta = try manager.spawn(
            repoPath: NSTemporaryDirectory(),
            task: nil,
            command: "printf 'DUZ metin \\033[31mKIR%sMIZI\\033[0m \\033[1mKAL%sIN\\033[0m son\\n' '' ''"
        )
        defer { manager.killAll() }

        // Çıktının PTY → pipeline → MainActor feed turunu tamamlamasını bekle
        let deadline = Date().addingTimeInterval(10)
        var snapshot: TerminalScreenSnapshot?
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            snapshot = manager.screenSnapshot(id: meta.id)
            let flat = snapshot.map { snap in
                snap.screen.flatMap { $0 }.map(\.text).joined() + snap.history
            } ?? ""
            if flat.contains("KIRMIZI") { break }
        }

        let resolved = try XCTUnwrap(snapshot)
        let allRuns = resolved.screen.flatMap { $0 }
        let flatText = allRuns.map(\.text).joined() + resolved.history
        XCTAssertTrue(
            flatText.contains("KIRMIZI"),
            "snapshot çıktıyı içermiyor — screen: \(resolved.screen.prefix(5)), history: \(resolved.history.prefix(400))"
        )

        let redRun = allRuns.first { $0.text.contains("KIRMIZI") }
        XCTAssertNotNil(redRun?.foreground, "KIRMIZI koşusunun rengi yok: \(String(describing: redRun))")

        let boldRun = allRuns.first { $0.text.contains("KALIN") }
        XCTAssertEqual(
            (boldRun?.flags ?? 0) & TerminalRunFlag.bold, TerminalRunFlag.bold,
            "KALIN koşusu bold değil: \(String(describing: boldRun))"
        )
    }
}
