import Foundation
import LumiKit
import Observation

/// Agent History ▸ oturum sunucusu (karar 138, Lumi Sessions Protocol v1).
///
/// Ağ isteği YALNIZ kullanıcı eylemiyle gider: `Import from Server` popup'ı
/// açıldığında (liste 5 dakikadan eskiyse), popup'taki Refresh düğmesinde,
/// bağlanırken, yüklerken, indirirken ve silerken. Arka planda tazeleme yok.
/// Listede yalnız özetler durur (ad, proje, yükleyen, tarih); paket içe
/// aktarılırken indirilir. Bağlantı kaydı `config.json` additive
/// `sessionServer`'da, token Keychain'de (`com.lumi.sessions`).
@Observable
@MainActor
public final class SessionShareStore {
    /// Popup açılışında listenin bayat sayıldığı yaş.
    public static let staleAfter: TimeInterval = 5 * 60

    public struct ConnectForm: Equatable, Sendable {
        public var address = ""
        public var token = ""
        public var isVerifying = false
        public var failure: SessionShareFailure?
        /// Var olan bağlantının token'ını/adresini yeniliyor.
        public var isReconnect = false

        public init() {}
    }

    public struct ExportDraft: Equatable, Sendable {
        public let entry: AgentHistoryEntry
        public var title: String
        public var project: String
        public var isUploading = false
        public var failure: SessionShareFailure?

        public var canUpload: Bool {
            !isUploading && !title.trimmed.isEmpty && !project.trimmed.isEmpty
        }
    }

    // MARK: - Durum

    public private(set) var server: SessionServer?
    public private(set) var info: SessionServerInfo?
    public private(set) var sessions: [SharedSession] = []
    public private(set) var lastRefreshedAt: Date?
    public private(set) var isRefreshing = false
    public private(set) var listFailure: SessionShareFailure?
    /// Token Keychain'de yok/okunamadı — popup bağlanma formunu açar.
    public private(set) var needsReconnect = false
    public private(set) var busySessionIDs: Set<String> = []

    public var isBrowserPresented = false
    public var connectForm: ConnectForm?
    public var exportDraft: ExportDraft?
    /// Sol panel: nil = All, aksi hâlde yükleyen kimliği.
    public var uploaderFilter: String?
    public var selectedSessionID: String?
    /// Silme onayı bekleyen oturum (popup içi satır onayı).
    public var confirmingDeleteID: String?

    public var isConnected: Bool { server != nil && client != nil }

