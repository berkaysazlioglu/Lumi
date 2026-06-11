import Foundation
import LumiKit

/// Skeleton bildirimleri: UNUserNotificationCenter bundle'lı app gerektirir
/// (SPM executable'da çöker) — gerçek presenter Faz 6'da app target'a gelir.
/// Bu presenter zamanlama/guard mantığının uçtan uca koşmasını sağlar, sunumu
/// stderr'e loglar.
struct LogNotificationPresenter: NotificationPresenting {
    func requestAuthorization() async -> Bool {
        true
    }

    @MainActor
    func present(id: String, title: String, body: String) {
        fputs("[lumi-notify] \(title): \(body) (terminal \(id.prefix(8)))\n", stderr)
    }

    @MainActor
    func removeDelivered(id: String) {}
}
