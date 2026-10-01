import Foundation
import LumiKit

/// Claude hesaplarının tek yetkili sahibi (karar 56).
///
/// Sıralı erişim şart olduğu için `actor`: iki hesap değişimi iç içe girerse
/// yüzeye yarım kimlik bilgisi yazılır. Hesap listesi `config.json`'da,
/// token'lar `ClaudeManagedAuthStore`'da (Keychain) yaşar; bu tip ikisini
/// tutarlı tutar.
///
/// **Bilinçli kapsam dışı (Orca'da var):** proaktif OAuth token yenileme.
/// Orca, tek kullanımlık refresh token'ı kendi döndürüp saklıyor; Lumi
/// yenilemeyi CLI'a bırakır ve döndürülen token'ı "geri okuma" ile yönetilen
/// depoya yazar. Sonuç: süresi dolmuş bir hesapta kullanım göstergesi, o hesap
/// altında bir terminal açılana kadar hata verebilir.
public actor ClaudeAccountService: ClaudeAccountServicing {
    private let config: any ConfigServicing
    private let store: ClaudeManagedAuthStore
    private let surface: ClaudeAuthSurface
    private let login: ClaudeLoginSession
    private let now: @Sendable () -> Date
    private var pendingLogin: Task<ClaudeLoginSession.Result, Error>?
    /// Yüzeye EN SON Lumi'nin yazdığı kimlik bilgisi. Sahiplik kanıtı:
    /// yüzeydeki değer bundan farklıysa araya dışarıdan bir login girmiştir ve
    /// üzerine yazmak kullanıcının taze oturumunu silmek olur.
    private var lastWrittenCredentialsJSON: String?

    public init(
        config: any ConfigServicing,
        paths: LumiPaths,
        keychain: any KeychainAccessing = SecurityKeychain(),
        runner: any EnvironmentProcessRunning = SystemProcessRunner(),
        locator: any BinaryLocating = SystemBinaryLocator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            config: config,
            store: ClaudeManagedAuthStore(keychain: keychain, root: paths.claudeAccountsDir),
            surface: ClaudeAuthSurface(keychain: keychain),
            login: ClaudeLoginSession(runner: runner, locator: locator, keychain: keychain),
            now: now
        )
    }

    init(
        config: any ConfigServicing,
        store: ClaudeManagedAuthStore,
        surface: ClaudeAuthSurface,
        login: ClaudeLoginSession,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.store = store
        self.surface = surface
        self.login = login
        self.now = now
    }

    // MARK: - Okuma

    public func accounts() async -> ClaudeAccountsSnapshot {
        let config = await config.config()
        return ClaudeAccountsSnapshot(
            accounts: config.claudeAccounts.sorted { $0.createdAt < $1.createdAt },
            selection: config.claudeAccountSelection,
            systemDefaultEmail: systemDefaultEmail(for: config.claudeAccountSelection)
        )
    }

    /// Sistem login'inin kimliği token'sız kaynaklardan okunur: varsayılan
    /// seçiliyken yüzeyin kendisi (`.claude.json` ▸ `oauthAccount`), yönetilen
    /// bir hesaptayken yakalanmış snapshot'ın marker'ı. Keychain'e dokunulmaz.
    private func systemDefaultEmail(for selection: ClaudeAccountSelection) -> String? {
        let oauthAccountJSON = selection == .systemDefault
            ? surface.readOauthAccount()
            : store.systemDefaultOauthAccountJSON()
        return ClaudeIdentity.resolve(
            statusJSON: nil, oauthAccountJSON: oauthAccountJSON, credentialsJSON: nil
        ).email
    }

    /// Uygulama açılışında çağrılır.
    ///
    /// **Önce geri okuma, sonra gerekiyorsa materialize.** Lumi kapalıyken CLI
    /// token'ı yenilemiş olabilir; refresh token tek kullanımlıktır ve dönerek
    /// yenilenir, yani depodaki eski blob'u körlemesine yüzeye yazmak o hesabı
    /// `invalid_grant` ile oturumdan düşürürdü. Yüzey zaten doğru kopyayı
    /// taşıyorsa hiçbir dosyaya dokunulmaz.
    public func syncActiveSelection() async {
        let snapshot = await accounts()
        guard let account = snapshot.activeAccount else { return }
        do {
            await readBackRefreshedCredentials(for: account)
            let managed = try await store.readSnapshot(accountID: account.id)
            if case let .available(live) = await surface.read(),
               live.credentialsJSON == managed.credentialsJSON {
                lastWrittenCredentialsJSON = managed.credentialsJSON
                return
            }
            try await materialize(account)
        } catch {
            // Sessiz: kullanıcı hesabı Settings'ten yeniden seçerse hata görünür.
        }
    }

    // MARK: - Ekleme / yeniden doğrulama

    public func addAccount() async throws -> ClaudeAccountsSnapshot {
        let result = try await runLogin()
        let email = result.identity.email ?? ""
        let existing = await config.config().claudeAccounts
        guard !existing.contains(where: {
            $0.isSameIdentity(email: email, organizationUUID: result.identity.organizationUUID)
        }) else {
            throw LumiError.claudeAccountFailed(
                operation: "add", detail: "\(email) is already added."
            )
        }
        let timestamp = now()
        let account = ClaudeAccount(
            id: UUID().uuidString,
            email: email,
            organizationUUID: result.identity.organizationUUID,
            organizationName: result.identity.organizationName,
            createdAt: timestamp,
            updatedAt: timestamp,
            lastAuthenticatedAt: timestamp
        )
        try await store.write(result.snapshot, accountID: account.id)
        try await config.updateConfig { $0.claudeAccounts.append(account) }
        return await accounts()
    }

    public func reauthenticate(accountID: String) async throws -> ClaudeAccountsSnapshot {
        let snapshot = await accounts()
        guard let account = snapshot.accounts.first(where: { $0.id == accountID }) else {
            throw LumiError.claudeAccountFailed(operation: "re-authenticate", detail: "account no longer exists")
        }
        let result = try await runLogin()
        let email = result.identity.email ?? account.email
        guard account.isSameIdentity(email: email, organizationUUID: result.identity.organizationUUID)
            || result.identity.organizationUUID == nil else {
            throw LumiError.claudeAccountFailed(
                operation: "re-authenticate",
                detail: "signed in as \(email), but this row belongs to \(account.email)"
            )
        }
        // Yazmadan önceki kopya: config güncellemesi patlarsa depo eski
        // hâline döner, yoksa kimlik kartı ile token'lar ayrışırdı.
        let previous = try? await store.readSnapshot(accountID: accountID)
        try await store.write(result.snapshot, accountID: accountID)
        let timestamp = now()
        do {
            try await config.updateConfig { config in
                guard let index = config.claudeAccounts.firstIndex(where: { $0.id == accountID })
                else { return }
                config.claudeAccounts[index].email = email
                config.claudeAccounts[index].organizationUUID = result.identity.organizationUUID
                config.claudeAccounts[index].organizationName = result.identity.organizationName
                config.claudeAccounts[index].updatedAt = timestamp
                config.claudeAccounts[index].lastAuthenticatedAt = timestamp
            }
        } catch {
            if let previous { try? await store.write(previous, accountID: accountID) }
            throw error
        }
        // Aktif hesap yeniden doğrulandıysa taze token hemen yüzeye iner.
        if snapshot.selection == .account(accountID) {
            try await surface.write(result.snapshot)
            lastWrittenCredentialsJSON = result.snapshot.credentialsJSON
        }
        return await accounts()
    }

    public func cancelPendingLogin() async {
        pendingLogin?.cancel()
    }

    // MARK: - Silme / seçim

    public func removeAccount(accountID: String) async throws -> ClaudeAccountsSnapshot {
        let snapshot = await accounts()
        guard snapshot.accounts.contains(where: { $0.id == accountID }) else { return snapshot }
        // Aktif hesabı silmek önce yüzeyi sistem varsayılanına döndürür;
        // aksi halde silinmiş bir hesabın token'ı yüzeyde kalırdı.
        if snapshot.selection == .account(accountID) {
            try await restoreSystemDefault()
            try await config.updateConfig { $0.claudeAccountSelection = .systemDefault }
        }
        try await store.remove(accountID: accountID)
        try await config.updateConfig { config in
            config.claudeAccounts.removeAll { $0.id == accountID }
        }
        return await accounts()
    }

    public func select(_ selection: ClaudeAccountSelection) async throws -> ClaudeAccountsSnapshot {
        let snapshot = await accounts()
        // Aynı seçime tekrar basmak normalde no-op'tur; AMA yüzey o seçimle
        // uyuşmuyorsa (önceki geçiş yarıda kalmıştı) yeniden uygulanır —
        // aksi halde kullanıcı hiçbir butonun işe yaramadığı bir durumda
        // sıkışırdı.
        if selection == snapshot.selection, await isSurfaceConsistent(with: selection, in: snapshot) {
            return snapshot
        }
        // Ayrılmadan önce CLI'ın tazelediği token'ları hesabın kendi deposuna
        // geri yaz — yoksa bir sonraki geçişte bayat token materialize edilirdi.
        if let outgoing = snapshot.activeAccount {
            await readBackRefreshedCredentials(for: outgoing)
        }
        do {
            switch selection {
            case let .account(id):
                guard let account = snapshot.accounts.first(where: { $0.id == id }) else {
                    throw LumiError.claudeAccountFailed(
                        operation: "switch", detail: "account no longer exists"
                    )
                }
                try await materialize(account)
            case .systemDefault:
                try await restoreSystemDefault()
            }
        } catch {
            // Yüzey yarıda kalmış olabilir: eski seçimi yeniden uygula, böylece
            // kullanıcı ne UI'da ne de CLI'da tutarsız bir hâlde kalmaz.
            await rollbackSurface(to: snapshot)
            throw error
        }
        try await config.updateConfig { $0.claudeAccountSelection = selection }
        return await accounts()
    }

    /// Yüzeydeki kimlik bilgisi verilen seçimin beklediği kopya mı?
    /// Okunamıyorsa "tutarlı" sayılır: kilitli bir keychain yüzünden
    /// kendiliğinden yazma başlatmayalım.
    private func isSurfaceConsistent(
        with selection: ClaudeAccountSelection, in snapshot: ClaudeAccountsSnapshot
    ) async -> Bool {
        guard case let .account(id) = selection,
              let account = snapshot.accounts.first(where: { $0.id == id }),
              let managed = try? await store.readSnapshot(accountID: account.id),
              case let .available(live) = await surface.read() else { return true }
        return live.credentialsJSON == managed.credentialsJSON
    }

    /// Hata sonrası yüzeyi ESKİ seçime döndürme denemesi (en iyi çaba —
    /// buradaki ikinci bir hata, asıl hatayı gölgelememeli).
    private func rollbackSurface(to snapshot: ClaudeAccountsSnapshot) async {
        do {
            if let account = snapshot.activeAccount {
                try await materialize(account)
            } else {
                try await restoreSystemDefault()
            }
        } catch {
            // Yutulur: asıl hata çağırana gider, kullanıcı tekrar deneyebilir.
        }
    }

    // MARK: - Yüzey işlemleri

    private func materialize(_ account: ClaudeAccount) async throws {
        let managed = try await store.readSnapshot(accountID: account.id)
        guard ClaudeIdentity.isValidCredentials(managed.credentialsJSON) else {
            throw LumiError.claudeAccountFailed(
                operation: "switch",
                detail: "\(account.email) has no stored credentials — re-authenticate it."
            )
        }
        guard case let .available(live) = await surface.read() else {
            throw LumiError.claudeAccountFailed(
                operation: "switch",
                detail: "the macOS Keychain could not be read — unlock it and try again"
            )
        }
        // Kullanıcının KENDİ oturumu saklanır. Yüzeydeki değer ne bizim son
        // yazdığımız ne de materialize edilecek kopya ise, araya dışarıdan bir
        // login girmiştir: snapshot tazelenir, yoksa `System default` çok eski
        // bir oturumu geri getirirdi.
        let isForeign = live.credentialsJSON != nil
            && live.credentialsJSON != lastWrittenCredentialsJSON
            && live.credentialsJSON != managed.credentialsJSON
        try await store.captureSystemDefault(live, force: isForeign)
        try await surface.write(managed)
        lastWrittenCredentialsJSON = managed.credentialsJSON
    }

    /// Sistem varsayılanına dönüş.
    ///
    /// İki kapı: (1) yakalanmış bir varsayılan yoksa yüzeye DOKUNULMAZ —
    /// boşaltmak kullanıcıyı hiç istemediği bir oturum kapatmaya sürüklerdi;
    /// (2) yüzeydeki kimlik bilgisi bizim son yazdığımız değilse araya
    /// dışarıdan bir login girmiştir, o oturum yeni varsayılan sayılır ve
    /// snapshot yalnız temizlenir.
    private func restoreSystemDefault() async throws {
        guard let snapshot = try await store.systemDefaultSnapshot() else { return }
        guard case let .available(live) = await surface.read() else {
            throw LumiError.claudeAccountFailed(
                operation: "switch",
                detail: "the macOS Keychain could not be read — unlock it and try again"
            )
        }
        let isForeign = live.credentialsJSON != nil
            && lastWrittenCredentialsJSON != nil
            && live.credentialsJSON != lastWrittenCredentialsJSON
        if !isForeign {
            try await surface.write(snapshot)
        }
        try await store.clearSystemDefaultSnapshot()
        lastWrittenCredentialsJSON = nil
    }

    /// Yüzeydeki kimlik bilgisi yönetilen kopyadan farklıysa CLI onu
    /// tazelemiştir ve hesabın deposuna geri yazılır.
    ///
    /// Kimlik kanıtı sırası: (1) blob'un kendi içindeki e-posta/organizasyon,
    /// (2) yoksa `oauthAccount` karşılaştırması. İkisi de kanıt vermiyorsa
    /// yazılmaz — kullanıcı terminalde elle başka bir hesaba geçmiş olabilir.
    /// Ayrıca ESKİ bir blob yeninin üstüne yazılmaz (`expiresAt`).
    private func readBackRefreshedCredentials(for account: ClaudeAccount) async {
        guard let managed = try? await store.readSnapshot(accountID: account.id),
              case let .available(live) = await surface.read(),
              let credentials = live.credentialsJSON,
              credentials != managed.credentialsJSON,
              ClaudeIdentity.isValidCredentials(credentials) else { return }
        guard Self.credentialsBelong(to: account, credentials: credentials, managed: managed, live: live)
        else { return }
        let managedExpiry = ClaudeIdentity.expiresAt(managed.credentialsJSON)
        let liveExpiry = ClaudeIdentity.expiresAt(credentials)
        if let managedExpiry, let liveExpiry, liveExpiry < managedExpiry { return }
        try? await store.write(
            ClaudeAuthSurface.Snapshot(
                credentialsJSON: credentials,
                oauthAccountJSON: live.oauthAccountJSON ?? managed.oauthAccountJSON
            ),
            accountID: account.id
        )
    }

    /// Geri okuma kimlik kapısı (saf — test edilebilir).
    static func credentialsBelong(
        to account: ClaudeAccount,
        credentials: String,
        managed: ClaudeAuthSurface.Snapshot,
        live: ClaudeAuthSurface.Snapshot
    ) -> Bool {
        let identity = ClaudeIdentity.credentialIdentity(credentials)
        if let email = identity.email {
            guard email.caseInsensitiveCompare(account.email) == .orderedSame else { return false }
            guard let accountOrganization = account.organizationUUID else { return true }
            return identity.organizationUUID == nil
                || identity.organizationUUID == accountOrganization
        }
        // Blob kimlik taşımıyor → `oauthAccount` kanıtı. Yönetilen tarafta da
        // kanıt yoksa doğrulanamaz sayılır ve yazılmaz.
        guard let managedOauth = managed.oauthAccountJSON else { return false }
        return managedOauth == live.oauthAccountJSON
    }

    private func runLogin() async throws -> ClaudeLoginSession.Result {
        if pendingLogin != nil {
            throw LumiError.claudeAccountFailed(operation: "login", detail: "a sign-in is already running")
        }
        let session = login
        let task = Task { try await session.run() }
        pendingLogin = task
        defer { pendingLogin = nil }
        return try await task.value
    }
}
