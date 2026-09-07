import Foundation
import LumiKit

/// PTY child'ına verilecek environment'ı üretir.
///
/// TERM ve COLORTERM her zaman Lumi'nin (SwiftTerm backend) yeteneklerini
/// deklare eder — miras alınan değerler DIŞ terminali (iTerm vb.) tanımlar ve
/// launch bağlamına göre değişir: Finder'dan açılan .app'te COLORTERM hiç
/// yoktur, `swift run`'da dış terminalden sızar. Bu fark, PTY'deki CLI'ların
/// (Claude Code dahil) truecolor yerine 256-renk paletine düşmesine ve
/// terminal renklerinin paketli build'de soluk görünmesine yol açıyordu.
///
/// Karar 45: hook uç noktası verilirse `LUMI_TERMINAL_ID` / `LUMI_AGENT_HOOK_PORT`
/// / `LUMI_AGENT_HOOK_TOKEN` eklenir — Claude/Codex'in kurulu hook script'i
/// olayı doğru terminale, doğru sunucuya iletir. Uç nokta yoksa üçlü hiç
/// yazılmaz (miras kalan bayat değer de silinir: başka bir Lumi örneğinin
/// portuna post edilmesin).
enum TerminalEnvironment {
    static func childEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        hookEndpoint: AgentHookEndpoint? = nil,
        terminalID: TerminalID? = nil
    ) -> [String: String] {
        var environment = base
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        environment[AgentHookEndpoint.EnvironmentKey.terminalID] = nil
        environment[AgentHookEndpoint.EnvironmentKey.port] = nil
        environment[AgentHookEndpoint.EnvironmentKey.token] = nil
        if let hookEndpoint, let terminalID {
            environment.merge(hookEndpoint.environment(for: terminalID)) { _, new in new }
        }
        return environment
    }
}
