import Foundation

/// Agent row status glyph semantics — mirrors the Mac's `AgentActivityState`
/// (decisions 51/81): running → spinner, needs input → bell, done → check,
/// failed → x, idle → muted dot. `waiting-*` (turn closed) is "done", so a
/// finished agent no longer looks like one awaiting a decision (decision 97).
public enum AgentActivity: Sendable, Equatable {
    case running, awaitingDecision, done, failed, idle

    public init(status: String, awaitingDecision: Bool) {
        if awaitingDecision { self = .awaitingDecision; return }
        switch SessionStatus(rawValue: status) ?? .idle {
        case .working: self = .running
        case .waitingUnseen, .waitingFocused, .waitingSeen: self = .done
        case .error: self = .failed
        case .idle: self = .idle
        }
    }

    public var title: String {
        switch self {
        case .running: "Running"
        case .awaitingDecision: "Needs input"
        case .done: "Done"
        case .failed: "Failed"
        case .idle: "Idle"
        }
    }

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
