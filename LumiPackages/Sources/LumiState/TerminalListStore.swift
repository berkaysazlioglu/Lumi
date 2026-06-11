import Foundation
import LumiKit
import Observation

/// Terminal listesinin UI-yüzlü metadata store'u (design/03 §4, spec/21 kuralları).
/// Ham çıktı burada ASLA tutulmaz — yalnız TerminalMeta.
///
/// Değişmez kural (spec/21 §6): minimize edilmiş terminal asla odak alamaz;
/// tek istisna bildirim/bell tıklamasıdır ve `restoreAndFocus` üzerinden
/// (önce restore, sonra odak) akar.
@Observable
@MainActor
public final class TerminalListStore {
    public private(set) var terminals: [TerminalMeta] = []
    public private(set) var activeTerminalID: TerminalID?
    public private(set) var minimizedIDs: Set<TerminalID> = []

    @ObservationIgnored private var lastActiveByRepo: [String: TerminalID] = [:]
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

    // MARK: - Selector'lar

    public func terminals(in repoPath: String) -> [TerminalMeta] {
        terminals.filter { $0.repoPath == repoPath }
    }

    public func visibleTerminals(in repoPath: String) -> [TerminalMeta] {
        terminals.filter { $0.repoPath == repoPath && !minimizedIDs.contains($0.id) }
    }

    public func minimizedTerminals(in repoPath: String) -> [TerminalMeta] {
        terminals.filter { $0.repoPath == repoPath && minimizedIDs.contains($0.id) }
    }

    public func isMinimized(_ id: TerminalID) -> Bool {
        minimizedIDs.contains(id)
    }

    public var totalCount: Int {
        terminals.count
    }

