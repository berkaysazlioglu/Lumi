import Foundation

/// Asenkron yüklenen tek bir değerin durumu (design/03 §4 bu adı `GitStore`
/// diff cache'inde anıyor; `FileViewerStore` sunum içeriğinde kullanır).
///
/// Amaç: "değer + isLoading + errorMessage" üçlüsünün doğurduğu geçersiz ara
/// durumları (yükleniyor AMA eski değer ekranda, hata AMA bayat içerik görünür)
/// yapısal olarak imkânsız kılmak — karar 5'in tek tip hata sözleşmesi.
public enum Loadable<Value: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case loaded(Value)
    /// Kullanıcıya gösterilecek hata metni (`LumiError.localizedDescription`).
    case failed(String)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    /// İçeriği dönüştürür; `loading`/`failed` aynen taşınır.
    public func map<T>(_ transform: (Value) -> T) -> Loadable<T> {
        switch self {
        case .loading: return .loading
        case .loaded(let value): return .loaded(transform(value))
        case .failed(let message): return .failed(message)
        }
    }
}
