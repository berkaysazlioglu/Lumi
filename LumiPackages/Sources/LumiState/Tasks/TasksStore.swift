import Foundation
import LumiKit
import Observation

/// Tasks route'unun store'u (Tasks planı, Faz 1).
///
/// Bağlı kaynakları, birleşik task listesini, filtreyi ve iki sheet'in
/// (bağlama, yeni task) durumunu tutar. Adapter'ları `TaskProviderMaking`
/// üretir — store hangi adapter'la konuştuğunu bilmez.
///
/// **Tazeleme (kullanıcı kararı 6):** istek yalnız route görünürken atılır.
/// `keepFresh()` route view'ının `.task`'ında koşar: hemen bir tazeleme, sonra
/// `refreshInterval`'da bir; view kaybolunca SwiftUI task'i iptal eder ve
/// döngü biter.
@Observable
@MainActor
public final class TasksStore {
    public enum Layout: String, CaseIterable, Sendable {
        case board
        case list

        public var title: String {
            switch self {
            case .board: "Board"
            case .list: "List"
            }
        }
    }

    /// Bir kaynağın bağlantı durumu — başlık şeridindeki uyarı bandını sürer.
    public enum Phase: Equatable, Sendable {
        case loading
        case ready
        /// Ulaşılamadı; son liste ekranda kalır.
        case offline(String)
        /// Sunucuya ulaşıldı ama hata/bozuk yanıt döndü (5xx, geçersiz JSON);
        /// son liste ekranda kalır. "Offline"dan ayrı: düzeltilecek yer sunucu kodu.
        case failing(String)
        /// Token reddedildi (401).
        case reconnect
        /// Protokol sürümü desteklenmiyor ya da adapter yok.
        case unsupported(String)
    }

    public struct SourceState: Identifiable, Sendable {
        public var source: TaskSource
        /// Kaynağın kendi beyanı (maske uygulanmamış).
        var declaredInfo: TaskSourceInfo?
        public var phase: Phase
        public var lastUpdated: Date?
        public var users: [TaskUser] = []
        public var projects: [TaskProjectRef] = []
        /// Demo kaynağın "X yoksa" anahtarları: kapatılan yetenek/alanlar.
        public var hiddenCapabilities: Set<TaskCapability> = []
        public var hiddenFields: Set<TaskField> = []
        /// Demo kaynağın hata taklidi (yalnız `TaskProviderSimulating`).
        public var simulatedFailure: TaskSimulatedFailure?

        public var id: TaskSourceID { source.id }

        /// UI'ın baktığı beyan — maskeler uygulanmış hâli.
        public var info: TaskSourceInfo? {
            declaredInfo?.masked(capabilities: hiddenCapabilities, fields: hiddenFields)
        }

        /// Kaynağın beyan ettiği tam küme (demo anahtarlarının satırları).
        public var declaredCapabilities: Set<TaskCapability> { declaredInfo?.capabilities ?? [] }
        public var declaredFields: Set<TaskField> { Set(declaredInfo.map { Array($0.fields.keys) } ?? []) }
    }

    /// Route görünürken tazeleme aralığı.
    public static let refreshInterval: Duration = .seconds(15)
    /// Birleşik yazım gecikmesi: bir task'e yapılan düzenlemeler son
    /// düzenlemeden bu kadar sonra TEK `PATCH` olarak gider.
    public static let writeDelay: Duration = .seconds(2)

    public internal(set) var sources: [SourceState] = []
    public internal(set) var entries: [TaskEntry] = []
    public var filter = TaskFilter()
    public var layout: Layout = .board
    public var showAllDone = false
    public var selectedTask: TaskKey?
    public internal(set) var isRefreshing = false

