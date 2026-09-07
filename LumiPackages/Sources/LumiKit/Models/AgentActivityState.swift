import Foundation

/// Sidebar ajan satırının durum glifi (karar 51, Orca `AgentStateDot`).
///
/// Altı durumlu `TerminalStatus` + karar bekleme bayrağı, kullanıcıya dört
/// anlama indirgenir: **çalışıyor** (spinner), **karar bekliyor** (zil),
/// **bitti** (yeşil tik — ajan turn'ünü kapattı, girdi bekliyor), **hata**
/// ve **boşta** (düz shell / henüz başlamamış). Eşleme view'sız test edilir.
public enum AgentActivityState: Sendable, Equatable {
    case running
    case awaitingDecision
    case done
    case failed
    case idle

    public init(status: TerminalStatus, isAwaitingDecision: Bool) {
        if isAwaitingDecision { self = .awaitingDecision; return }
        switch status {
        case .working: self = .running
        case .waitingUnseen, .waitingFocused, .waitingSeen: self = .done
        case .error: self = .failed
        case .idle: self = .idle
        }
    }

    /// Erişilebilirlik etiketi ve tooltip metni.
    public var title: String {
        switch self {
        case .running: "Running"
        case .awaitingDecision: "Waiting for decision"
        case .done: "Done"
        case .failed: "Failed"
        case .idle: "Idle"
        }
    }

    /// Orca sıralaması: dikkat isteyenler önce, sonra çalışanlar, sonra bitenler.
    public var sortRank: Int {
        switch self {
        case .awaitingDecision: 0
        case .failed: 1
        case .running: 2
        case .done: 3
        case .idle: 4
        }
    }
}
