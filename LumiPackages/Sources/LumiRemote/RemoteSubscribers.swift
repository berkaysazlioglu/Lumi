import Foundation
import LumiKit

/// Bir terminali kimin hangi modda izlediği (docs/design/08 "Abonelik sayımı").
///
/// Eskiden abonelik terminal başına tekti: bir istemcinin `unsubscribe`'ı ya da
/// başka moddaki `subscribe`'ı diğer izleyicinin akışını da kesiyordu. Şimdi her
/// izleyici (`subscriber` — telefon kanalı için tek `phone`, hub kanalında
/// controller'ın relay bağlantı kimliği) kendi modunu taşır; bir mod yalnız son
/// izleyicisi gidince kapanır. Saf değer tipi — akışları servis açıp kapatır.
struct RemoteSubscribers {
    enum Mode: Equatable { case terminal, chat }

    /// Telefon kanalının izleyici anahtarı — bütün telefonlar bugünkü gibi tek izleyici sayılır.
    static let phone = "phone"

    static func hubSubscriber(_ from: String?) -> String { "hub:\(from ?? "")" }

    private var byTerminal: [TerminalID: [String: Mode]] = [:]

    func has(_ id: TerminalID, mode: Mode) -> Bool {
        byTerminal[id]?.values.contains(mode) ?? false
    }

    /// `subscriber` artık `id`'yi `mode`'da izliyor. Dönen kümede, bu izleyicinin
    /// önceki modundan izleyicisi kalmayan mod (kapatılacak akış) bulunur.
    mutating func subscribe(_ id: TerminalID, subscriber: String, mode: Mode) -> Set<Mode> {
        let previous = byTerminal[id]?[subscriber]
        byTerminal[id, default: [:]][subscriber] = mode
        guard let previous, previous != mode, !has(id, mode: previous) else { return [] }
        return [previous]
    }

    /// İzleyicinin `id` aboneliğini bırakır; izleyicisi kalmayan modu döner.
    mutating func unsubscribe(_ id: TerminalID, subscriber: String) -> Set<Mode> {
        guard let mode = byTerminal[id]?.removeValue(forKey: subscriber) else { return [] }
        if byTerminal[id]?.isEmpty == true { byTerminal[id] = nil }
        return has(id, mode: mode) ? [] : [mode]
    }

    /// Şartı sağlayan izleyicilerin hepsini bırakır (controller ayrıldı / hub kanalı koptu).
    /// Terminal başına izleyicisi kalmayan modları döner.
    mutating func removeSubscribers(where matches: (String) -> Bool) -> [TerminalID: Set<Mode>] {
        var orphaned: [TerminalID: Set<Mode>] = [:]
        for id in Array(byTerminal.keys) {
            for subscriber in (byTerminal[id] ?? [:]).keys where matches(subscriber) {
                let modes = unsubscribe(id, subscriber: subscriber)
                if !modes.isEmpty { orphaned[id, default: []].formUnion(modes) }
            }
        }
        return orphaned
    }

    /// Terminal kapandı.
    mutating func remove(_ id: TerminalID) {
        byTerminal[id] = nil
    }

    mutating func removeAll() {
        byTerminal.removeAll()
    }
}
