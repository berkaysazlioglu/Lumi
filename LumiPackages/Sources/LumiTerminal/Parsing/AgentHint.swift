/// Terminalde hangi agent'ın çalıştığına dair ipucu.
/// LumiKit.AgentProvider config seviyesidir; hint ise oturum içi çıkarımdır.
enum AgentHint: Equatable, Sendable {
    case claude
    case codex
    case unknown
}
