import Foundation
import LumiKit
import UserNotifications

/// Gerçek OS bildirimleri (spec/13 §4.3 + UN izin akışı — yeni gereksinim).
/// UNUserNotificationCenter bundle'lı app gerektirir; `swift run` ile koşan
/// bundle'sız süreçte kullanılamaz — seçim composition root'ta yapılır.
final class UNNotificationPresenter: NSObject, NotificationPresenting {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Bildirim tıklaması → terminal odaklama köprüsü (minimize istisnası
    /// store'da restoreAndFocus ile işler).
    nonisolated(unsafe) var onClick: (@MainActor (TerminalID) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert])) ?? false
    }

    @MainActor
    func present(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // silent: true paritesi — ses yok (spec/13 §4.3)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    func removeDelivered(id: String) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [id])
    }
}

extension UNNotificationPresenter: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        if let uuid = UUID(uuidString: identifier) {
            let terminalID = TerminalID(raw: uuid)
            Task { @MainActor [onClick] in
                onClick?(terminalID)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
