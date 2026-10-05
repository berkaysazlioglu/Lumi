import Foundation
import LumiKit
import Observation

/// Orchestrator'ın yazma eylemleri için onay isteği (karar 114 Faz 3):
/// popup'ta "şu terminale şu mesaj" kartı olarak görünür.
public struct OrchestratorApprovalRequest: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sendMessage
        case startTerminal
    }

    public let id: UUID
    public let kind: Kind
    /// Kartın başlığı ("Send to “api-refactor”").
    public let title: String
    /// Hedefin konumu: proje · checkout · sağlayıcı · durum.
    public let target: String
    /// Gönderilecek mesaj / ilk prompt — kullanıcı onaylamadan önce görür.
    public let body: String
    /// Ek uyarı (ör. "ajan meşgul — turn bitince gönderilecek").
    public let note: String?

    public init(
        id: UUID = UUID(), kind: Kind, title: String, target: String, body: String, note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.target = target
        self.body = body
        self.note = note
    }
}

/// Onay kapısı: araç yürütücüsü `request` ile bekler, popup `resolve` ile
/// cevaplar. Cevapsız istek `timeout` sonunda düşer — Claude'un araç
/// çağrısı sonsuza dek asılı kalmasın. Stop / New conversation / quit
/// bekleyenlerin hepsini reddeder.
@Observable
@MainActor
public final class OrchestratorApprovals {
    public enum Decision: Equatable, Sendable {
        case approved
        case rejected
        case timedOut
    }

    /// Varsayılan bekleme üst sınırı. Orchestrator sürecinin MCP araç
    /// zaman aşımı bundan uzundur (`OrchestratorService.toolTimeout`).
    public static let defaultTimeout: Duration = .seconds(600)

    public private(set) var pending: [OrchestratorApprovalRequest] = []

    @ObservationIgnored private var continuations: [UUID: CheckedContinuation<Decision, Never>] = [:]
    @ObservationIgnored private var timeouts: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let timeout: Duration

    public init(timeout: Duration = OrchestratorApprovals.defaultTimeout) {
        self.timeout = timeout
    }

    public func request(_ request: OrchestratorApprovalRequest) async -> Decision {
        await withCheckedContinuation { continuation in
            pending.append(request)
            continuations[request.id] = continuation
            let timeout = self.timeout
            timeouts[request.id] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(request.id, .timedOut)
            }
        }
    }

    public func approve(_ id: UUID) { finish(id, .approved) }
    public func reject(_ id: UUID) { finish(id, .rejected) }

    /// Bekleyen tüm istekleri reddeder (süreç durduruldu / konuşma sıfırlandı).
    public func rejectAll() {
        for request in pending { finish(request.id, .rejected) }
    }

    private func finish(_ id: UUID, _ decision: Decision) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeAll { $0.id == id }
        continuation.resume(returning: decision)
    }
}
