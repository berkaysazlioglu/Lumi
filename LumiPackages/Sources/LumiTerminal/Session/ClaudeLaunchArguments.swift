import Foundation

/// Karar 141: koşan claude'un argv'sinden resume'a taşınacak bayraklar.
///
/// Beyaz listedir: yalnız oturumun nasıl çalıştığını belirleyen ve resume'da
/// yeniden verilmesi güvenli bayraklar kalır (`--model`, `--permission-mode`,
/// `--add-dir`…). Oturum seçen (`--resume`, `--continue`, `--session-id`,
/// `--fork-session`), yan etki doğuran (`--worktree`, `--tmux`, `--bg`,
/// `--cloud`) ya da tek seferlik (`-p`, ilk prompt gibi konumsal argümanlar)
/// her şey düşer; tanınmayan bayrak da düşer — kaybolması, yanlış
/// tekrarlanmasından iyidir.
public enum ClaudeLaunchArguments {
    private enum Arity {
        case none
        case one
        /// commander'ın `<values...>` biçimi: `-` ile başlamayan tüm devam token'ları.
        case variadic
    }

    private static let kept: [String: Arity] = [
        "--model": .one,
        "--fallback-model": .one,
        "--effort": .one,
        "--permission-mode": .one,
        "--permission-prompts": .one,
        "--agent": .one,
        "--agents": .one,
        "--append-system-prompt": .one,
        "--system-prompt": .one,
        "--settings": .one,
        "--setting-sources": .one,
        "--autocompact": .one,
        "--plugin-dir": .one,
        "--max-budget-usd": .one,
        "--add-dir": .variadic,
        "--allowedTools": .variadic,
        "--allowed-tools": .variadic,
        "--disallowedTools": .variadic,
        "--disallowed-tools": .variadic,
        "--tools": .variadic,
        "--mcp-config": .variadic,
        "--betas": .variadic,
        "--dangerously-skip-permissions": .none,
        "--allow-dangerously-skip-permissions": .none,
        "--strict-mcp-config": .none,
        "--disable-slash-commands": .none,
        "--ide": .none,
        "--chrome": .none,
        "--no-chrome": .none,
        "--brief": .none,
        "--verbose": .none,
        "--safe-mode": .none,
        "--restricted": .none,
    ]

    /// Sürecin argv'si (argv[0] dahil) → resume bayrakları. Süreç claude
    /// değilse `nil` (ön planda başka bir program koşuyor).
    public static func resumable(fromProcessArguments argv: [String]) -> [String]? {
        guard let start = claudeArgumentsStart(in: argv) else { return nil }
        return filter(Array(argv[start...]))
    }

    /// Beyaz listeden geçen bayraklar, sıraları ve değerleriyle.
    public static func filter(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            index += 1
            if token == "--" { break }
            if let equals = token.firstIndex(of: "="), token.hasPrefix("--") {
                // `--model=opus`: değeri token'ın içinde.
                if let arity = kept[String(token[..<equals])], arity != .none { result.append(token) }
                continue
            }
            switch kept[token] {
            case nil:
                continue
            case .none?:
                result.append(token)
            case .one?:
                guard index < arguments.count else { continue }
                result += [token, arguments[index]]
                index += 1
            case .variadic?:
                var values: [String] = []
                while index < arguments.count, !arguments[index].hasPrefix("-") {
                    values.append(arguments[index])
                    index += 1
                }
                if !values.isEmpty { result += [token] + values }
            }
        }
        return result
    }

    /// Yerel ikili `claude …`; npm kurulumu `node …/claude-code/cli.js …`.
    private static func claudeArgumentsStart(in argv: [String]) -> Int? {
        guard let first = argv.first else { return nil }
        let name = (first as NSString).lastPathComponent
        if name == "claude" { return 1 }
        if name == "node" || name.hasPrefix("node"), argv.count > 1, argv[1].contains("claude-code") {
            return 2
        }
        return nil
    }
}
