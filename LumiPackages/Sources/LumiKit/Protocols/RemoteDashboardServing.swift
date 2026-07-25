import Foundation

/// Remote dashboard sunucusunun anlık durumu — UI popover'ı bu değerden çizilir.
public struct RemoteDashboardStatus: Sendable, Equatable {
    public let isRunning: Bool
    /// Yerel ağdan erişim adresi, ör. `http://192.168.1.20:8484` (yalnız çalışırken).
    public let url: String?

    public init(isRunning: Bool, url: String?) {
        self.isRunning = isRunning
        self.url = url
    }

    public static let stopped = RemoteDashboardStatus(isRunning: false, url: nil)
}

/// Yerel ağ dashboard sunucusunun servis sınırı (design/06). Kullanıcı
/// topbar popover'ından açıp kapatır; uygulama açılışında OTOMATİK BAŞLAMAZ.
/// Implementasyon LumiRemote'ta yaşar; LumiState yalnız bu protokolü görür.
@MainActor
public protocol RemoteDashboardServing: AnyObject, Sendable {
    var status: RemoteDashboardStatus { get }

    /// Sunucuyu başlatır; port kullanımda vb. durumda `LumiError.remoteDashboardFailed`
    /// fırlatır (karar 5 — sessiz başarısızlık yok).
    func start() async throws

    func stop() async
}
