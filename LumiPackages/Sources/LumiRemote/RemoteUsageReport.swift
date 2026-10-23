import Foundation
import LumiKit

/// Mac top bar'ındaki kota göstergelerinin telefona giden hâli (karar 128):
/// yalnız Mac'te AÇIK göstergeler taşınır — telefon aynı seçimi gösterir.
public struct RemoteUsageReport: Sendable, Equatable {
    public struct Provider: Sendable, Equatable {
        public let provider: AgentProvider
        public let snapshot: UsageSnapshot?
        public let errorMessage: String?

        public init(provider: AgentProvider, snapshot: UsageSnapshot?, errorMessage: String?) {
            self.provider = provider
            self.snapshot = snapshot
            self.errorMessage = errorMessage
        }
    }

    public let providers: [Provider]
    /// DeepSeek göstergesi kapalıysa `nil`; açık ama bakiye yoksa `balance == nil`.
    public let deepSeek: DeepSeekEntry?

    public struct DeepSeekEntry: Sendable, Equatable {
        public let balance: DeepSeekBalance?
        public let errorMessage: String?

        public init(balance: DeepSeekBalance?, errorMessage: String?) {
            self.balance = balance
            self.errorMessage = errorMessage
        }
    }

    public init(providers: [Provider], deepSeek: DeepSeekEntry?) {
        self.providers = providers
        self.deepSeek = deepSeek
    }

    /// `usage` payload'ı: `{providers:[{id,limits:[{id,label,kind,percent?,
    /// resetsAt?,durationSec?}],error?}], deepseek?:{available,currency?,total?,error?}}`.
    /// `resetsAt` epoch ms'dir; süre yalnız sağlayıcı bildirdiyse gelir (karar 74).
    public func payload() -> [String: Any] {
        var dict: [String: Any] = ["providers": providers.map(Self.providerPayload)]
        if let deepSeek { dict["deepseek"] = Self.deepSeekPayload(deepSeek) }
        return dict
    }

    private static func providerPayload(_ entry: Provider) -> [String: Any] {
        var dict: [String: Any] = [
            "id": entry.provider.rawValue,
            "limits": (entry.snapshot?.limits ?? []).map(limitPayload),
        ]
        if let error = entry.errorMessage { dict["error"] = error }
        return dict
    }

    private static func limitPayload(_ limit: UsageLimit) -> [String: Any] {
        var dict: [String: Any] = ["id": limit.id, "label": limit.rawLabel, "kind": kindName(limit.kind)]
        if let percent = limit.window.percentUsed { dict["percent"] = percent }
        if let resetsAt = limit.window.resetsAt {
            dict["resetsAt"] = (resetsAt.timeIntervalSince1970 * 1000).rounded()
        }
        if let duration = limit.window.duration { dict["durationSec"] = duration }
        return dict
    }

    private static func kindName(_ kind: UsageLimit.Kind) -> String {
        switch kind {
        case .session: "session"
        case .weeklyAll: "week"
        case .weeklyModel: "model"
        case .other: "other"
        }
    }

    private static func deepSeekPayload(_ entry: DeepSeekEntry) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let balance = entry.balance {
            dict["available"] = balance.isAvailable
            if let primary = balance.primary {
                dict["currency"] = primary.currency
                if let total = primary.total { dict["total"] = NSDecimalNumber(decimal: total).stringValue }
            }
        }
        if let error = entry.errorMessage { dict["error"] = error }
        return dict
    }
}
