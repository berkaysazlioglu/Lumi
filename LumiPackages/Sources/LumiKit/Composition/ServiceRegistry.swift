import Foundation

/// Servis grafiğinin tek erişim yüzü (refactor 3.2, design/00 §3).
///
/// Composition root somut tipleri yalnız `LiveServiceRegistry` içinde tanır;
/// `AppContainer` ve feature assembly'leri bu protokolü görür. Böylece bootstrap
/// sırası sözleşmesi tamamen fake bir grafikle test edilebilir
/// (`FakeServiceRegistry`) ve `LumiPaths.Mode` seçimi `#if DEBUG`'dan çıkıp
/// executable'ın girişine (`AppBootstrap`) taşınır.
@MainActor
public protocol ServiceRegistry: AnyObject {
    /// `~/.lumi` (prod) veya `~/.lumi-dev` (dev) çözümlemesi — karar 9.
    var paths: LumiPaths { get }

    var config: any ConfigServicing { get }
    var system: any SystemServicing { get }
    var repo: any RepoServicing { get }
    var git: any GitServicing { get }
    /// Plastic SCM yüzeyi (karar 45): okuma + checkin/undo.
    var plastic: any PlasticServicing { get }
    var agentHistory: any AgentHistoryReading { get }

    /// Oturum kontrolü + görünüm ayarı (ISP: `TerminalServicing` bileşimi).
    /// Somut `TerminalSessionManager` bu yüzeyin ARDINDA kalır.
    var terminal: any TerminalServicing { get }
    /// Canlı NSView köprüsü ayrı bir yüzdür (design/00 §2 sınır hilesi);
    /// terminal servisinin bir alanı olarak sızdırılmaz.
    var viewProvider: any TerminalViewProviding { get }

    /// FileViewer'ın sözdizimi vurgulayıcısı (refactor 7.5). Somut motor
    /// (`HighlightrEngine`, JSCore) LumiServices'te; kabuk yalnız protokolü görür.
    var highlighter: any SyntaxHighlighting { get }

    var notifications: any NotificationServicing { get }
    var sessionStarter: any SessionStarterServicing { get }
    var activityMonitor: any ActivityMonitoring { get }
    /// Karar 43: alt bar Resource Manager örnekleyicisi ve uyku engeli.
    var processSampler: any ProcessSampling { get }
    var sleepAssertion: any SleepAsserting { get }

    /// Sağlayıcı başına kullanım servisi (karar 32). Sözlük yerine fonksiyon:
    /// yeni sağlayıcı eklendiğinde çağıranlar `nil` ele almak zorunda kalmaz.
    func usage(for provider: AgentProvider) -> any UsageServicing
}
