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
        overrides: [String: String] = [:],
        hookEndpoint: AgentHookEndpoint? = nil,
        terminalID: TerminalID? = nil,
        claudePluginDirectories: [String] = []
    ) -> [String: String] {
        var environment = base
        environment.merge(overrides) { _, new in new }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        // oh-my-zsh güncelleme sorusu `[Y/n]` launch komutunun ilk karakter(ler)ini
        // yiyor ("claude"→"laude"; LaunchCommandGate sessizliği "prompt hazır"
        // sanıyor — [Y/n] da sessiz bekler). Lumi'nin açtığı shell'de güncelleme
        // sorusunun yeri yok: omz'nin resmi anahtarlarıyla kapatılır (yeni omz
        // DISABLE_UPDATE_PROMPT'u, eskisi DISABLE_AUTO_UPDATE'i okur).
        environment["DISABLE_UPDATE_PROMPT"] = "true"
        environment["DISABLE_AUTO_UPDATE"] = "true"
        // Claude-oturum kimliği ASLA miras geçmez: Lumi bir claude oturumu
        // içinden başlatılırsa (open env taşır) child claude kendini alt-oturum
        // sanıp (CLAUDECODE=1 + CLAUDE_CODE_SESSION_ID) transcript'i enjekte
        // edilen --session-id yoluna hiç yazmıyor → telefon chat aynası sonsuza
        // dek boş kalıyordu (2026-09-17 teşhisi). CLAUDE_CONFIG_DIR bilinçli
        // korunur (kullanıcının meşru global ayarı olabilir).
        environment["CLAUDECODE"] = nil
        environment["CLAUDE_EFFORT"] = nil
        for key in environment.keys where key.hasPrefix("CLAUDE_CODE_") {
            environment[key] = nil
        }
        // Claude Code terminal görsellerini (kitty grafikleri) yalnız XTVERSION
        // cevabı kitty/ghostty diyen terminalde açar; SwiftTerm kendi adını
        // söyler ama kitty Unicode placeholder'larını çizer. Mod'ların `Image`
        // öğesi (yapıştırılan görsel önizlemesi) bu kapıdan geçer.
        environment["CLAUDE_CODE_FORCE_TERMINAL_IMAGES"] = "1"
        // Karar 142: açık Lumi modları, `--plugin-dir` vermeden her claude'a.
        if !claudePluginDirectories.isEmpty {
            environment[ClaudeMods.pluginDirsVariable] = claudePluginDirectories.joined(separator: ":")
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
