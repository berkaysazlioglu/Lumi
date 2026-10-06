import Foundation

/// Terminal link adaylarının diskte olup olmadığı (karar 116, Orca
/// `terminal-path-exists-cache` paritesi): olmayan yolun altı çizilmez.
///
/// Sorgu ana thread'de ve cooperative pool'da KOŞMAZ (karar 86): asılı bir ağ
/// mount'undaki `fileExists` ayrı bir GCD kuyruğunda bekler; aynı yol için
/// ikinci bir sorgu açılmaz. Orca'dan fark: cevaplar süresizdir değil — kısa bir
/// ömürle tutulur ki az önce oluşturulan dosya hover'da link olabilsin.
@MainActor
final class TerminalLinkPathCache {
    typealias Probe = @Sendable (String) -> Bool

    /// Bir cevabın geçerli kaldığı süre.
    static let entryLifetime: TimeInterval = 3
    /// Önbellek tavanı (hover'da gezilen yollar birikmesin).
    static let maxEntries = 1024

    private struct Entry {
        let exists: Bool
        let storedAt: Date
    }

    private let probe: Probe
    /// `true` → sorgu çağıran thread'de koşar (testler).
    private let runsInline: Bool
    private let now: () -> Date
    private var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private static let queue = DispatchQueue(label: "lumi.terminal.link-path-probe", qos: .userInitiated, attributes: .concurrent)

    init(
        probe: @escaping Probe = { FileManager.default.fileExists(atPath: $0) },
        runsInline: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.probe = probe
        self.runsInline = runsInline
        self.now = now
    }

    /// `nil` → bilinmiyor (hiç sorulmadı ya da cevap eskidi).
    func exists(_ path: String) -> Bool? {
        guard let entry = entries[path] else { return nil }
        guard now().timeIntervalSince(entry.storedAt) < Self.entryLifetime else {
            entries[path] = nil
            return nil
        }
        return entry.exists
    }

    /// Bilinmeyen yolları sorar; cevaplar gelince `completion` ana thread'de bir
    /// kez çağrılır. Zaten sorulmakta olan yol yeniden sorulmaz ve o durumda
    /// `completion` çağrılmaz — çağıran, tamamlanınca GÜNCEL durumu yeniden
    /// değerlendirmelidir (ilk sorgunun completion'ı bunu yapar).
    func request(_ paths: [String], completion: @escaping @MainActor @Sendable () -> Void) {
        let pending = paths.filter { exists($0) == nil && !inFlight.contains($0) }
        guard !pending.isEmpty else { return }
        inFlight.formUnion(pending)
        let probe = probe
        if runsInline {
            store(pending.map { ($0, probe($0)) })
            completion()
            return
        }
        Self.queue.async {
            let results = pending.map { ($0, probe($0)) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.store(results)
                    completion()
                }
            }
        }
    }

    private func store(_ results: [(String, Bool)]) {
        if entries.count + results.count > Self.maxEntries { entries.removeAll(keepingCapacity: true) }
        let storedAt = now()
        for (path, exists) in results {
            inFlight.remove(path)
            entries[path] = Entry(exists: exists, storedAt: storedAt)
        }
    }
}
