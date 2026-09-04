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

    private func makeCatSession() throws -> TerminalSession {
        // /bin/cat: shell prompt'u ve init çıktısı olmadan canlı bir PTY.
        try TerminalSession(
            repoPath: FileManager.default.temporaryDirectory.path,
            name: "resize-test",
            task: nil,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            executable: "/bin/cat",
            args: []
        )
    }

    func testConsecutiveResizeRequestsCollapseIntoSingleIoctl() async throws {
        // Arrange
        let session = try makeCatSession()
        defer { session.terminate() }
        let resizes = ResizeRecorder()
        session.onPTYResize = { resizes.append(cols: $0, rows: $1) }

        // Act — pencere sürükleme burst'ü: debounce penceresi içinde 5 istek
        for offset in 0 ..< 5 {
            session.requestResize(cols: 100 + offset, rows: 30 + offset)
        }
        try? await Task.sleep(for: Self.settleWindow)

        // Assert — tek ioctl, SON boyutla
        XCTAssertEqual(resizes.count, 1, "debounce tutmadı: \(resizes.all)")
        XCTAssertEqual(resizes.last?.cols, 104)
        XCTAssertEqual(resizes.last?.rows, 34)
    }

    func testResizeAfterDebounceWindowIsDeliveredSeparately() async throws {
        // Arrange
        let session = try makeCatSession()
        defer { session.terminate() }
        let resizes = ResizeRecorder()
        session.onPTYResize = { resizes.append(cols: $0, rows: $1) }

        // Act — iki ayrı burst, aralarında debounce penceresi kapanıyor
        session.requestResize(cols: 100, rows: 30)
        try? await Task.sleep(for: Self.settleWindow)
        session.requestResize(cols: 90, rows: 20)
        try? await Task.sleep(for: Self.settleWindow)

        // Assert — debounce susturmaz, yalnız birleştirir
        XCTAssertEqual(resizes.count, 2, "\(resizes.all)")
        XCTAssertEqual(resizes.last?.cols, 90)
        XCTAssertEqual(resizes.last?.rows, 20)
    }

    func testZeroSizedResizeIsSkipped() async throws {
        // design/01 §6: cols/rows 0 ise atlanır (SwiftUI layout'u 0×0 verebilir).
        let session = try makeCatSession()
        defer { session.terminate() }
        let resizes = ResizeRecorder()
        session.onPTYResize = { resizes.append(cols: $0, rows: $1) }

        session.requestResize(cols: 0, rows: 24)
        session.requestResize(cols: 80, rows: 0)
        try? await Task.sleep(for: Self.settleWindow)

        XCTAssertEqual(resizes.count, 0, "geçersiz boyut PTY'ye iletildi: \(resizes.all)")
    }
}

/// `onPTYResize` io queue'da çağrılır; toplayıcı thread-safe olmalı.
private final class ResizeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(cols: UInt16, rows: UInt16)] = []

    func append(cols: UInt16, rows: UInt16) {
        lock.lock()
        storage.append((cols, rows))
        lock.unlock()
    }

    var all: [(cols: UInt16, rows: UInt16)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var count: Int { all.count }
    var last: (cols: UInt16, rows: UInt16)? { all.last }
}
