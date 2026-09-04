/// Terminalde hangi agent'ın çalıştığına dair ipucu.
/// LumiKit.AgentProvider config seviyesidir; hint ise oturum içi çıkarımdır.
///
/// Kapalı enum değil **açık struct**tır (Faz 4.8 / OCP): yeni bir agent semantiği
/// eklemek (`OSCSemantics` implementasyonu + kendi hint sabiti) mevcut hiçbir
/// switch'i kırmaz. `.claude` / `.codex` / `.unknown` karşılaştırmaları aynen çalışır.
struct AgentHint: Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let unknown = AgentHint(rawValue: "unknown")
    static let claude = AgentHint(rawValue: "claude")
    static let codex = AgentHint(rawValue: "codex")
}