    public func meta(for id: TerminalID) -> TerminalMeta? {
        terminals.first { $0.id == id }
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

    public func closeAll(in repoPath: String) {
        for meta in terminals(in: repoPath) {
            close(meta.id)
        }
    }

    /// setActiveTerminal paritesi (spec/21 §7): id map'te olmasa bile set edilir
    /// (yeni spawn henüz yansımamış olabilir); minimize edilmişe odak verilmez.
    public func focus(_ id: TerminalID?) {
        guard let id else {
            activeTerminalID = nil
            service.setFocused(nil)
            return
        }
        guard !minimizedIDs.contains(id) else { return }
        activeTerminalID = id
        if let repoPath = meta(for: id)?.repoPath {
            lastActiveByRepo[repoPath] = id
        }
        service.setFocused(id)
    }

    /// Minimize: aktifse görünür komşuya proaktif odak kayar (spec/21 §6).
    public func minimize(_ id: TerminalID) {
        guard let repoPath = meta(for: id)?.repoPath else { return }
        minimizedIDs.insert(id)
        if activeTerminalID == id {
            let visibleBefore = terminals.filter {
                $0.repoPath == repoPath && ($0.id == id || !minimizedIDs.contains($0.id))
            }
            focus(Self.neighborID(closing: id, among: visibleBefore))
        }
        if lastActiveByRepo[repoPath] == id {
            lastActiveByRepo[repoPath] = visibleTerminals(in: repoPath).first?.id
        }
    }

    /// Restore odaklamaz — odaklı restore yalnız bildirim/bell tıklamasıyla.
    public func restore(_ id: TerminalID) {
        minimizedIDs.remove(id)
    }

    /// Bildirim tıklaması istisnası: önce restore, sonra odak (spec/21 §6).
    public func restoreAndFocus(_ id: TerminalID) {
        minimizedIDs.remove(id)
        focus(id)
    }

    /// Tab değişimi yan etkisi (spec/21 §9): repo'nun lastActive'i geçerli ve
    /// görünürse o, değilse ilk görünür, hiç yoksa nil.
    public func activateRepo(_ repoPath: String) {
        let visible = visibleTerminals(in: repoPath)
        if let last = lastActiveByRepo[repoPath], visible.contains(where: { $0.id == last }) {
            focus(last)
        } else {
            focus(visible.first?.id)
        }
    }

    // MARK: - Klavye navigasyonu (görünür küme, aynı repo)

    public func focusIndex(_ index: Int, in repoPath: String) {
        let visible = visibleTerminals(in: repoPath)
        guard visible.indices.contains(index) else { return }
        focus(visible[index].id)
    }

    public func focusNext(in repoPath: String) {
        stepFocus(in: repoPath, offset: 1)
    }

    public func focusPrevious(in repoPath: String) {
        stepFocus(in: repoPath, offset: -1)
    }

    private func stepFocus(in repoPath: String, offset: Int) {
        let visible = visibleTerminals(in: repoPath)
        guard !visible.isEmpty else { return }
        guard let current = activeTerminalID,
              let index = visible.firstIndex(where: { $0.id == current }) else {
            focus(visible.first?.id)
            return
        }
        let next = (index + offset + visible.count) % visible.count
        focus(visible[next].id)
    }

    // MARK: - Event uygulama (testler doğrudan sürebilsin diye internal)

    func apply(_ event: TerminalEvent) {
        switch event {
        case .spawned(let meta):
            terminals.append(meta)
            // Spawn eden path açıkça odaklar (spec/21 §3 sözleşmesi)
            focus(meta.id)
        case .exited(let id, _):
            remove(id)
        case .statusChanged(let id, let status):
            update(id) { $0.status = status }
        case .titleChanged(let id, let title):
            update(id) { $0.oscTitle = title }
        case .bell(let id):
            // Emülatör BEL karakteri — status-güdümlü bell'ler ayrıca
            // NotificationService'ten gelir
            if let meta = meta(for: id) {
                toasts.show(.bell, title: meta.name, message: "Bell", terminalID: id)
            }
        }
    }

    private func update(_ id: TerminalID, _ mutate: (inout TerminalMeta) -> Void) {
        guard let index = terminals.firstIndex(where: { $0.id == id }) else { return }
        var copy = terminals[index]
        mutate(&copy)
        terminals[index] = copy
    }

    /// Kapanışta komşu odaklama (spec/21 §5 birebir): silmeden ÖNCE hesaplanır;
    /// adaylar aynı repo'nun görünür terminalleridir — odak başka repo'ya atlamaz.
    private func remove(_ id: TerminalID) {
        guard let index = terminals.firstIndex(where: { $0.id == id }) else { return }
        let repoPath = terminals[index].repoPath

        if activeTerminalID == id {
            let candidates = terminals.filter {
                $0.repoPath == repoPath && ($0.id == id || !minimizedIDs.contains($0.id))
            }
            let neighbor = Self.neighborID(closing: id, among: candidates)
            activeTerminalID = neighbor
            if let neighbor {
                lastActiveByRepo[repoPath] = neighbor
                service.setFocused(neighbor)
            } else {
                service.setFocused(nil)
            }
        }

        if lastActiveByRepo[repoPath] == id {
            let remaining = terminals.filter {
                $0.repoPath == repoPath && $0.id != id && !minimizedIDs.contains($0.id)
            }
            if let first = remaining.first {
                lastActiveByRepo[repoPath] = first.id
            } else {
                lastActiveByRepo.removeValue(forKey: repoPath)
            }
        }

        minimizedIDs.remove(id)
        terminals.remove(at: index)
    }

    /// Komşu kuralı (spec/21 §5): önceki; ilk kapanıyorsa sonraki; id listede
    /// yoksa ilki; liste boşsa nil. `candidates` kapanan terminali İÇERİR.
    static func neighborID(closing id: TerminalID, among candidates: [TerminalMeta]) -> TerminalID? {
        let others = candidates.filter { $0.id != id }
        guard !others.isEmpty else { return nil }
        guard let index = candidates.firstIndex(where: { $0.id == id }) else {
            return others.first?.id
        }
        if index > 0 {
            return candidates[index - 1].id
        }
        return others.first?.id
    }
}
