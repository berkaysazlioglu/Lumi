import AppKit
import Foundation

/// Terminal alt sisteminin servis sınırı (design/02 §1).
/// Tek process'te UI-yüzlü servis @MainActor'da yaşar; PTY I/O implementasyonun
/// içindeki background queue'lardadır — bu protokol o detayı sızdırmaz.
@MainActor
public protocol TerminalServicing: AnyObject {
    /// Yeni login-shell PTY oturumu açar; `command` verilirse shell'e yazılır (PTY argv'si değil).
    /// Limit aşımında `LumiError.terminalLimitReached` fırlatır (karar 5 — sessiz null yok).
    @discardableResult
    func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta

    func write(id: TerminalID, text: String) throws
    func kill(id: TerminalID) throws
    func killAll()
    func resize(id: TerminalID, cols: Int, rows: Int)

    /// Tab seviyesi odak; eşleşen terminale onFocus, diğerlerine onBlur uygulanır (spec/10 §12).
    func setFocused(_ id: TerminalID?)
    /// Pencere seviyesi odak; tüm status makinelerine yayılır (spec/10 §12).
    func setWindowFocused(_ focused: Bool)

    /// Sıralı koleksiyon — Map-insertion-order tuzağına karşı (karar 11).
    var terminals: [TerminalMeta] { get }

    func setMaxTerminals(_ n: Int)
    func events() -> AsyncStream<TerminalEvent>
}

/// Canlı terminal NSView'larını UI'a köprüleyen sınır (design/00 §2).
/// LumiKit'te yaşar ki LumiUI, LumiTerminal'i import etmeden host edebilsin.
/// View'lar PTY ömrü boyunca registry'de retain edilir; SwiftUI re-render
/// hiçbir koşulda terminal state'ini yok edemez (design/03 §3).
@MainActor
public protocol TerminalViewProviding: AnyObject {
    /// Canlı terminal view'ını container'a reparent eder ve görünür/fit akışını tetikler.
    func attachView(for id: TerminalID, into container: NSView)
    /// View'ı hierarchy'den ayırır ama YOK ETMEZ; gizli-terminal politikası devreye girer.
    func detachView(for id: TerminalID)
}