    /// Bağlama sheet'i (nil = kapalı).
    public var connectFlow: TaskConnectFlow?
    /// Yeni task sheet'i (nil = kapalı).
    public var newTaskForm: NewTaskForm?
    /// Start sheet'inin task'i (nil = kapalı).
    public var startingTask: TaskKey?
    /// Hata kaydı sheet'i.
    public var isFailureLogPresented = false
    /// Prompt şablonu düzenlenen kaynak (nil = sheet kapalı).
    public var editingPromptTemplate: TaskSourceID?
    /// Başarısız isteklerin kaydı — en yeni başta (bkz. `TasksStore+Failures`).
    public internal(set) var failureLog: [TaskFailureEntry] = []
    /// Task ↔ ajan bağlantıları (bkz. `TasksStore+Agents`).
    public internal(set) var agentLinks: [TaskKey: TaskAgentLink] = [:]
    /// Gönderilmeyi bekleyen birleşik yazım var mı — başlıkta `Saving…`.
    public internal(set) var pendingWriteCount = 0

    @ObservationIgnored let factory: any TaskProviderMaking
    @ObservationIgnored let config: any ConfigServicing
    @ObservationIgnored let credentials: any TaskCredentialStoring
    @ObservationIgnored let images: any TaskImageLoading
    @ObservationIgnored let agents: any TaskAgentRunning
    /// Lumi projesinin git origin'i (Start'ta proje eşleşmesi).
    @ObservationIgnored let remoteURL: @Sendable (String) async -> String?
    @ObservationIgnored let toasts: ToastStore
    @ObservationIgnored let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored let debounce: @Sendable (Duration) async throws -> Void
    /// Gecikmesi süren birleşik yazımlar.
    @ObservationIgnored var pendingWrites: [TaskKey: PendingWrite] = [:]
    @ObservationIgnored var agentRuns: [TaskKey: Task<Void, Never>] = [:]
    @ObservationIgnored var providers: [TaskSourceID: any TaskProviding] = [:]
    /// Yazım sıra numarası: her yerel yazım bir artırır. Uçuştaki ya da
    /// tazeleme başladıktan sonra yapılan yazımın task'i, tazelemenin getirdiği
    /// (muhtemelen eski) sunucu kopyasıyla ezilmez.
    @ObservationIgnored var writeSequence = 0
    @ObservationIgnored var lastWrite: [TaskKey: Int] = [:]
    @ObservationIgnored var inFlightWrites: [TaskKey: Int] = [:]
    /// Silinen task'in yazım numarası — eski bir liste onu geri getirmesin.
    @ObservationIgnored var deletions: [TaskKey: Int] = [:]
    /// Verify'dan geçen, Connect'e basılmayı bekleyen kaynak + adapter.
    @ObservationIgnored var pendingConnection: (TaskSource, any TaskProviding)?

    public init(
        factory: any TaskProviderMaking,
        config: any ConfigServicing,
        credentials: any TaskCredentialStoring,
        images: any TaskImageLoading,
        agents: any TaskAgentRunning,
        remoteURL: @escaping @Sendable (String) async -> String? = { _ in nil },
        toasts: ToastStore,
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        debounce: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.factory = factory
        self.config = config
        self.credentials = credentials
        self.images = images
        self.agents = agents
        self.remoteURL = remoteURL
        self.toasts = toasts
        self.now = now
        self.sleep = sleep
        self.debounce = debounce
    }

    // MARK: - Türevler

    public var hasSources: Bool { !sources.isEmpty }

    public func state(of id: TaskSourceID) -> SourceState? {
        sources.first { $0.id == id }
    }

    public func info(of id: TaskSourceID) -> TaskSourceInfo? {
        state(of: id)?.info
    }

    public func entry(_ key: TaskKey) -> TaskEntry? {
        entries.first { $0.key == key }
    }

    /// Filtrenin kaynak seçimine göre görünen kaynaklar.
    public var visibleSources: [SourceState] {
        guard let selected = filter.source else { return sources }
        return sources.filter { $0.id == selected }
    }

    public var columns: [TaskBoard.Column] {
        TaskBoard.columns(entries, filter: filter, me: { [weak self] in self?.info(of: $0)?.me }, showAllDone: showAllDone)
    }

    public var rows: [TaskEntry] {
        TaskBoard.rows(entries, filter: filter, me: { [weak self] in self?.info(of: $0)?.me })
    }

