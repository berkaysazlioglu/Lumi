import Foundation

/// Saf, test-edilebilir turn-status reducer (spec §4.2). Session başına bir örnek;
/// hook olaylarını `ChatTurnStatus`'a katlar. Saat testte determinizm için enjekte
/// edilir. "working" için TEK otorite budur (userPromptSubmit→stop); SessionMeta.status
/// ile çift-kaynak kullanılmaz.
public final class TurnStatusReducer {
    private let now: @Sendable () -> Date
    public private(set) var status: ChatTurnStatus = .idle

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Durum değiştiyse yeni `ChatTurnStatus`, aksi halde `nil` (idempotent).
    public func reduce(_ event: AgentHookEvent) -> ChatTurnStatus? {
        var next = status
        switch event.kind {
        case .userPromptSubmit:
            next = ChatTurnStatus(
                working: true,
                startedAtMs: Int(now().timeIntervalSince1970 * 1000),
                tool: nil
            )
        case .preToolUse:
            guard event.isLead else { return nil }
            next.tool = event.toolName
        case .postToolUse, .postToolUseFailure:
            guard event.isLead else { return nil }
            next.tool = nil
        case .stop, .stopFailure:
            next = .idle
        case .sessionStart:
            guard event.source == "clear" else { return nil }
            next = .idle
        default:
            return nil
        }
        guard next != status else { return nil }
        status = next
        return next
    }

    /// Karar 96: Esc/Ctrl+C kesmesinde Claude Stop hook'u göndermez. Terminal
    /// kesmeyi çıkardığında (`inferInterrupt` → status non-working) çağrılır.
    /// Çalışıyorsa `.idle` döner, değilse `nil` (idempotent).
    public func interrupt() -> ChatTurnStatus? {
        guard status.working else { return nil }
        status = .idle
        return .idle
    }
}
