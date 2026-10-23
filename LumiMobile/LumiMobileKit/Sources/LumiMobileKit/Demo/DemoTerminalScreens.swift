import Foundation

/// Canned PTY scrollback for terminal-mode demo sessions (zsh + a Codex screen).
enum DemoTerminalScreens {
    private static let esc = "\u{1B}["
    private static let reset = esc + "0m"
    private static let bold = esc + "1m"
    private static let red = esc + "31m"
    private static let green = esc + "32m"
    private static let yellow = esc + "33m"
    private static let magenta = esc + "35m"
    private static let cyan = esc + "36m"
    private static let dim = esc + "2m"
    private static let boldBlue = esc + "1;34m"

    /// The zsh prompt (`demo@Mac lumi %`) used by the shell screen and the echo.
    static func prompt(_ dir: String = "lumi") -> String {
        "\(green)demo@Mac\(reset) \(boldBlue)\(dir)\(reset) \(magenta)%\(reset) "
    }

    static func scrollback(for sessionId: String) -> Data {
        let lines = sessionId == DemoIDs.hints ? codexLines : shellLines
        return Data((lines.joined(separator: "\r\n")).utf8)
    }

    private static var shellLines: [String] {
        [
            "\(dim)Last login: Thu Oct 23 09:41:12 on ttys004\(reset)",
            prompt("Desktop") + "ls -la",
            "total 48",
            "drwx------@  9 demo  staff   288 Oct 23 09:40 \(boldBlue).\(reset)",
            "drwxr-x---+ 42 demo  staff  1344 Oct 22 18:02 \(boldBlue)..\(reset)",
            "-rw-r--r--@  1 demo  staff  6148 Oct 21 11:20 .DS_Store",
            "drwxr-xr-x   5 demo  staff   160 Oct 20 14:33 \(boldBlue)mockups\(reset)",
            "-rwxr-xr-x   1 demo  staff   412 Oct 19 16:05 \(red)release.sh\(reset)",
            "-rw-r--r--   1 demo  staff  2310 Oct 23 09:12 notes.md",
            "lrwxr-xr-x   1 demo  staff    24 Oct 18 10:00 \(magenta)lumi\(reset) -> /Users/demo/wkspaces/Lumi",
            prompt("Desktop") + "cd lumi && git status",
            "On branch \(bold)main\(reset)",
            "Your branch is ahead of '\(cyan)origin/main\(reset)' by 2 commits.",
            "",
            "Changes to be committed:",
            "  (use \"git restore --staged <file>...\" to unstage)",
            "\t\(green)modified:   LumiMobile/LumiMobileKit/Sources/LumiMobileKit/RelayClient.swift\(reset)",
            "",
            "Changes not staged for commit:",
            "\t\(red)modified:   LumiPackages/Sources/LumiKit/Models/ProjectTree.swift\(reset)",
            "\t\(red)deleted:    docs/old-notes.md\(reset)",
            "",
            "Untracked files:",
            "\t\(red)scratch.swift\(reset)",
            "",
            prompt(),
        ]
    }

    private static var codexLines: [String] {
        [
            "\(bold)>_ OpenAI Codex\(reset) \(dim)(v0.48.0)\(reset)",
            "",
            "\(dim)model:\(reset) gpt-5-codex   \(dim)directory:\(reset) ~/wkspaces/word-puzzle",
            "",
            "\(cyan)›\(reset) Add a 30 s cooldown to the hint button and show a ring timer.",
            "",
            "\(yellow)•\(reset) Explored",
            "  └ Read HintButton.swift, HintStore.swift",
            "\(yellow)•\(reset) Edited Sources/App/Hints/HintButton.swift (+24 -3)",
            "\(yellow)•\(reset) Ran swift test --filter HintTests",
            "  └ \(green)Executed 6 tests, with 0 failures\(reset)",
            "",
            "Added `HintCooldown` (30 s) and a `RingTimer` overlay; the button is disabled",
            "while cooling down and re-enables with a light haptic.",
            "",
            "\(dim)▌ Ask Codex to do anything\(reset)",
        ]
    }

    /// Echo of typed bytes for the shell: CR → newline + fresh prompt, DEL → erase.
    static func echo(_ bytes: Data) -> Data {
        var out = Data()
        for byte in bytes {
            switch byte {
            case carriageReturn: out.append(contentsOf: Array(("\r\n" + prompt()).utf8))
            case delete: out.append(contentsOf: Array("\u{8} \u{8}".utf8))
            default: out.append(byte)
            }
        }
        return out
    }

    private static let carriageReturn: UInt8 = 0x0D
    private static let delete: UInt8 = 0x7F
}
