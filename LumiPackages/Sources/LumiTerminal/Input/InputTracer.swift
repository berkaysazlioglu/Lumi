import Darwin
import Foundation

/// Opt-in girdi izleyicisi: `LUMI_DEBUG_INPUT=1` ile yazma hunisinden geçen
/// byte'ları stderr'e hex döker. Klavye→PTY zincirindeki kopukluğu teşhis için;
/// üretim yolunda maliyeti tek bir bool kontrolüdür.
enum InputTracer {
    static let isEnabled = ProcessInfo.processInfo.environment["LUMI_DEBUG_INPUT"] == "1"

    static func trace(_ stage: String, _ data: Data) {
        guard isEnabled else { return }
        let hex = data.prefix(48).map { String(format: "%02x", $0) }.joined(separator: " ")
        let line = "[lumi-input] \(stage): \(data.count)B [\(hex)]\n"
        fputs(line, stderr)
    }
}
