import Foundation
import LumiKit
import Observation

/// Alt bar Resource Manager'ın durumu (karar 43; Orca
/// `ResourceUsageStatusSegment` paritesi).
///
/// Periyodik `ps` örneklemesi → terminal başına PTY alt ağacı toplamı +
/// uygulamanın kendi kullanımı. Gruplama repo bazlıdır (Lumi'de worktree yok).
/// Örnekleme aralığı popover açıkken sıklaşır.
@Observable
@MainActor
public final class ResourceUsageStore: StoreLifecycle {
    public enum SortOption: String, Sendable, CaseIterable {
        case name
        case cpu
        case memory
    }

    public struct SessionRow: Identifiable, Sendable, Equatable {
        public let id: TerminalID
        public let title: String
        public let status: TerminalStatus
        /// `nil` = süreç henüz örneklenmedi ya da bitmiş.
        public let metrics: ResourceMetrics?
    }

    public struct RepoGroup: Identifiable, Sendable, Equatable {
        public let id: String
        public let name: String
        public let metrics: ResourceMetrics
        public let sessions: [SessionRow]
    }

    public static let idleInterval: Duration = .seconds(5)
    public static let openInterval: Duration = .seconds(2)
    /// Sparkline geçmişi (uygulama RSS'i).
    public static let historyLength = 30

    public private(set) var snapshot: ResourceUsageSnapshot?
    public private(set) var appMemoryHistory: [Double] = []
    public private(set) var isSampling = false
    public var sortOption: SortOption = .name
    public var collapsedRepos: Set<String> = []
    public var isAppCollapsed = true
    /// Popover görünürlüğü — aralık seçimi için.
    public var isPresented = false {
        didSet { if isPresented, !oldValue { Task { await refresh() } } }
    }

    @ObservationIgnored private let terminals: TerminalListStore
    @ObservationIgnored private let terminalService: any TerminalSessionControlling
    @ObservationIgnored private let sampler: any ProcessSampling
    @ObservationIgnored private let appPID: Int32
    @ObservationIgnored private let hostMemoryBytes: UInt64
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(
        terminals: TerminalListStore,
        terminalService: any TerminalSessionControlling,
        sampler: any ProcessSampling,
        appPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        hostMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.terminals = terminals
        self.terminalService = terminalService
        self.sampler = sampler
        self.appPID = appPID
        self.hostMemoryBytes = hostMemoryBytes
        self.now = now
    }

    // MARK: - Yaşam döngüsü

    public func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self else { return }
                let interval = self.isPresented ? Self.openInterval : Self.idleInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Tek örnekleme turu. Tablo alınamazsa önceki snapshot korunur.
    public func refresh() async {
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }
        let roots = Dictionary(uniqueKeysWithValues: terminals.terminals.compactMap { meta in
            terminalService.processID(for: meta.id).map { (meta.id, $0) }
        })
        guard let table = await sampler.sampleProcessTable() else { return }
        let next = ResourceUsageSnapshot.make(
            table: table, appPID: appPID, terminalRoots: roots,
            hostMemoryBytes: hostMemoryBytes, sampledAt: now()
        )
        snapshot = next
        appMemoryHistory = (appMemoryHistory + [Double(next.app.total.residentBytes)]).suffix(Self.historyLength)
    }

    // MARK: - Türevler

    /// Alt bar rozeti: terminal ağaçlarının Σ RSS'i.
    public var terminalMemoryBytes: UInt64 { snapshot?.terminalTotal.residentBytes ?? 0 }
    public var terminalCPUPercent: Double { snapshot?.terminalTotal.cpuPercent ?? 0 }
    public var sessionCount: Int { terminals.terminals.count }

    /// Repo grupları, seçili sıralamayla (gruplar ve içindeki oturumlar).
    public var repoGroups: [RepoGroup] {
        let grouped = Dictionary(grouping: terminals.terminals, by: \.repoPath)
        let groups = grouped.map { repoPath, metas -> RepoGroup in
            let rows = metas.map { meta in
                SessionRow(
                    id: meta.id, title: meta.displayTitle, status: meta.status,
                    metrics: snapshot?.terminals[meta.id]
                )
            }
            let total = rows.compactMap(\.metrics).reduce(.zero, +)
            return RepoGroup(
                id: repoPath,
                name: (repoPath as NSString).lastPathComponent,
                metrics: total,
                sessions: sort(rows, by: sortOption)
            )
        }
        return sort(groups, by: sortOption)
    }

    private func sort(_ rows: [SessionRow], by option: SortOption) -> [SessionRow] {
        switch option {
        case .name: return rows.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .cpu: return rows.sorted { ($0.metrics?.cpuPercent ?? -1) > ($1.metrics?.cpuPercent ?? -1) }
        case .memory: return rows.sorted { ($0.metrics?.residentBytes ?? 0) > ($1.metrics?.residentBytes ?? 0) }
        }
    }

    private func sort(_ groups: [RepoGroup], by option: SortOption) -> [RepoGroup] {
        switch option {
        case .name: return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .cpu: return groups.sorted { $0.metrics.cpuPercent > $1.metrics.cpuPercent }
        case .memory: return groups.sorted { $0.metrics.residentBytes > $1.metrics.residentBytes }
        }
    }

    // MARK: - Eylemler

    public func toggleRepo(_ id: String) {
        collapsedRepos = collapsedRepos.contains(id) ? collapsedRepos.subtracting([id]) : collapsedRepos.union([id])
    }

    /// Oturumu sonlandırır (terminal kapanır; onay UI tarafındadır).
    public func kill(_ id: TerminalID) {
        terminals.close(id)
    }

    public func killAll() {
        for meta in terminals.terminals { terminals.close(meta.id) }
    }
}
