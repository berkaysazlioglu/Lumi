extension ClaudeModelAlias {
    /// `--session-id` enjeksiyonu (karar 23) bu komutun üstüne eklenir — ilk
    /// token `claude` kaldığı sürece resume zinciri bozulmaz.
    public var launchCommand: String {
        "\(AgentProvider.claude.launchCommand) --model \(rawValue)"
    }
}
