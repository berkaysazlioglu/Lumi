import Foundation
import LumiKit
import Observation

/// Plastic SCM panel cache'leri + checkin akışı (karar 46): çalışma alanı
/// başlığı, değişiklik listesi/seçimi, son changeset'ler.
///
/// Tazeleme: aktif repo değişiminde `loadAll`, FSEvents köprüsünde yalnız
/// `refreshStatus` (changeset sorgusu sunucuya gider — her dosya
/// değişiminde koşmaz), başlıktaki ↻ ile yeniden `loadAll`.
@Observable
@MainActor
public final class PlasticStore {
    /// History'de gösterilen pencere: son 7 gün.
    public static let recentWindow: TimeInterval = 7 * 24 * 60 * 60
    /// Sunucudan çekilen en yeni changeset tavanı; pencere bunun içinde uygulanır.
    public static let changesetLimit = 200
    /// Pencerede hiç changeset yoksa gösterilen en yeni N kayıt.
    public static let fallbackCount = 25

    /// History gövdesinin verisi: pencere içindekiler ya da (boşsa) en yeniler.
    public struct RecentChangesets: Equatable, Sendable {
        public let items: [PlasticChangeset]
        /// true → pencere boştu, `items` en yeni `fallbackCount` kayıttır.
        public let isFallback: Bool

        public init(items: [PlasticChangeset], isFallback: Bool) {
            self.items = items
            self.isFallback = isFallback
        }

        public static let empty = RecentChangesets(items: [], isFallback: false)
    }

    public private(set) var workspaces: [String: PlasticWorkspaceInfo] = [:]
    public private(set) var changesets: [String: [PlasticChangeset]] = [:]
    public private(set) var changes: [String: [PlasticFileChange]] = [:]
    /// `cm` kurulu mu? Süreç ömrü boyunca bir kez ölçülür.
    public private(set) var isCLIAvailable = true
    @ObservationIgnored private var didProbeCLI = false
    public private(set) var loadingPaths: Set<String> = []

    /// Checkin seçimi — `GitStore` kuralıyla aynı: kullanıcı dokunmadıysa
    /// hepsi seçili; bir kez toggle ettiyse tazeleme seçimi ezmez, yalnız
    /// kaybolan dosyalar düşer.
    public private(set) var selectedFiles = KeyedToggleSet<String, String>()
    @ObservationIgnored private var reposWithUserSelection: Set<String> = []
    public private(set) var checkinMessages: [String: String] = [:]
    public private(set) var isCheckingIn = false

