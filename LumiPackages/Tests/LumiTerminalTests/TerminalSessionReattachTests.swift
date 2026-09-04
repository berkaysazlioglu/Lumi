import AppKit
import Foundation
import LumiKit
import XCTest
@testable import LumiTerminal

/// design/00 Ek A §A.2-12 ZORUNLU entegrasyon testi:
/// "View yok edilir → PTY yaşar → reattach → PTY'ye sıfır istenmeyen byte".
///
/// Neden `/bin/cat`: cat (ve altındaki tty satır disiplini) PTY'ye yazılan her
/// byte'ı geri echo eder. Böylece "PTY'ye istenmeyen byte gitti mi?" sorusu iki
/// bağımsız yoldan ölçülür: (1) yazma hunisindeki `onPTYWrite` sayacı,
/// (2) emülatör buffer'ında beliren echo. Login shell kullanılsaydı prompt
/// çıktısı ölçümü kirletirdi.
@MainActor
final class TerminalSessionReattachTests: XCTestCase {
    /// Gecikmeli işlerin (150 ms resize debounce, ertelenmiş detach, coalescer
    /// flush) tamamlanması için pencere: en uzun iç sabitin 3 katı. "Olmamalı"
    /// assert'lerinde sabit uyku kaçınılmaz; marj sabitten türetilir.
    private static let settleWindow = Duration.seconds(TerminalSession.resizeDebounceInterval * 3)

    private static let containerFrame = NSRect(x: 0, y: 0, width: 400, height: 300)

    private func makeCatSession() throws -> TerminalSession {
        try TerminalSession(
            repoPath: FileManager.default.temporaryDirectory.path,
            name: "reattach-test",
            task: nil,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            executable: "/bin/cat",
            args: []
        )
    }

    /// `TerminalSessionManager.spawn` ile birebir aynı registry kablolaması
    /// (görünürlük → setHidden + requestRepaint, redraw → redrawFromBuffer).
    private func makeRegistry(for session: TerminalSession) -> TerminalViewRegistry {
        let registry = TerminalViewRegistry()
        registry.register(
            view: session.terminalView,
            for: session.id,
            onVisibilityChange: { [weak session] visible in
                session?.setHidden(!visible)
                if visible { session?.requestRepaint() }
            },
            onRedraw: { [weak session] in session?.redrawFromBuffer() }
        )
        return registry
    }

