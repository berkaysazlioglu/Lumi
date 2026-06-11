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

    @ObservationIgnored private let service: any TerminalServicing
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    public init(service: any TerminalServicing, toasts: ToastStore) {
        self.service = service
        self.toasts = toasts
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
        toasts.reporting {
            _ = try self.service.spawn(repoPath: repoPath, task: task, command: command)
        }
    }

    public func close(_ id: TerminalID) {
        toasts.reporting {
            try self.service.kill(id: id)
        }
    }

    public func focus(_ id: TerminalID?) {
        activeTerminalID = id
        service.setFocused(id)
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
        case .bell(let id):
            let name = terminals.first(where: { $0.id == id })?.name ?? "Terminal"
            toasts.show(.bell, title: name, message: "Bell")
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
}
