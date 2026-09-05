import Foundation

/// Prompt kuyruğundaki tek eleman (refactor 7.8).
///
/// Kuyruk eskiden `[String]` idi ve liste `id: \.offset` ile çizildiği için
/// `.onMove` sırasında SwiftUI satırları indeks üzerinden eşliyordu: sürükleme
/// bittiğinde silinen/taşınan satırın kimliği kayıyordu. Stabil `id` bu
/// kırılganlığı yapısal olarak kaldırır.
///
/// **Persist edilmez:** kuyruk oturumluktur (`~/.lumi` biçimleri değişmez,
/// karar 9); `id` yalnız bellekteki liste kimliğidir.
public struct QueuedPrompt: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
