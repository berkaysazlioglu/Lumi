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
    /// Opens a session with per-spawn environment overrides. Used by Codex
    /// cold restore to pin the thread to its original CODEX_HOME.
    @discardableResult
    func spawn(
        repoPath: String,
        task: String?,
        command: String?,
        environment: [String: String]
    ) throws -> TerminalMeta

    func write(id: TerminalID, text: String) throws
    func kill(id: TerminalID) throws
    /// PTY çocuk sürecinin pid'i (Resource Manager alt ağaç toplamı için);
    /// oturum yoksa ya da süreç bitmişse `nil`.
    func processID(for id: TerminalID) -> Int32?
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

    /// Karar 45: hook sunucusunun uç noktası. Sonraki spawn'ların PTY env'ine
    /// (`LUMI_AGENT_HOOK_*`) yazılır; `nil` = hook'lar kapalı, env eklenmez.
    func setAgentHookEndpoint(_ endpoint: AgentHookEndpoint?)
    /// Environment applied only to future sessions of a provider.
    func setLaunchEnvironment(_ environment: [String: String], for provider: AgentProvider)
    /// Karar 142: açık Claude modlarının klasörleri; sonraki spawn'ların
    /// `CLAUDE_CODE_PLUGIN_DIRS`'ine yazılır. Boş = değişken yazılmaz.
    func setClaudePluginDirectories(_ paths: [String])
    /// Karar 45: sunucudan gelen hook olayını ilgili oturumun durum
    /// makinesine iletir. Tanınmayan terminal kimliği sessizce düşer (kapanmış
    /// terminalin geç gelen hook'u).
    func applyAgentHookEvent(_ event: AgentHookEvent)

    func events() -> AsyncStream<TerminalEvent>

    // MARK: - Remote mirror

    /// Ham PTY bayt batch'leri — RemoteService uzak abone tüketicisi.
    /// Bilinmeyen id → boş/bitirilmiş stream.
    func subscribeOutput(_ id: TerminalID) -> AsyncStream<Data>

    /// Baytları PTY'ye yazar (mevcut input filter üzerinden). Bilinmeyen id → no-op.
    func writeInput(_ data: Data, to id: TerminalID)

    /// Tek atış scrollback snapshot: SwiftTerm buffer'ını UTF-8 Data olarak döker.
    /// Bilinmeyen id → (Data(), 0, 0).
    func serializeScrollback(_ id: TerminalID) -> (data: Data, cols: Int, rows: Int)

    /// Tek atış ekran durumu: boş bir emülatöre beslenince aynı ekranı kuran VT akışı
    /// (renkler, `\r\n`, alt-screen, modlar, imleç). Controller aynası kullanır
    /// (karar 143 ek); telefon düz `serializeScrollback`'te kalır.
    func serializeScreenState(_ id: TerminalID) -> (data: Data, cols: Int, rows: Int)

    /// Controller aynasının sıralı akışı (karar 143 ek): ilk öğe ekran durumu snapshot'ıdır,
    /// ardından canlı baytlar. Snapshot ile baytlar emülatörle aynı adımda üretildiği için
    /// arada kayıp/tekrar olmaz; emülatör boyut değiştirince yeni boyutta yeni snapshot gelir.
    /// Bilinmeyen id → boş/bitirilmiş stream.
    func subscribeScreenMirror(_ id: TerminalID) -> AsyncStream<TerminalMirrorEvent>

    /// "Yazan kazanır" (karar 143 ek): uzak yazarın ızgarası. Emülatör ve PTY bu ızgaraya
    /// geçer, yerel kart ızgarayı fontu ölçekleyerek gösterir. Yerelde tuşa basılınca ya da
    /// `clearRemoteGrid` ile yerel boyuta dönülür. Bilinmeyen id → no-op.
    func setRemoteGrid(_ id: TerminalID, grid: TerminalGrid)
    func clearRemoteGrid(_ id: TerminalID)

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
    /// Karar 57: düz tıkla açılan link eylemleri. Kapalıyken düz tık terminale
    /// aittir (seçim/caret); ⌘ / ⇧⌘ ile doğrudan açma etkilenmez.
    func applyLinkActions(enabled: Bool)
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

    /// Bekleyen klavye-odağı isteğini (servisin `setFocused`'ı) yerine getirmeyi
    /// dener: view bir pencereye ulaşmışsa first responder yapılır. Host container
    /// pencereye girdiğinde / layout aldığında çağırır — istek yoksa no-op.
    func fulfillPendingKeyboardFocus()
}

public extension TerminalViewProviding {
    func fulfillPendingKeyboardFocus() {}
}

public extension TerminalSessionControlling {
    /// Emülatörü olmayan implementasyonlar (fake'ler, önizleme) düz snapshot'a düşer.
    func serializeScreenState(_ id: TerminalID) -> (data: Data, cols: Int, rows: Int) {
        serializeScrollback(id)
    }

    func setRemoteGrid(_ id: TerminalID, grid: TerminalGrid) {}
    func clearRemoteGrid(_ id: TerminalID) {}

    /// Emülatörü olmayan implementasyonlar: snapshot + `subscribeOutput` (boyut olayı yok).
    func subscribeScreenMirror(_ id: TerminalID) -> AsyncStream<TerminalMirrorEvent> {
        let state = serializeScreenState(id)
        let output = subscribeOutput(id)
        return AsyncStream { continuation in
            continuation.yield(.snapshot(data: state.data, cols: state.cols, rows: state.rows))
            let task = Task {
                for await batch in output { continuation.yield(.output(batch)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Controller aynası akışının öğesi (`subscribeScreenMirror`).
public enum TerminalMirrorEvent: Sendable, Equatable {
    /// Boş bir emülatörü `cols×rows`'ta bu ekrana kuran VT akışı; ayna sıfırlanıp yeniden kurulur.
    case snapshot(data: Data, cols: Int, rows: Int)
    /// Snapshot'tan sonraki ham PTY baytları.
    case output(Data)
}
