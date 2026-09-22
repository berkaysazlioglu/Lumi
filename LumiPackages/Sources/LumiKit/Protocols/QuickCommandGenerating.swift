import Foundation

/// Claude'dan hızlı komut üretme isteği (karar 92).
public struct QuickCommandGenerationRequest: Sendable, Equatable {
    /// Claude'un gezdiği dizin — projenin kendi kökü.
    public let projectPath: String
    public let projectName: String
    /// Kullanıcının tarifi ("Unity'yi bu workspace'te aç" gibi).
    public let description: String
    /// Düzenlenen komutun mevcut gövdesi; varsa Claude onu iyileştirir.
    public let currentScript: String
    /// Karar 93: `Start App` gibi terminalsiz, arka planda koşacak komut.
    public let runsInBackground: Bool

    public init(
        projectPath: String, projectName: String, description: String,
        currentScript: String = "", runsInBackground: Bool = false
    ) {
        self.projectPath = projectPath
        self.projectName = projectName
        self.description = description
        self.currentScript = currentScript
        self.runsInBackground = runsInBackground
    }
}

/// Hızlı komut üreticisi sınırı (karar 92). **Fırlatan sözleşme:** kullanıcı
/// düğmeye bastı; CLI yok / oturum yok / script'siz yanıt görünür hatadır
/// (`LumiError.cliNotFound` ya da `.quickCommandGenerationFailed`).
///
/// Karar 47'nin aksine üretim araçlıdır: Claude projeyi gezip script'leri
/// inceleyebilir ve keşif için komut çalıştırabilir. Dönen değer anahtarları
/// (`{path}` …) çözülmemiş bir `sh` gövdesidir.
public protocol QuickCommandGenerating: Sendable {
    func generate(_ request: QuickCommandGenerationRequest) async throws -> String
}
