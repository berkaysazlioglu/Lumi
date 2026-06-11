/// Terminalde hangi agent'ın çalıştığına dair ipucu (spec/10 §6).
/// LumiKit.AgentProvider config seviyesidir; hint ise oturum içi çıkarımdır.
enum AgentHint: Equatable, Sendable {
    case claude
    case codex
    case unknown
}
