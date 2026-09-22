import Foundation
import LumiKit

/// `claude -p` için hızlı komut prompt'u (karar 92) — saf metin üretimi.
///
/// Sözleşme system prompt'a eklenir (`--append-system-prompt`), kullanıcının
/// tarifi stdin'den gider: talimat/veri ayrımı karar 47'deki gibi korunur.
public enum QuickCommandPrompt {
    public static func systemPrompt(projectPath: String, runsInBackground: Bool = false) -> String {
        let keys = QuickCommandPlaceholder.allCases
            .map { "- \($0.token): \($0.summary)" }
            .joined(separator: "\n")
        return """
        You write reusable shell commands for the Lumi desktop app. The user describes a command \
        for the project at \(projectPath) (your current directory). Explore it freely — read files, \
        inspect existing scripts, run read-only commands — but NEVER modify, create or delete files \
        and never start long-running processes.

        \(runsInBackground ? backgroundRun : terminalRun) Its working directory is one checkout of \
        this project: either the project itself or a separate workspace copy (git worktree / \
        Plastic workspace) located elsewhere on disk. So:
        - Never hard-code \(projectPath) or any path inside it. Use these placeholders, which Lumi \
        replaces with raw text before running:
        \(keys)
        - Always wrap placeholders in double quotes, e.g. cd "{path}" (paths may contain spaces).
        - Prefer paths relative to the working directory when the file belongs to the checkout.
        - Read project-specific values (tool/engine versions, scheme or target names, ports) from \
        the checkout's files AT RUN TIME instead of hard-coding what you saw while exploring — \
        other checkouts may be on a different branch. Example: a Unity editor version comes from \
        "{path}/ProjectSettings/ProjectVersion.txt" (m_EditorVersion).
        - Don't start with a #! line; Lumi runs the file with sh.
        - Target POSIX sh (macOS). Keep it short, add brief comments only where they help.
        - macOS `open -a App --args …` passes the arguments ONLY when App is not already running; \
        otherwise it just brings the running instance to the front and silently drops them. When \
        each project needs its own instance (Unity Editor, another project in the same IDE), use \
        `open -n -a …`, or check first whether that project is already open.

        Reply with exactly ONE ```sh fenced code block containing the whole script and nothing \
        else — no explanation before or after it. Write comments in English.
        """
    }

    private static let terminalRun =
        "The command you write is saved and later run with `sh <file>` in a NEW terminal window."

    /// Karar 93: Start App terminalsiz koşar — soru soramaz, çıktıyı kimse görmez.
    /// Ölçülen hatalar: `npx expo start` stdin'siz "Input is required" ile
    /// kapandı; `open -a Unity` açık Unity'ye `-projectPath`'i iletmedi.
    private static let backgroundRun = """
        The command you write starts the project's app. It is saved and later run with `sh <file>` \
        in the BACKGROUND: no terminal, no stdin (it reads /dev/null), output goes to a log file, \
        and nobody watches it. So nothing may ever ask a question: any CLI that can prompt \
        (Expo, npm/npx, installers, simulators) must be made non-interactive — e.g. `CI=1`, \
        `--non-interactive`, `--yes`, or answering defaults — otherwise it aborts with an \
        "input is required" error and the app never starts. Fail loudly with a clear message on \
        stderr (it lands in the log) when a prerequisite is missing. Launching a GUI app or a \
        long-running server in the foreground of the script is fine — the script is detached from \
        Lumi.
        """

    public static func body(for request: QuickCommandGenerationRequest) -> String {
        var text = "Project: \(request.projectName)\n\nCommand I want:\n\(request.description.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        let current = request.currentScript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            text += "\nCurrent script (improve or replace it):\n```sh\n\(current)\n```\n"
        }
        return text
    }

    /// Yanıttaki ilk kabuk bloğunun (` ```sh ` / ` ```bash ` / dilsiz ` ``` `)
    /// içi. Çitler çift çift gezilir ki başka dildeki bir bloğun kapanışı
    /// açılış sanılmasın; kapanmamış blok sona kadar sürer. Hiç blok yoksa
    /// (model talimatı çiğnediyse) yanıtın kendisi. Boşsa `nil`.
    public static func extractScript(from reply: String) -> String? {
        let lines = reply.components(separatedBy: "\n")
        var index = lines.startIndex
        var sawFence = false
        while let open = lines[index...].firstIndex(where: { fenceLanguage($0) != nil }) {
            sawFence = true
            let body = lines[(open + 1)...]
            let close = body.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "```" } ?? body.endIndex
            if shellLanguages.contains(fenceLanguage(lines[open]) ?? "") {
                return nonEmpty(body[..<close].joined(separator: "\n"))
            }
            guard close < lines.endIndex else { break }
            index = close + 1
        }
        return sawFence ? nil : nonEmpty(reply)
    }

    private static let shellLanguages: Set<String> = ["", "sh", "bash", "shell", "zsh"]

    /// Çit satırıysa dil etiketi (küçük harf, boş olabilir), değilse `nil`.
    private static func fenceLanguage(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else { return nil }
        return trimmed.dropFirst(3).lowercased()
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed + "\n"
    }
}
