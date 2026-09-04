import Foundation

/// Repo (ya da başka bir anahtar) başına tutulan "açık/seçili" küme cache'i
/// (refactor 5.5).
///
/// Üç yerde birebir aynı kod vardı: `GitStore.selectedFiles`,
/// `GitStore.expandedBranches`, `RepoStore.expandedNodes` — her biri kendi
/// `toggle`/`contains`/`?? []` kopyasını taşıyordu ve hiçbiri tab kapanınca
/// temizlenmiyordu. Tek tip burada; `evict(_:)` bellek cache'ini boşaltmanın
/// tek yoludur.
///
/// Subscript **opsiyonel** döner: sözlük paritesi korunur (yazılmamış anahtar
/// `nil`), böylece mevcut `?? []` / `?.count` çağrı yerleri değişmeden çalışır.
public struct KeyedToggleSet<Key: Hashable & Sendable, Element: Hashable & Sendable>: Equatable, Sendable {
    private var storage: [Key: Set<Element>]

    public init(_ storage: [Key: Set<Element>] = [:]) {
        self.storage = storage
    }

    public subscript(key: Key) -> Set<Element>? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    public var isEmpty: Bool { storage.isEmpty }

    public var keys: Dictionary<Key, Set<Element>>.Keys { storage.keys }

    public func contains(_ element: Element, in key: Key) -> Bool {
        storage[key]?.contains(element) ?? false
    }

    public mutating func toggle(_ element: Element, in key: Key) {
        var set = storage[key] ?? []
        if set.contains(element) {
            set.remove(element)
        } else {
            set.insert(element)
        }
        storage[key] = set
    }

    public mutating func insert(_ element: Element, in key: Key) {
        storage[key, default: []].insert(element)
    }

    public mutating func formUnion(_ elements: some Sequence<Element>, in key: Key) {
        storage[key, default: []].formUnion(elements)
    }

    /// Anahtarın kümesini tamamen değiştirir (boş küme de yazılır — `evict`
    /// ile karıştırma: burada anahtar KALIR).
    public mutating func replace(_ elements: Set<Element>, in key: Key) {
        storage[key] = elements
    }

    /// Bellek cache'ini boşaltır: anahtar tamamen kaybolur.
    public mutating func evict(_ key: Key) {
        storage.removeValue(forKey: key)
    }
}
