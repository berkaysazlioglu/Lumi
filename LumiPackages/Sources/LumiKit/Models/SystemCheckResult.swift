import Foundation

/// Tek bir sistem sağlık kontrolünün sonucu (design/02 §8).
public struct SystemCheckResult: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable {
        case pass
        case warn
        case fail
    }

    public let id: String
    public let label: String
    public let status: Status
    public let message: String
    public let isFixable: Bool
    /// "Fix" aksiyonunun açacağı kurulum sayfası. Kontrolün kendisi üretir —
    /// checkID → URL eşlemesi AppDelegate'te bir `switch` olarak yaşamaz
    /// (refactor 3.6). `isFixable` true olduğu halde `nil` olabilir: düzeltme
    /// yolu bir bağlantı değilse.
    public let fixURL: URL?

    public init(
        id: String,
        label: String,
        status: Status,
        message: String,
        isFixable: Bool = false,
        fixURL: URL? = nil
    ) {
        self.id = id
        self.label = label
        self.status = status
        self.message = message
        self.isFixable = isFixable
        self.fixURL = fixURL
    }
}