    /// Sol panel: yükleyenler, ada göre; `me` en üstte.
    public var uploaders: [SharedSessionUploader] {
        var seen = Set<String>()
        let unique = sessions.map(\.uploader).filter { seen.insert($0.id).inserted }
        return unique.sorted { lhs, rhs in
            if lhs.id == info?.me.id { return true }
            if rhs.id == info?.me.id { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public var visibleSessions: [SharedSession] {
        guard let uploaderFilter else { return sessions }
        return sessions.filter { $0.uploader.id == uploaderFilter }
    }

    public func isMine(_ session: SharedSession) -> Bool {
        session.uploader.id == info?.me.id
    }

    @ObservationIgnored private let factory: any SessionSharingMaking
    @ObservationIgnored private let credentials: any SessionServerCredentialStoring
    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let history: AgentHistoryStore
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let makeID: @Sendable () -> String
    @ObservationIgnored private var client: (any SessionSharing)?

    public init(
        factory: any SessionSharingMaking,
        credentials: any SessionServerCredentialStoring,
        config: any ConfigServicing,
        history: AgentHistoryStore,
        toasts: ToastStore,
        now: @Sendable @escaping () -> Date = { Date() },
        makeID: @Sendable @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.factory = factory
        self.credentials = credentials
        self.config = config
        self.history = history
        self.toasts = toasts
        self.now = now
        self.makeID = makeID
    }

    // MARK: - Açılış (ağ yok)

    /// Kayıt + token okunur; istek atılmaz.
    public func load() async {
        guard let saved = await config.config().sessionServer else { return }
        server = saved
        guard case .success(let url) = TaskEndpoint.normalize(saved.baseURL) else {
            needsReconnect = true
            return
        }
        switch await credentials.token(for: saved.id) {
        case .found(let token):
            client = factory.makeClient(baseURL: url, token: token)
        case .missing, .failed:
            needsReconnect = true
        }
    }

    // MARK: - Popup

    /// `Import from Server`: bağlıysa ve liste 5 dakikadan eskiyse tazeler;
    /// bağlı değilse bağlanma formunu açar.
    public func openBrowser() {
        isBrowserPresented = true
        confirmingDeleteID = nil
        guard isConnected else {
            beginConnect(isReconnect: server != nil)
            return
        }
        connectForm = nil
        if let lastRefreshedAt, now().timeIntervalSince(lastRefreshedAt) < Self.staleAfter { return }
        Task { await refresh() }
    }

    public func closeBrowser() {
        isBrowserPresented = false
        connectForm = nil
        confirmingDeleteID = nil
    }

    public func refresh() async {
        guard let client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if info == nil { info = try await client.discover() }
            sessions = try await client.listSessions()
            lastRefreshedAt = now()
            listFailure = nil
            if let uploaderFilter, !sessions.contains(where: { $0.uploader.id == uploaderFilter }) {
                self.uploaderFilter = nil
            }
            if let selectedSessionID, !sessions.contains(where: { $0.id == selectedSessionID }) {
                self.selectedSessionID = nil
            }
        } catch is CancellationError {
            return
        } catch {
            listFailure = Self.failure(error)
        }
    }

    // MARK: - Bağlanma

    public func beginConnect(isReconnect: Bool = false) {
        var form = ConnectForm()
        form.isReconnect = isReconnect
        if isReconnect, let server { form.address = server.baseURL }
        connectForm = form
    }

    public func cancelConnect() {
        connectForm = nil
        if !isConnected { isBrowserPresented = false }
    }

    public var addressProblem: String? {
        guard let address = connectForm?.address, !address.trimmed.isEmpty,
              case .failure(let problem) = TaskEndpoint.normalize(address) else { return nil }
        return problem.message
    }

    public var canSubmitConnect: Bool {
        guard let form = connectForm, !form.isVerifying, !form.token.trimmed.isEmpty,
              case .success = TaskEndpoint.normalize(form.address) else { return false }
        return true
    }

    /// Discovery + liste geçerse kayıt ve token yazılır.
    public func connect() async {
        guard canSubmitConnect, let form = connectForm,
              case .success(let url) = TaskEndpoint.normalize(form.address) else { return }
        let token = form.token.trimmed
        connectForm?.isVerifying = true
        connectForm?.failure = nil
        let candidate = factory.makeClient(baseURL: url, token: token)
        do {
            let discovered = try await candidate.discover()
            let listed = try await candidate.listSessions()
            let record = SessionServer(
                id: server?.id ?? makeID(), name: discovered.name ?? url.host ?? url.absoluteString,
                baseURL: url.absoluteString
            )
            try await credentials.setToken(token, for: record.id)
            try await config.updateConfig { $0.sessionServer = record }
            server = record
            client = candidate
            info = discovered
            sessions = listed
            lastRefreshedAt = now()
            listFailure = nil
            needsReconnect = false
            uploaderFilter = nil
            connectForm = nil
            toasts.show(.success, title: "Connected to \(record.name)", message: "Signed in as \(discovered.me.name)")
        } catch {
            connectForm?.isVerifying = false
            connectForm?.failure = Self.failure(error)
        }
    }

    public func disconnect() async {
        guard let server else { return }
        try? await credentials.deleteToken(for: server.id)
        do {
            try await config.updateConfig { $0.sessionServer = nil }
        } catch {
            toasts.show(.error, title: "Couldn't save the disconnection", message: error.localizedDescription)
        }
        self.server = nil
        client = nil
        info = nil
        sessions = []
        lastRefreshedAt = nil
        listFailure = nil
        needsReconnect = false
        uploaderFilter = nil
        selectedSessionID = nil
        beginConnect()
    }

    // MARK: - İçe aktarma

    /// Paketi indirir ve `projectPath` için kurar (karar 52'nin yolu).
    @discardableResult
    public func importSession(_ id: String, into projectPath: String) async -> Bool {
        guard let client, !busySessionIDs.contains(id) else { return false }
        busySessionIDs.insert(id)
        defer { busySessionIDs.remove(id) }
        let data: Data
        do {
            data = try await client.download(sessionID: id)
        } catch {
            report(error, title: "Couldn't download the session")
            return false
        }
        return await history.importArchive(data, projectPath: projectPath) != nil
    }

    // MARK: - Silme (yalnız kendi yüklediklerim)

    public func deleteSession(_ id: String) async {
        confirmingDeleteID = nil
        guard let client, let session = sessions.first(where: { $0.id == id }), isMine(session),
              !busySessionIDs.contains(id) else { return }
        busySessionIDs.insert(id)
        defer { busySessionIDs.remove(id) }
        do {
            try await client.delete(sessionID: id)
            sessions.removeAll { $0.id == id }
            if selectedSessionID == id { selectedSessionID = nil }
            toasts.show(.success, title: "Session deleted from the server", message: session.title)
        } catch {
            report(error, title: "Couldn't delete the session")
        }
    }

    // MARK: - Dışa aktarma (onay penceresi)

    public func beginExport(_ entry: AgentHistoryEntry, projectName: String) {
        exportDraft = ExportDraft(entry: entry, title: entry.title, project: projectName)
        // Kullanıcı eylemi: "kim olarak yükleniyor" satırı için discovery.
        if isConnected, info == nil { Task { await discoverIfNeeded() } }
    }

    private func discoverIfNeeded() async {
        guard let client, info == nil else { return }
        info = try? await client.discover()
    }

    public func cancelExport() {
        guard exportDraft?.isUploading != true else { return }
        exportDraft = nil
    }

    /// Bağlantı yokken onay penceresinden kurulum popup'ına geçiş.
    public func setUpServerFromExport() {
        exportDraft = nil
        openBrowser()
    }

    public func confirmExport() async {
        guard let client, let draft = exportDraft, draft.canUpload else { return }
        exportDraft?.isUploading = true
        exportDraft?.failure = nil
        do {
            if info == nil { info = try await client.discover() }
            let archive = try await history.exportArchive(draft.entry)
            if let limit = info?.maxUploadBytes, archive.count > limit {
                throw SessionShareFailure(
                    kind: .tooLarge,
                    serverMessage: "The session is \(Self.megabytes(archive.count)); the server accepts up to \(Self.megabytes(limit))."
                )
            }
            let uploaded = try await client.upload(SharedSessionUpload(
                title: draft.title.trimmed, project: draft.project.trimmed,
                provider: draft.entry.provider, archive: archive
            ))
            sessions.removeAll { $0.id == uploaded.id }
            sessions.insert(uploaded, at: 0)
            exportDraft = nil
            toasts.show(.success, title: "Session uploaded", message: "\(uploaded.title) · \(uploaded.project)")
        } catch {
            exportDraft?.isUploading = false
            exportDraft?.failure = Self.failure(error)
        }
    }

    // MARK: - Yardımcılar

    private func report(_ error: any Error, title: String) {
        let failure = Self.failure(error)
        if failure.kind == .unauthorized { listFailure = failure }
        toasts.show(.error, title: title, message: failure.summary)
    }

    static func failure(_ error: any Error) -> SessionShareFailure {
        if let failure = error as? SessionShareFailure { return failure }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return SessionShareFailure(kind: .unreachable(message))
    }

    static func megabytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
