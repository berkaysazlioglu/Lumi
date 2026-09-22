import Foundation

/// Çözülmüş hızlı komut gövdesini diske yazan sınır (karar 92). Dosya
/// `~/.lumi/quick-commands/` altında durur; dönen değer mutlak yoldur.
/// **Fırlatan sözleşme:** yazılamazsa `LumiError.fileOperationFailed`.
public protocol QuickCommandScriptWriting: Sendable {
    func writeScript(named fileName: String, contents: String) async throws -> String
}
