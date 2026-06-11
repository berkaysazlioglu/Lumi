import AppKit
import Foundation
import LumiKit
import LumiState
import LumiTerminal

/// P1 prototipi (design/04): 1 görünür + 12 gizli terminal, hepsi `yes` flood'u.
/// Geçme kriteri: RSS < 300MB, main thread < %40, görünür terminalde akıcılık.
/// Bellek raporu 5 sn'de bir stdout'a yazılır; CPU Activity Monitor/Instruments ile izlenir.
@MainActor
final class P1Harness {
    static let terminalCount = 13
    static let reportInterval: TimeInterval = 5

    private let manager: TerminalSessionManager
    private let store: TerminalListStore
    private var reportTimer: Timer?
    private let startedAt = Date()

    init(manager: TerminalSessionManager, store: TerminalListStore) {
        self.manager = manager
        self.store = store
    }

    func run(repoPath: String) {
        manager.setMaxTerminals(Self.terminalCount)
        print("P1: \(Self.terminalCount) terminal spawn ediliyor (1 görünür + \(Self.terminalCount - 1) gizli)…")

        for index in 0..<Self.terminalCount {
            do {
                _ = try manager.spawn(repoPath: repoPath, task: "p1-\(index)", command: nil)
            } catch {
                print("P1: spawn \(index) başarısız: \(error.localizedDescription)")
            }
        }

        // İlk terminal görünür kalsın; store son spawn'ı aktif yapmıştı
        if let first = manager.terminals.first {
            store.focus(first.id)
        }

        // Login shell'lerin oturması için kısa bekleme, sonra flood başlat
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [manager] in
            MainActor.assumeIsolated {
                print("P1: flood başlıyor (yes)…")
                for meta in manager.terminals {
                    try? manager.write(id: meta.id, text: "yes\r")
                }
            }
        }

        reportTimer = Timer.scheduledTimer(withTimeInterval: Self.reportInterval, repeats: true) { _ in
            MainActor.assumeIsolated {
                let elapsed = Int(Date().timeIntervalSince(self.startedAt))
                let footprint = MemoryFootprint.footprintMB()
                let verdict = footprint < 300 ? "OK" : "LİMİT AŞIMI"
                print(String(format: "P1 t=%3ds  bellek=%.1f MB  terminal=%d  [%@]",
                             elapsed, footprint, self.manager.terminals.count, verdict))
            }
        }
    }
}
