import Foundation
import LumiKit

/// Status-makinesi-güdümlü bildirim servisi (spec/13 §4 tablosu birebir):
///
/// | Status           | Bildirim                  | Tekrar                  |
/// |------------------|---------------------------|-------------------------|
/// | waiting-unseen   | anında "waiting for input"| unseenIntervalMinutes   |
/// | waiting-seen     | yok                       | seenIntervalMinutes     |
/// | error            | tek seferlik              | yok                     |
/// | diğerleri        | yok                       | interval temizlenir     |
///
/// Her geçiş önce mevcut interval'i temizler (terminal başına en fazla bir).
/// Focus guard: native OS bildirimi yalnız pencere odaklı DEĞİLKEN; bell
/// toast sinyali her durumda gönderilir.
public final class NotificationService: NotificationServicing {
    public static let waitingBody = "Assistant waiting for input"
    public static let errorBody = "Assistant exited with error"

    private let presenter: any NotificationPresenting
    private let scheduler: any RepeatingScheduling
    private let broadcaster = EventBroadcaster<NotificationEvent>()
    private var settings: NotificationSettings
    private var windowFocused = true
    private var permissionRequested = false

    public init(
        presenter: any NotificationPresenting,
        settings: NotificationSettings = .defaults
    ) {
        self.presenter = presenter
        self.scheduler = TimerRepeatingScheduler()
        self.settings = settings
    }

    init(
        presenter: any NotificationPresenting,
        scheduler: any RepeatingScheduling,
        settings: NotificationSettings = .defaults
    ) {
        self.presenter = presenter
        self.scheduler = scheduler
        self.settings = settings
    }

    public func requestPermissionIfNeeded() async {
        guard !permissionRequested else { return }
        permissionRequested = true
        _ = await presenter.requestAuthorization()
    }

    public func updateSettings(_ settings: NotificationSettings) {
        self.settings = settings
    }

    public func setWindowFocused(_ focused: Bool) {
        windowFocused = focused
    }

    public func handleStatusChange(id: TerminalID, repoName: String, status: TerminalStatus) {
        // Her geçiş mevcut interval'i temizler (terminal başına en fazla bir)
        scheduler.cancel(id: id.description)

        switch status {
        case .waitingUnseen:
            broadcaster.send(.bell(id, repoName: repoName))
            guard settings.unseenEnabled else { return }
            deliver(id: id, title: repoName, body: Self.waitingBody)
            scheduleRepeat(id: id, repoName: repoName, minutes: settings.unseenIntervalMinutes, body: Self.waitingBody)

        case .waitingSeen:
            guard settings.seenEnabled else { return }
            scheduleRepeat(id: id, repoName: repoName, minutes: settings.seenIntervalMinutes, body: Self.waitingBody)

        case .error:
            broadcaster.send(.bell(id, repoName: repoName))
            deliver(id: id, title: repoName, body: Self.errorBody)

        case .working, .idle, .waitingFocused:
            break // yalnız interval temizliği
        }
    }

    public func terminalRemoved(_ id: TerminalID) {
        scheduler.cancel(id: id.description)
        presenter.removeDelivered(id: id.description)
    }

    public func events() -> AsyncStream<NotificationEvent> {
        broadcaster.stream()
    }

    /// Bildirim tıklaması köprüsü — presenter implementasyonu (app target)
    /// tıklamayı buraya iletir.
    public func notificationClicked(terminalID: TerminalID) {
        broadcaster.send(.clicked(terminalID))
    }

    private func scheduleRepeat(id: TerminalID, repoName: String, minutes: Int, body: String) {
        let interval = TimeInterval(max(1, minutes)) * 60
        scheduler.schedule(id: id.description, interval: interval) { [weak self] in
            self?.deliver(id: id, title: repoName, body: body)
        }
    }

    private func deliver(id: TerminalID, title: String, body: String) {
        // Focus guard: pencere odaklıyken OS bildirimi gönderilmez (spec/13 §4)
        guard !windowFocused else { return }
        presenter.present(id: id.description, title: title, body: body)
    }
}
