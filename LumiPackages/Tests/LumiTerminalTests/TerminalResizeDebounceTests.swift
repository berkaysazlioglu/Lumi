import AppKit
import Foundation
import XCTest
@testable import LumiTerminal

/// Resize debounce paritesi (design/01 §6): view tarafında 150 ms; pencere
/// sürüklenirken doğan onlarca `sizeChanged` tek `ioctl(TIOCSWINSZ)`'e iner
/// (her ioctl foreground process group'a SIGWINCH gönderir — TUI'yi spam'lemek
/// hem pahalı hem görsel olarak bozucudur).
@MainActor
final class TerminalResizeDebounceTests: XCTestCase {
    /// Debounce'un tamamlandığından emin olmak için beklenen pencere: sabitin
    /// 3 katı (magic number yok).
    private static let settleWindow = Duration.seconds(TerminalSession.resizeDebounceInterval * 3)

    /// /bin/cat: shell prompt'u ve init çıktısı olmadan canlı bir PTY.
    /// ioctl'ler enjekte edilen `PTYControlling` dekoratöründe sayılır (Faz 4.1).
    private func makeCatSession(recorder: PTYRecorder) throws -> TerminalSession {
        try TerminalSession(
            repoPath: FileManager.default.temporaryDirectory.path,
            name: "resize-test",
            task: nil,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            ptySpawner: RecordingPTYSpawner(executable: "/bin/cat", recorder: recorder)
        )
    }

    func testConsecutiveResizeRequestsCollapseIntoSingleIoctl() async throws {
        // Arrange
        let resizes = PTYRecorder()
        let session = try makeCatSession(recorder: resizes)
        defer { session.terminate() }

        // Act — pencere sürükleme burst'ü: debounce penceresi içinde 5 istek
        for offset in 0 ..< 5 {
            session.requestResize(cols: 100 + offset, rows: 30 + offset)
        }
        try? await Task.sleep(for: Self.settleWindow)

        // Assert — tek ioctl, SON boyutla
        XCTAssertEqual(resizes.resizeCount, 1, "debounce tutmadı: \(resizes.allResizes)")
        XCTAssertEqual(resizes.lastResize?.cols, 104)
        XCTAssertEqual(resizes.lastResize?.rows, 34)
    }

    func testResizeAfterDebounceWindowIsDeliveredSeparately() async throws {
        // Arrange
        let resizes = PTYRecorder()
        let session = try makeCatSession(recorder: resizes)
        defer { session.terminate() }

        // Act — iki ayrı burst, aralarında debounce penceresi kapanıyor
        session.requestResize(cols: 100, rows: 30)
        try? await Task.sleep(for: Self.settleWindow)
        session.requestResize(cols: 90, rows: 20)
        try? await Task.sleep(for: Self.settleWindow)

        // Assert — debounce susturmaz, yalnız birleştirir
        XCTAssertEqual(resizes.resizeCount, 2, "\(resizes.allResizes)")
        XCTAssertEqual(resizes.lastResize?.cols, 90)
        XCTAssertEqual(resizes.lastResize?.rows, 20)
    }

    func testZeroSizedResizeIsSkipped() async throws {
        // design/01 §6: cols/rows 0 ise atlanır (SwiftUI layout'u 0×0 verebilir).
        let resizes = PTYRecorder()
        let session = try makeCatSession(recorder: resizes)
        defer { session.terminate() }

        session.requestResize(cols: 0, rows: 24)
        session.requestResize(cols: 80, rows: 0)
        try? await Task.sleep(for: Self.settleWindow)

        XCTAssertEqual(resizes.resizeCount, 0, "geçersiz boyut PTY'ye iletildi: \(resizes.allResizes)")
    }
}
