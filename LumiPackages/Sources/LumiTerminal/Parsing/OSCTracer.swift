import Darwin
import Foundation

/// Opt-in OSC izleyicisi: `LUMI_DEBUG_OSC=1` ile decode edilen her OSC olayını
/// stderr'e döker. Amaç: Claude/Codex'in gerçekte yaydığı başlık ve bildirim
/// dizilerini ground-truth olarak görmek (✳-idle varsayımının ve izin/soru
/// anlarının doğrulanması). Üretim yolunda maliyeti tek bir bool'dur.
enum OSCTracer {
    static let isEnabled = ProcessInfo.processInfo.environment["LUMI_DEBUG_OSC"] == "1"

    /// Ham OSC olayı + semantik katmanın ondan ürettiği yorum birlikte loglanır
    /// (yorumsuz kalan kodlar da görünür: `events=[]`).
    static func trace(raw: OSCRawEvent, events: [OSCEvent]) {
        guard isEnabled else { return }
        let scalars = raw.payload.unicodeScalars.prefix(6)
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
        let line = "[lumi-osc] cmd=\(raw.code) events=\(events) head=[\(scalars)] "
            + "raw=\(quoted(raw.payload))\n"
        fputs(line, stderr)
    }

    private static func quoted(_ string: String) -> String {
        "\"\(string.prefix(120))\""
    }
}
