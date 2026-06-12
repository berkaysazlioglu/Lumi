import Darwin
import Foundation

/// Opt-in OSC izleyicisi: `LUMI_DEBUG_OSC=1` ile decode edilen her OSC 0/2/9
/// olayını stderr'e döker. Amaç: Claude/Codex'in gerçekte yaydığı başlık ve
/// bildirim dizilerini ground-truth olarak görmek (✳-idle varsayımının ve
/// izin/soru anlarının doğrulanması). Üretim yolunda maliyeti tek bir bool'dur.
enum OSCTracer {
    static let isEnabled = ProcessInfo.processInfo.environment["LUMI_DEBUG_OSC"] == "1"

    /// Ham başlık olayı: komut, payload ve ilk birkaç codepoint (hex) +
    /// parser'ın çıkardığı isWorking yorumu birlikte loglanır.
    static func traceTitle(command: Int, raw: String, isWorking: Bool?) {
        guard isEnabled else { return }
        let scalars = raw.unicodeScalars.prefix(6)
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
        let work = isWorking.map(String.init(describing:)) ?? "nil"
        let line = "[lumi-osc] cmd=\(command) isWorking=\(work) head=[\(scalars)] raw=\(quoted(raw))\n"
        fputs(line, stderr)
    }

    /// OSC 9 bildirim olayı: payload + yorumlanan tür (turn-complete vs generic).
    static func traceNotification(raw: String, kind: OSCNotificationKind) {
        guard isEnabled else { return }
        let line = "[lumi-osc] cmd=9 kind=\(kind) raw=\(quoted(raw))\n"
        fputs(line, stderr)
    }

    private static func quoted(_ string: String) -> String {
        "\"\(string.prefix(120))\""
    }
}
