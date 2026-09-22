import Foundation

/// Script'i terminal açmadan, Lumi'den kopuk başlatan sınır (karar 93 —
/// `Start App`). Çağrı başlatmayı bekler, script'in bitmesini BEKLEMEZ;
/// stdout/stderr `logPath`'e yazılır.
/// **Fırlatan sözleşme:** başlatılamazsa `LumiError.spawnFailed`.
public protocol QuickCommandBackgroundLaunching: Sendable {
    func launch(scriptPath: String, workingDirectory: String, logPath: String) async throws
}
