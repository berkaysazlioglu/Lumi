import Foundation
import LumiKit

/// Topbar remote-dashboard popover'ının durumu (design/06). Sunucu yaşam
/// döngüsü tamamen kullanıcı eylemiyle sürülür; otomatik başlatma yoktur.
@Observable
@MainActor
public final class RemoteDashboardStore {
    public private(set) var isRunning = false
    public private(set) var url: String?
    /// start/stop devam ederken buton kilitlenir (çift tıklama yarışı olmaz).
    public private(set) var isBusy = false

    @ObservationIgnored private let server: any RemoteDashboardServing
    @ObservationIgnored private let toasts: ToastStore

    public init(server: any RemoteDashboardServing, toasts: ToastStore) {
        self.server = server
        self.toasts = toasts
    }

    public func toggle() {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            if self.isRunning {
                await self.server.stop()
            } else {
                do {
                    try await self.server.start()
                } catch let error as LumiError {
                    self.toasts.show(error: error)
                } catch {
                    self.toasts.show(error: .remoteDashboardFailed(
                        detail: error.localizedDescription
                    ))
                }
            }
            self.sync()
        }
    }

    /// Uygulama kapanışında sunucuyu düşür (AppContainer.shutdown).
    public func shutdown() async {
        await server.stop()
        sync()
    }

    private func sync() {
        let status = server.status
        isRunning = status.isRunning
        url = status.url
    }
}
