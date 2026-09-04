import AppKit
import Foundation
import LumiKit

/// `TerminalServicing` fake'i (design/00 §3 test ikamesi deseni).
/// Tüm çağrılar kaydedilir; `failSpawns`/`failWrites` bayrakları hata yollarını
/// (karar 5: sessiz yutma yok) sürmek için ayrı bir sınıfa gerek bırakmaz.
@MainActor
public final class FakeTerminalService: TerminalServicing {
    private let broadcaster = EventBroadcaster<TerminalEvent>()

    // MARK: Ayarlanabilir davranış
    /// Açıkken `spawn` `.spawnFailed` fırlatır.
    public var failSpawns = false
    /// Açıkken `write` `.terminalNotFound` fırlatır (yazım kaydedilmez, deneme sayılır).
    public var failWrites = false
    /// Açıkken `kill` `.terminalNotFound` fırlatır.
    public var failKills = false

    // MARK: Çağrı kaydı
    public private(set) var spawnedMetas: [TerminalMeta] = []
    public private(set) var spawnAttempts = 0
    public private(set) var killedIDs: [TerminalID] = []
    public private(set) var killAllCount = 0
    public private(set) var shutdownCount = 0
    public private(set) var focusCalls: [TerminalID?] = []
    public private(set) var windowFocusCalls: [Bool] = []
    public private(set) var resizeCalls: [(id: TerminalID, cols: Int, rows: Int)] = []
    public private(set) var writtenTexts: [(id: TerminalID, text: String)] = []
    public private(set) var writeAttempts = 0
    public private(set) var appliedFonts: [NSFont] = []
    public private(set) var appliedCursors: [(shape: TerminalCursorShape, blink: Bool)] = []

    public init() {}

    public var terminals: [TerminalMeta] { spawnedMetas }

    @discardableResult
    public func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        spawnAttempts += 1
        if failSpawns { throw LumiError.spawnFailed(reason: "fake") }
        let meta = TerminalMeta(
            id: TerminalID(),
            name: "Terminal \(spawnedMetas.count + 1)",
            repoPath: repoPath,
            createdAt: Date(),
            task: task
        )
        spawnedMetas.append(meta)
        broadcaster.send(.spawned(meta))
        return meta
    }

    public func write(id: TerminalID, text: String) throws {
        writeAttempts += 1
        if failWrites { throw LumiError.terminalNotFound(id) }
        writtenTexts.append((id, text))
    }

    public func kill(id: TerminalID) throws {
        if failKills { throw LumiError.terminalNotFound(id) }
        killedIDs.append(id)
    }

    public func killAll() {
        killAllCount += 1
    }

    /// Gerçek servis global NSEvent monitörlerini bırakır; fake yalnız sayar.
    public func shutdown() {
        shutdownCount += 1
    }

    public func resize(id: TerminalID, cols: Int, rows: Int) {
        resizeCalls.append((id, cols, rows))
    }

    public func setFocused(_ id: TerminalID?) {
        focusCalls.append(id)
    }

    public func setWindowFocused(_ focused: Bool) {
        windowFocusCalls.append(focused)
    }

    // MARK: TerminalAppearanceControlling

    public func applyFont(_ font: NSFont) {
        appliedFonts.append(font)
    }

    public func applyCursor(shape: TerminalCursorShape, blink: Bool) {
        appliedCursors.append((shape, blink))
    }

    public func events() -> AsyncStream<TerminalEvent> {
        broadcaster.stream()
    }

    /// Testin senaryo event'i itmesi için.
    public func emit(_ event: TerminalEvent) {
        broadcaster.send(event)
    }
}
