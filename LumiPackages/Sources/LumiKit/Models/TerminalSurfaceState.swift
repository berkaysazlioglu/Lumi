/// Bir terminalin UI yüzeyindeki durumu (design/01 §3, refactor Faz 4.3).
///
/// Görünürlük ve odak, Faz 4.3'ten önce iki bağımsız kanaldı: registry
/// attach/detach yalnız coalescer aralığını değiştiriyor, `setFocused` ise
/// yalnız durum makinesine dokunuyordu. Orta alan başka bir görünüme geçtiğinde
/// (Tasks) terminal ekranda olmadığı hâlde `focused` kalıyor ve `waitingUnseen`
/// yerine `waitingFocused`'a çıkıyordu — yanlış rozet, yanlış bildirim ve karar
/// 24 auto-minimize'ının bozulması. Bu tip iki kanalı TEK atomik geçişte
/// birleştirir.
///
/// - `foreground`: ekranda ve çizilebilir (coalescer 16 ms). Odak ayrıdır:
///   foreground olmak odak KAZANDIRMAZ — odağın otoritesi servistir.
/// - `background`: canlı ama görünmüyor (route değişimi, başka tab). Emülatör
///   beslenmeye devam eder, aralık 100 ms'e genişler, durum makinesi blur alır.
/// - `minimized`: kullanıcı (ya da karar 24) kartı gizledi. Bugün `background`
///   ile aynı akış politikasını paylaşır; ayrı case, niyeti kaybetmemek ve
///   ileride farklı politika (örn. daha agresif tahliye) uygulayabilmek içindir.
public enum TerminalSurfaceState: Sendable, Equatable {
    case foreground
    case background
    case minimized

    /// Akış politikası: yalnız foreground "görünür" sayılır (16 ms aralık).
    public var isVisible: Bool { self == .foreground }
}