    /// Görünen kaynaklardan biri bir alanı okuyabiliyorsa o alanın filtresi/
    /// kolonu gösterilir.
    public func anyVisibleSourceCanRead(_ field: TaskField) -> Bool {
        visibleSources.contains { $0.info?.canRead(field) == true }
    }

    public func anyVisibleSourceSupports(_ capability: TaskCapability) -> Bool {
        visibleSources.contains { $0.info?.supports(capability) == true }
    }

    /// Filtre menüsü için görünen kaynakların projeleri (task'lerde geçenler
    /// + kaynağın listesi), tekil ve ada göre sıralı.
    public var knownProjects: [TaskProjectRef] {
        let visibleIDs = Set(visibleSources.map(\.id))
        var byKey: [String: TaskProjectRef] = [:]
        for state in visibleSources where state.info?.canRead(.project) == true {
            for project in state.projects { byKey[project.key] = byKey[project.key] ?? project }
        }
        for entry in entries where visibleIDs.contains(entry.source) {
            guard let project = entry.item.project, info(of: entry.source)?.canRead(.project) == true else { continue }
            byKey[project.key] = byKey[project.key] ?? project
        }
        return byKey.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Atanan filtresinin kişileri — `You` en üstte.
    public var knownAssignees: [TaskUserOrdering.Option] {
        let states = visibleSources.filter { $0.info?.canRead(.assignee) == true }
        let me = states.count == 1 ? states[0].info?.me : nil
        var users = states.flatMap(\.users)
        let visibleIDs = Set(states.map(\.id))
        users += entries.filter { visibleIDs.contains($0.source) }.compactMap(\.item.assignee)
        return TaskUserOrdering.options(users: users, me: me)
    }

    /// "Assigned to me" filtresi tek kaynakta anlamlıdır (kişi kaynak başına).
    public var canFilterByMe: Bool {
        let states = visibleSources.filter { $0.info?.canRead(.assignee) == true }
        return states.count == 1 && states[0].info?.me != nil
    }

    public func assignOptions(for source: TaskSourceID) -> [TaskUserOrdering.Option] {
        guard let state = state(of: source), let info = state.info, info.canAssign else { return [] }
        return TaskUserOrdering.options(users: info.supports(.users) ? state.users : [], me: info.me)
    }

    // MARK: - Tazeleme

    /// Route görünür olduğu sürece koşar (bkz. tip notu).
    public func keepFresh() async {
        while !Task.isCancelled {
            await refreshSources()
            do {
                try await sleep(Self.refreshInterval)
            } catch {
                return
            }
        }
    }

    /// Elle yenileme: başlık şeridinde spinner gösterir. Döngünün kendi
    /// tazelemesi sessizdir — her 15 sn'de "Updated…" yazısı yanıp sönmesin.
    public func refreshAll() async {
        guard !sources.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshSources()
    }

    private func refreshSources() async {
        for id in sources.map(\.id) {
            await refresh(id)
        }
    }

    func refresh(_ id: TaskSourceID) async {
        guard let provider = providers[id], let current = state(of: id) else { return }
        let sequenceAtStart = writeSequence
        let needsDiscovery = current.declaredInfo == nil || current.phase == .reconnect
        var operation = TaskOperation.discover
        do {
            if needsDiscovery {
                let info = try await provider.discover()
                guard info.isVersionSupported else {
                    throw TaskProviderError.unsupportedVersion(info.version)
                }
                await loadDirectories(id, provider: provider, info: info)
                update(id) { $0.declaredInfo = info }
            }
            operation = .listTasks
            let items = try await provider.listTasks()
            merge(items, from: id, sequenceAtStart: sequenceAtStart)
            update(id) {
                $0.phase = .ready
                $0.lastUpdated = now()
            }
        } catch {
            // Route kapanınca `keepFresh` iptal edilir: yarıda kalan tazeleme
            // kesinti değildir, durum ve hata kaydı değişmez.
            if Self.isCancellation(error) { return }
            update(id) { $0.phase = Self.phase(for: error) }
            record(error, operation: operation, source: id)
        }
    }

    /// Kullanıcı ve proje listeleri yalnız discovery'de (bağlanırken ve
    /// yeniden bağlanırken) çekilir; ikisi de sık değişmez.
    func loadDirectories(_ id: TaskSourceID, provider: any TaskProviding, info: TaskSourceInfo) async {
        let users = info.supports(.users) ? (try? await provider.listUsers()) ?? [] : []
        let projects = info.supports(.projects) ? (try? await provider.listProjects()) ?? [] : []
        update(id) {
            $0.users = users
            $0.projects = projects
        }
    }

    /// Kaynağın task'lerini sunucunun listesiyle değiştirir; uçuştaki ya da
    /// tazeleme başladıktan sonra yapılmış yazımların yerel kopyası korunur.
    func merge(_ items: [TaskItem], from id: TaskSourceID, sequenceAtStart: Int) {
        let local = Dictionary(uniqueKeysWithValues: entries.filter { $0.source == id }.map { ($0.item.id, $0) })
        var merged: [TaskEntry] = items.compactMap { item in
            let key = TaskKey(source: id, id: item.id)
            if let deletedAt = deletions[key], deletedAt > sequenceAtStart || inFlightWrites[key] != nil { return nil }
            if isProtected(key, since: sequenceAtStart), let kept = local[item.id] { return kept }
            return TaskEntry(source: id, item: item)
        }
        // Sunucunun listesinde henüz görünmeyen ama korunan yerel task'ler
        // (ör. az önce oluşturulan) düşmez.
        let serverIDs = Set(items.map(\.id))
        var vanished: [TaskEntry] = []
        for (taskID, entry) in local where !serverIDs.contains(taskID) {
            if isProtected(entry.key, since: sequenceAtStart) {
                merged.append(entry)
            } else {
                vanished.append(entry)
            }
        }
        entries = entries.filter { $0.source != id } + merged
        // Sunucuda silinen task'lerin görselleri de gider.
        cleanUpImages(of: vanished)
        if let selectedTask, selectedTask.source == id, entry(selectedTask) == nil {
            self.selectedTask = nil
        }
    }

    private func isProtected(_ key: TaskKey, since sequence: Int) -> Bool {
        pendingWrites[key] != nil || inFlightWrites[key, default: 0] > 0 || lastWrite[key, default: 0] > sequence
    }

    static func phase(for error: any Error) -> Phase {
        let kind: TaskProviderError? = (error as? TaskRequestFailure)?.kind ?? (error as? TaskProviderError)
        return switch kind {
        case .unauthorized: .reconnect
        case .unsupportedVersion, .unsupported: .unsupported(message(error))
        case .unreachable, nil: .offline(message(error))
        case .invalidResponse, .conflict, .notFound: .failing(message(error))
        }
    }

    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
    }

