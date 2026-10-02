import Foundation

/// `claude -p --output-format json` zarfı:
/// `{"type":"result","subtype":"success","is_error":false,"result":"…","total_cost_usd":…,"duration_ms":…}`.
/// Orchestrator'ın arka plan çağrıları (özet — Faz 4, `ask_project` — Faz 5) ortak okur.
struct ClaudePrintEnvelope: Equatable {
    let result: String
    let isError: Bool
    /// Hata alt tipi (`error_max_budget_usd`, `error_max_turns` …).
    let subtype: String?
    let costUSD: Double?
    let durationSeconds: Double?

    init?(stdout: String) {
        guard let data = stdout.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        result = object["result"] as? String ?? ""
        isError = object["is_error"] as? Bool ?? false
        subtype = object["subtype"] as? String
        costUSD = object["total_cost_usd"] as? Double
        durationSeconds = (object["duration_ms"] as? Double).map { $0 / 1000 }
    }

    /// Hata zarfında kullanıcıya söylenecek açıklama.
    var errorDetail: String {
        if !result.isEmpty { return String(result.prefix(500)) }
        return subtype ?? "claude reported an error"
    }
}
