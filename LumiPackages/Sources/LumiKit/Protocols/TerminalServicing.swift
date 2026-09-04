import AppKit
import Foundation

/// Terminal oturum yaşam döngüsü + I/O sınırı (design/02 §1).
/// Tek process'te UI-yüzlü servis @MainActor'da yaşar; PTY I/O implementasyonun
/// içindeki background queue'lardadır — bu protokol o detayı sızdırmaz.
///
/// ISP (Faz 3.7): oturum kontrolü ile görünüm ayarı ayrı yüzlerdir. Store'lar
/// yalnız bu yüzü alır; görünüm ayarını yalnız composition root uygular.
@MainActor
public protocol TerminalSessionControlling: AnyObject, Sendable {
    /// Yeni login-shell PTY oturumu açar; `command` verilirse shell'e yazılır (PTY argv'si değil).
    @discardableResult
    func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta

    func write(id: TerminalID, text: String) throws
    func kill(id: TerminalID) throws
    func killAll()
    func resize(id: TerminalID, cols: Int, rows: Int)

    /// Tab seviyesi odak; eşleşen terminale onFocus, diğerlerine onBlur uygulanır.
    func setFocused(_ id: TerminalID?)
    /// Pencere seviyesi odak; tüm status makinelerine yayılır.
    func setWindowFocused(_ focused: Bool)

    /// Tek terminalin yüzey durumu (Faz 4.3). Görünürlük politikası (coalescer
    /// aralığı) ve odak (`statusMachine.onFocus/onBlur`) TEK atomik geçişte
    /// uygulanır — ikisi ayrı kanaldan aktığında ekranda olmayan terminal
    /// `focused` kalıyordu. Odak state'inin otoritesi servistir: `.foreground`
    /// yalnız o an `setFocused` ile seçili terminale odak geri verir.
    func setSurfaceState(_ state: TerminalSurfaceState, for id: TerminalID)

    /// Toplu yüzey geçişi (route/tab değişimi). `repoPath == nil` ⇒ tüm
    /// terminaller.
    func setSurfaceState(_ state: TerminalSurfaceState, in repoPath: String?)

    /// Sıralı koleksiyon — Map-insertion-order tuzağına karşı (karar 11).
    var terminals: [TerminalMeta] { get }

    func events() -> AsyncStream<TerminalEvent>

    /// Kapanış simetrisi: global NSEvent monitörleri gibi process-ömürlü
    /// kaynakları bırakır. Idempotent'tir; composition root `shutdown()`
    /// yolunda çağırır (refactor 3.2 — somut tipe inmemek için protokolde).
    func shutdown()
}

/// Terminal görünüm ayarlarının canlı uygulanması (Settings → font/cursor).
/// Ayrı yüz: store'lar bunu görmez, yalnız config yan etkisini süren
/// composition root çağırır.
///
/// Font `NSFont` olarak geçer (aile+boyut primitifleri değil): aile→font
/// çözümlemesi (bundle'daki JetBrains Mono fallback'i dahil) `LumiFonts`'ta,
/// yani kaynak bundle'ının sahibi olan LumiUI'da yaşar. Primitif imza,
/// LumiTerminal'de o çözümlemenin ikinci bir kopyasını doğururdu (DRY).
/// Cursor ise tersine primitiftir: `TerminalCursorShape` LumiKit'te,
/// SwiftTerm `CursorStyle`'a çeviri implementasyonun içindedir.
@MainActor
public protocol TerminalAppearanceControlling: AnyObject, Sendable {
    /// Font'u canlı tüm oturumlara uygular ve sonraki spawn'lara devreder.
    func applyFont(_ font: NSFont)
    /// Caret şekli + blink'i canlı tüm oturumlara uygular ve sonraki spawn'lara devreder.
    func applyCursor(shape: TerminalCursorShape, blink: Bool)
}

/// Terminal servisinin tam yüzü. Geriye uyumluluk + "her ikisini de uygulayan"
/// somut tipi adlandırmak için (design/00 §3 container şeması).
public typealias TerminalServicing = TerminalSessionControlling & TerminalAppearanceControlling

/// Canlı terminal NSView'larını UI'a köprüleyen sınır (design/00 §2).
/// LumiKit'te yaşar ki LumiUI, LumiTerminal'i import etmeden host edebilsin.
/// View'lar PTY ömrü boyunca registry'de retain edilir; SwiftUI re-render
/// hiçbir koşulda terminal state'ini yok edemez (design/03 §3).
@MainActor
public protocol TerminalViewProviding: AnyObject {
    /// Canlı terminal view'ını container'a reparent eder ve görünür/fit akışını tetikler.
    func attachView(for id: TerminalID, into container: NSView)
    /// View'ı verilen container'dan ayırır ama YOK ETMEZ; gizli-terminal politikası
    /// devreye girer. `container` parametresi bayat-detach koruması içindir: view
    /// başka bir host'a taşınmışsa (SwiftUI reparenting yarışı) bu çağrı no-op olur.
    func detachView(for id: TerminalID, from container: NSView)
    /// Terminalin canlı view'ı şu an bir container'a bağlı mı (Faz 4.4).
    /// Route geçişlerinde "zaten ayrılmış mı" kararını çağıran, SwiftUI'nin
    /// dismantle zamanlamasını tahmin etmeden verebilsin diye.
    func isAttached(_ id: TerminalID) -> Bool

    /// Bağlı TÜM view'ları tek çağrıda ayırır (Faz 4.4): route değişiminde
    /// SwiftUI dismantle sırasına güvenmek yerine açık, senkron bir kapanış.
    /// Her view için `onVisibilityChange(false)` akar; view'lar YOK EDİLMEZ.
    func detachAll()

    /// Bağlı tüm view'ları superview bounds'una yeniden oturtur ve redraw ister.
    /// Fullscreen giriş/çıkışı gibi AppKit'in view hiyerarşisini taşıdığı
    /// geçişlerin onarımı — çağıran somut registry tipini tanımak zorunda kalmaz.
    func refreshAttachedViews()
}
