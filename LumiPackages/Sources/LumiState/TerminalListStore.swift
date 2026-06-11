import Foundation
import LumiKit
import Observation

/// Terminal listesinin UI-yüzlü metadata store'u (design/03 §4).
/// Ham çıktı burada ASLA tutulmaz — yalnız TerminalMeta.
/// Tek process'te doğrudan gözlem: reconciliation yoktur, event akışı yeterlidir.
@Observable
@MainActor
public final class TerminalListStore {
    public private(set) var terminals: [TerminalMeta] = []
    public var activeTerminalID: TerminalID?
    /// Faz 2'de ToastStore'a devredilecek geçici görünür-hata alanı (karar 5).
    public private(set) var lastErrorMessage: String?

    @ObservationIgnored private let service: any TerminalServicing
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    public init(service: any TerminalServicing) {
        self.service = service
    }

    public func start() {
        guard consumeTask == nil else { return }
        let stream = service.events()
        consumeTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.apply(event)
            }
        }
    }

    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    // MARK: - Intent'ler

    public func spawn(in repoPath: String, command: String? = nil, task: String? = nil) {
        reporting {
            _ = try self.service.spawn(repoPath: repoPath, task: task, command: command)
        }
    }

    public func close(_ id: TerminalID) {
        reporting {
            try self.service.kill(id: id)
        }
    }

    public func focus(_ id: TerminalID?) {
        activeTerminalID = id
        service.setFocused(id)
    }

    public func clearError() {
        lastErrorMessage = nil
    }

    // MARK: - Event uygulama

    private func apply(_ event: TerminalEvent) {
        switch event {
        case .spawned(let meta):
            terminals.append(meta)
            focus(meta.id)
        case .exited(let id, _):
            remove(id)
        case .statusChanged(let id, let status):
            update(id) { $0.status = status }
        case .titleChanged(let id, let title):
            update(id) { $0.oscTitle = title }
        case .bell:
            break
        }
    }

    private func update(_ id: TerminalID, _ mutate: (inout TerminalMeta) -> Void) {
        guard let index = terminals.firstIndex(where: { $0.id == id }) else { return }
        var copy = terminals[index]
        mutate(&copy)
        terminals[index] = copy
    }

    private func remove(_ id: TerminalID) {
        guard let index = terminals.firstIndex(where: { $0.id == id }) else { return }
        if activeTerminalID == id {
            // Komşu-odak: önce önceki, yoksa sonraki (spec/21; repo-bazlı kurallar Faz 3'te)
            let remaining = terminals.indices.filter { $0 != index }
            let neighbor = remaining.last(where: { $0 < index }) ?? remaining.first(where: { $0 > index })
            focus(neighbor.map { terminals[$0].id })
        }
        terminals.remove(at: index)
    }

    private func reporting(_ operation: () throws -> Void) {
        do {
            try operation()
            lastErrorMessage = nil
        } catch let error as LumiError {
            lastErrorMessage = error.localizedDescription
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