    @ObservationIgnored private let service: any PlasticReading & PlasticWriting
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        service: any PlasticReading & PlasticWriting,
        toasts: ToastStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.toasts = toasts
        self.now = now
    }

    // MARK: - Yükleme

    public func loadAll(_ workspacePath: String) async {
        loadingPaths.insert(workspacePath)
        defer { loadingPaths.remove(workspacePath) }

        if !didProbeCLI {
            didProbeCLI = true
            isCLIAvailable = await service.isCLIAvailable()
        }
        guard isCLIAvailable else { return }

        if let info = await service.workspaceInfo(workspacePath: workspacePath) {
            workspaces[workspacePath] = info
        } else {
            workspaces.removeValue(forKey: workspacePath)
        }
        await refreshStatus(workspacePath)
        changesets[workspacePath] = await service.recentChangesets(
            workspacePath: workspacePath, limit: Self.changesetLimit
        )
    }

    /// FSEvents köprüsü: yalnız çalışma alanı durumu (sunucu sorgusu yok).
    public func refreshStatus(_ workspacePath: String) async {
        guard isCLIAvailable else { return }
        let list = await service.status(workspacePath: workspacePath)
        changes[workspacePath] = list
        let present = Set(list.map(\.path))
        if reposWithUserSelection.contains(workspacePath) {
            selectedFiles.replace((selectedFiles[workspacePath] ?? []).intersection(present), in: workspacePath)
        } else {
            selectedFiles.replace(present, in: workspacePath)
        }
    }

    public func isLoading(_ workspacePath: String) -> Bool {
        loadingPaths.contains(workspacePath)
    }

    // MARK: - Türevler

    public func recentChangesets(_ workspacePath: String) -> RecentChangesets {
        Self.select(from: changesets[workspacePath] ?? [], now: now())
    }

    /// Saf seçim: `now - recentWindow`dan yeni olanlar; hiç yoksa en yeni
    /// `fallbackCount` kayıt `isFallback` bayrağıyla. Çıktı changeset id'sine
    /// göre yeniden eskiye sıralıdır — graph'ın topolojik sırası (id'ler
    /// repo içinde monoton artar; tarih replikasyonla bozulabilir).
    public static func select(from all: [PlasticChangeset], now: Date) -> RecentChangesets {
        let sorted = all.sorted { $0.changesetID > $1.changesetID }
        let cutoff = now.addingTimeInterval(-recentWindow)
        let recent = sorted.filter { $0.date >= cutoff }
        if !recent.isEmpty { return RecentChangesets(items: recent, isFallback: false) }
        return RecentChangesets(items: Array(sorted.prefix(fallbackCount)), isFallback: !sorted.isEmpty)
    }

    // MARK: - Seçim

    public func toggleFile(_ workspacePath: String, path: String) {
        reposWithUserSelection.insert(workspacePath)
        selectedFiles.toggle(path, in: workspacePath)
    }

    public func toggleSelectAll(_ workspacePath: String) {
        reposWithUserSelection.insert(workspacePath)
        let all = Set((changes[workspacePath] ?? []).map(\.path))
        let current = selectedFiles[workspacePath] ?? []
        selectedFiles.replace(current.count == all.count ? [] : all, in: workspacePath)
    }

    public func isSelected(_ workspacePath: String, path: String) -> Bool {
        selectedFiles.contains(path, in: workspacePath)
    }

    // MARK: - Checkin

    /// Karar 47: seçili öğeler + çalışma alanı changeset'ine göre diff metni
    /// (`cm cat` tabanı ↔ yerel dosya). Başlık bilgisi yoksa yalnız liste gider.
    public func checkinMessageRequest(_ workspacePath: String) async -> CommitMessageRequest {
        let selected = selectedFiles[workspacePath] ?? []
        let selectedChanges = (changes[workspacePath] ?? []).filter { selected.contains($0.path) }
        let changes = selectedChanges.map { CommitMessageRequest.Change(path: $0.path, status: $0.status) }
        guard !changes.isEmpty, let changesetID = workspaces[workspacePath]?.changesetID else {
            return CommitMessageRequest(vcsName: "Plastic SCM", changes: changes)
        }
        let diff = await service.workingTreeDiffText(
            workspacePath: workspacePath, changesetID: changesetID, changes: selectedChanges
        )
        return CommitMessageRequest(vcsName: "Plastic SCM", changes: changes, diff: diff)
    }

    public func checkinMessage(for workspacePath: String) -> String {
        checkinMessages[workspacePath] ?? ""
    }

    public func setCheckinMessage(_ message: String, for workspacePath: String) {
        checkinMessages[workspacePath] = message
    }

    /// Checkin butonunun kapısı: en az bir dosya seçili, mesaj boşluk-dışı
    /// dolu, uçuşta checkin yok. `checkin(_:)` aynı koşulları guard'lar.
    public func canCheckin(_ workspacePath: String) -> Bool {
        guard !isCheckingIn, isCLIAvailable else { return false }
        guard !(selectedFiles[workspacePath] ?? []).isEmpty else { return false }
        return !checkinMessage(for: workspacePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    public func checkin(_ workspacePath: String) async {
        guard canCheckin(workspacePath) else { return }
        let files = Array(selectedFiles[workspacePath] ?? []).sorted()
        let message = checkinMessage(for: workspacePath).trimmingCharacters(in: .whitespacesAndNewlines)

        isCheckingIn = true
        defer { isCheckingIn = false }

        let succeeded = await toasts.reporting {
            try await self.service.checkin(workspacePath: workspacePath, message: message, files: files)
        }
        if succeeded {
            setCheckinMessage("", for: workspacePath)
            await loadAll(workspacePath)
        }
    }

    /// Tek öğenin yerel değişikliğini atar; başarıda yalnız durum tazelenir
    /// (changeset listesi değişmez).
    public func undo(_ workspacePath: String, path: String) async {
        let succeeded = await toasts.reporting {
            try await self.service.undo(workspacePath: workspacePath, files: [path])
        }
        if succeeded { await refreshStatus(workspacePath) }
    }

    // MARK: - Cache eviction

    public func evict(_ workspacePath: String) {
        workspaces.removeValue(forKey: workspacePath)
        changesets.removeValue(forKey: workspacePath)
        changes.removeValue(forKey: workspacePath)
        checkinMessages.removeValue(forKey: workspacePath)
        selectedFiles.evict(workspacePath)
        reposWithUserSelection.remove(workspacePath)
        loadingPaths.remove(workspacePath)
    }
}
