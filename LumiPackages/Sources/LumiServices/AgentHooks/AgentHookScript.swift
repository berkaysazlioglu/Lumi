import Foundation
import LumiKit

/// Sağlayıcı ayarlarına kaydedilen yönetilen hook script'i (karar 45).
///
/// Script stdin'deki hook JSON'unu okur ve PTY env'indeki `LUMI_*` üçlüsüyle
/// Lumi'nin loopback sunucusuna POST eder. Lumi dışında (iTerm'de açılmış bir
/// Claude) env yoktur → sessizce çıkar. Sunucu kapalıysa `curl` bağlantı
/// hatasıyla anında döner; hook Claude/Codex'i asla bekletmez.
public enum AgentHookScript {
    /// Script dizini `~/.lumi/hooks/` — Orca'nın `agent-hooks/claude-hook.sh`
    /// süpürücüsü bu adı YAKALAMAZ (`agent-hooks/` yok, dosya adı farklı);
    /// iki uygulama aynı makinede yan yana kurulu kalabilir.
    public static let directoryName = "hooks"
    /// Curl bütçeleri: bağlantı 0.5 s, toplam 1.5 s (Orca ile aynı).
    public static let connectTimeout = "0.5"
    public static let maxTime = "1.5"

    public static func fileName(for provider: AgentProvider) -> String {
        "lumi-\(provider.rawValue)-hook.sh"
    }

    /// Yönetilen komut eşleyicisinin aradığı iğne — yol taşınsa da tanınır.
    public static func managedNeedle(for provider: AgentProvider) -> String {
        "\(directoryName)/\(fileName(for: provider))"
    }

    public static func posix(provider: AgentProvider) -> String {
        var lines = [
            "#!/bin/sh",
            "# Lumi agent hook — Lumi her açılışta yeniden yazar; elle düzenleme kaybolur.",
        ]
        if provider == .claude {
            // Claude izin hook'ları boş stdout'ta fail-closed olur; `{}` = karar yok.
            lines.append("printf '{}\\n'")
        }
        lines += [
            "payload=$({ command -p cat 2>/dev/null || cat; })",
            "if [ -z \"$\(AgentHookEndpoint.EnvironmentKey.terminalID)\" ]"
                + " || [ -z \"$\(AgentHookEndpoint.EnvironmentKey.port)\" ]"
                + " || [ -z \"$\(AgentHookEndpoint.EnvironmentKey.token)\" ]; then",
            "  exit 0",
            "fi",
        ]
        if provider == .claude {
            // Arka plana alınmış Claude oturumu daemon worker'da koşar ve
            // dispatch eden panelin env'ini miras alır — o panele ait değildir.
            lines += ["if [ -n \"$CLAUDE_JOB_DIR\" ]; then", "  exit 0", "fi"]
        }
        lines += [
            "if [ -z \"$payload\" ]; then",
            "  exit 0",
            "fi",
            "printf '%s' \"$payload\" | curl -sS -X POST"
                + " \"http://127.0.0.1:${\(AgentHookEndpoint.EnvironmentKey.port)}\(AgentHookRequestRouter.pathPrefix)\(provider.rawValue)\" \\",
            "  --connect-timeout \(connectTimeout) --max-time \(maxTime) --noproxy 127.0.0.1 \\",
            "  -H 'Content-Type: application/json' \\",
            "  -H \"\(AgentHookRequestRouter.tokenHeader): ${\(AgentHookEndpoint.EnvironmentKey.token)}\" \\",
            "  -H \"\(AgentHookRequestRouter.terminalHeader): ${\(AgentHookEndpoint.EnvironmentKey.terminalID)}\" \\",
            "  --data-binary @- >/dev/null 2>&1 || :",
            "exit 0",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    /// Ayar dosyasındaki komut: script okunabilirse çalıştır; değilse (Lumi
    /// silinmiş) stdin'i boşalt ve Claude için `{}` bas — izin hook'u
    /// boş stdout'ta fail-closed kalmasın.
    public static func managedCommand(scriptPath: String, provider: AgentProvider) -> String {
        let quoted = "'" + scriptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let fallback = provider == .claude
            ? "{ command -p cat 2>/dev/null || cat; } >/dev/null 2>&1; printf '{}\\n'"
            : "{ command -p cat 2>/dev/null || cat; } >/dev/null 2>&1 || :"
        return "if [ -r \(quoted) ]; then /bin/sh \(quoted); else \(fallback); fi"
    }

    /// Komuttan script yolunu geri okur (tek tırnak içindeki ilk yol).
    public static func scriptPath(inManagedCommand command: String) -> String? {
        guard let open = command.firstIndex(of: "'") else { return nil }
        let rest = command[command.index(after: open)...]
        guard let close = rest.firstIndex(of: "'") else { return nil }
        return String(rest[..<close])
    }
}