    static func message(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func update(_ id: TaskSourceID, _ change: (inout SourceState) -> Void) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        change(&sources[index])
    }

    // MARK: - Kaynak yönetimi

    /// Demo kaynağın "X yoksa" anahtarı — yalnız beyanı maskeler.
    public func setCapability(_ capability: TaskCapability, hidden: Bool, in id: TaskSourceID) {
        update(id) { state in
            if hidden { state.hiddenCapabilities.insert(capability) } else { state.hiddenCapabilities.remove(capability) }
        }
    }

    public func setField(_ field: TaskField, hidden: Bool, in id: TaskSourceID) {
        update(id) { state in
            if hidden { state.hiddenFields.insert(field) } else { state.hiddenFields.remove(field) }
        }
    }

    /// Demo kaynağın hata taklidi — adapter `TaskProviderSimulating` değilse no-op.
    public func setSimulatedFailure(_ failure: TaskSimulatedFailure?, in id: TaskSourceID) {
        guard let simulator = providers[id] as? any TaskProviderSimulating else { return }
        update(id) { $0.simulatedFailure = failure }
        Task { await simulator.setSimulatedFailure(failure) }
    }

    public func canSimulateFailures(in id: TaskSourceID) -> Bool {
        providers[id] is any TaskProviderSimulating
    }
}
