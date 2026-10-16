/// New Claude dropdown'unun model kısayolları (karar 121). Yalnız Claude
/// Code'un takma adları kullanılır — tam model ID'si yazılmaz; takma ad her
/// zaman o ailenin en güncel modeline gider.
public enum ClaudeModelAlias: String, Sendable, Equatable, CaseIterable {
    // Sıra dropdown sırasıdır.
    case fable
    case opus
    case sonnet
    case haiku

    public var displayName: String {
        switch self {
        case .fable: "Fable"
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        }
    }

    /// `--session-id` enjeksiyonu (karar 23) bu komutun üstüne eklenir — ilk
    /// token `claude` kaldığı sürece resume zinciri bozulmaz.
    public var launchCommand: String {
        "\(AgentProvider.claude.launchCommand) --model \(rawValue)"
    }
}