    private func pumpMainQueue(turns: Int = 3) async {
        for _ in 0 ..< turns {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @discardableResult
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Emülatörün görünür grid'i — PTY'den gelen echo buradan okunur.
    private func bufferText(_ session: TerminalSession) -> String {
        let terminal = session.terminalView.getTerminal()
        return (0 ..< terminal.rows)
            .compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
            .joined(separator: "\n")
    }

    // MARK: - §A.2-12: reattach PTY'ye hiçbir şey yazmaz

    func testAttachDetachReattachWritesNothingToPTY() async throws {
        // Arrange — gerçek PTY (/bin/cat) + kalıcı emülatör + registry
        let session = try makeCatSession()
        defer { session.terminate() }
        let writes = WriteRecorder()
        session.onPTYWrite = { writes.append($0) }
        let registry = makeRegistry(for: session)
        let container = NSView(frame: Self.containerFrame)
        // Bug-40'ın gerçek koşulu: agent CLI'si focus reporting'i (mode 1004)
        // açmış durumda. Böylece attach/detach'te SwiftTerm ESC[I/ESC[O üretmeye
        // aday olur; filtre olmasa bu byte'lar PTY'ye sızardı.
        let window = NSWindow(
            contentRect: Self.containerFrame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        session.terminalView.feed(byteArray: ArraySlice(Array("\u{1B}[?1004h".utf8)))

        // Act — tam yaşam döngüsü: attach → detach → attach → refresh → resize
        registry.attachView(for: session.id, into: container)
        window.makeFirstResponder(session.terminalView)
        await pumpMainQueue()

        registry.detachView(for: session.id, from: container)
        window.makeFirstResponder(nil) // view hierarchy'den çıkış → focus kaybı
        await pumpMainQueue()
        XCTAssertNil(session.terminalView.superview, "detach view'ı sökmedi")

        registry.attachView(for: session.id, into: container)
        window.makeFirstResponder(session.terminalView)
        await pumpMainQueue()
        XCTAssertTrue(session.terminalView.superview === container)

        registry.refreshAttachedViews()
        await pumpMainQueue()

        // Fit/resize yolu: container küçülür → SwiftTerm sizeChanged → PTY resize
        container.setFrameSize(NSSize(width: 320, height: 240))
        registry.attachView(for: session.id, into: container) // reassert (host layout'u)
        session.requestResize(cols: 90, rows: 25)
        try? await Task.sleep(for: Self.settleWindow)
        await pumpMainQueue()

        // Assert — kullanıcı girdisi yokken PTY'ye TEK byte bile yazılmadı
        XCTAssertEqual(
            writes.totalBytes,
            0,
            "reattach yolunda PTY'ye istenmeyen byte yazıldı: \(writes.debugDescription)"
        )
        // İkinci, bağımsız kanıt: cat hiçbir şey echo etmedi → emülatör boş
        XCTAssertTrue(
            bufferText(session).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "emülatörde beklenmedik echo var: \(bufferText(session))"
        )
    }

    /// Kontrol grubu + §A.2-9: emülatör oto-yanıtları gerçek yazma hunisinden
    /// geçer. Focus event'leri (`ESC[I`/`ESC[O`, mode 1004) KOŞULSUZ ayıklanır;
    /// aynı yoldan gelen gerçek tuş vuruşu ise PTY'ye ulaşır — yani yukarıdaki
    /// "sıfır byte" sonucu yazma yolunun ölü olmasından kaynaklanmıyor.
    func testFocusAutoResponsesAreFilteredWhileKeystrokesReachPTY() async throws {
        // Arrange
        let session = try makeCatSession()
        defer { session.terminate() }
        let writes = WriteRecorder()
        session.onPTYWrite = { writes.append($0) }
        let registry = makeRegistry(for: session)
        let container = NSView(frame: Self.containerFrame)
        registry.attachView(for: session.id, into: container)
        await pumpMainQueue()

        // Act — SwiftTerm'in oto-yanıt yolu: TerminalViewDelegate.send
        session.send(source: session.terminalView, data: ArraySlice(Array("\u{1B}[I".utf8)))
        session.send(source: session.terminalView, data: ArraySlice(Array("\u{1B}[O".utf8)))
        try? await Task.sleep(for: Self.settleWindow)

        // Assert — focus event'leri PTY'ye ulaşmadı
        XCTAssertEqual(writes.totalBytes, 0, "focus event'i PTY'ye sızdı: \(writes.debugDescription)")

        // Act — aynı yoldan gerçek tuş vuruşu
        session.send(source: session.terminalView, data: ArraySlice(Array("lumi-key\r".utf8)))

        // Assert — yazma yolu canlı: byte'lar PTY'ye ulaştı ve cat geri echo etti
        let keystrokeReached = await waitUntil { writes.totalBytes > 0 }
        XCTAssertTrue(
            keystrokeReached,
            "gerçek tuş vuruşu PTY'ye ulaşmadı — 'sıfır byte' sonucu anlamsızlaşır"
        )
        XCTAssertEqual(writes.joined, Data("lumi-key\r".utf8))
        let echoArrived = await waitUntil { self.bufferText(session).contains("lumi-key") }
        XCTAssertTrue(echoArrived, "cat echo'su emülatöre ulaşmadı: \(bufferText(session))")
    }

    /// "UI ölür → PTY yaşar → UI yeniden bağlanır": view hierarchy'den sökülmüşken
    /// PTY'den gelen çıktı yine emülatöre işlenir ve reattach sonrası ekranda olur.
    /// Replay/snapshot yoktur (design/01 §1) — kanıtı budur.
    func testOutputArrivingWhileDetachedSurvivesReattach() async throws {
        // Arrange
        let session = try makeCatSession()
        defer { session.terminate() }
        let registry = makeRegistry(for: session)
        let container = NSView(frame: Self.containerFrame)
        registry.attachView(for: session.id, into: container)
        await pumpMainQueue()

        // Act — view'ı sök (gizli terminal politikası: coalescing genişler)
        registry.detachView(for: session.id, from: container)
        await pumpMainQueue()
        XCTAssertNil(session.terminalView.superview)

        // Act — detach'liyken PTY'ye yazılan metin cat tarafından geri echo edilir
        let marker = "detached-marker-\(UUID().uuidString.prefix(8))"
        session.write(marker + "\r")

        // Assert — emülatör (view yokken bile) çıktıyı işledi
        let echoedWhileDetached = await waitUntil { self.bufferText(session).contains(marker) }
        XCTAssertTrue(
            echoedWhileDetached,
            "detach sırasında gelen PTY çıktısı emülatöre işlenmedi"
        )

        // Act — yeniden bağlan
        registry.attachView(for: session.id, into: container)
        await pumpMainQueue()

        // Assert — aynı emülatör, aynı içerik: view yok edilmedi, PTY yaşadı
        XCTAssertTrue(session.terminalView.superview === container)
        XCTAssertTrue(
            bufferText(session).contains(marker),
            "reattach sonrası emülatör içeriği kayboldu (view yok edilmiş olmalı)"
        )
    }
}

/// PTY'ye giden byte'ların thread-safe toplayıcısı (`onPTYWrite` io queue'da çağrılır).
private final class WriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    var totalBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    var joined: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    var debugDescription: String {
        String(decoding: joined, as: UTF8.self).debugDescription
    }
}
