/// New Claude dropdown'unun model kısayolları (karar 121). Yalnız Claude
/// Code'un takma adları kullanılır — tam model ID'si yazılmaz; takma ad her
/// zaman o ailenin en güncel modeline gider. Telefonun `+` menüsü de aynı
/// listeyi gösterir ve `start_session`'a additive `model` olarak yollar (karar 133).
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
}
