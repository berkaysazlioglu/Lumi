import Foundation
import LumiKit

/// Lumi'nin yönettiği kimlik bilgilerinin deposu (karar 56).
///
/// Token'lar Keychain'de (`Lumi Claude Managed Credentials` servisi, hesap adı
/// = hesap id'si), token OLMAYAN `oauthAccount` bloğu ise
/// `~/.lumi/claude-accounts/<id>/auth/oauth-account.json` içinde 0600 ile
/// durur. Disk tarafında hiçbir zaman token yazılmaz.
///
/// Ayrıca "sistem varsayılanı" anlık görüntüsünü tutar: ilk kez yönetilen bir
/// hesaba geçerken kullanıcının KENDİ `~/.claude` oturumu buraya alınır,
/// `System default`'a dönüldüğünde aynen geri yazılır.
struct ClaudeManagedAuthStore: Sendable {
    /// Sistem varsayılanının Keychain'deki hesap adı. Hesap id'leri UUID
    /// olduğu için çakışmaz.
    static let systemDefaultKey = "__lumi-system-default__"
    private static let systemDefaultDirectoryName = "system-default"
    private static let systemDefaultMarkerName = "snapshot.json"

    private let keychain: any KeychainAccessing
    private let root: URL

    init(keychain: any KeychainAccessing, root: URL) {
        self.keychain = keychain
        self.root = root
    }

    // MARK: - Hesap başına

    /// Okuma hatası (kilitli keychain) "kimlik bilgisi yok" ile karışmasın
    /// diye fırlatır: çağıran, eksik bir kopyayı yüzeye yazmaya kalkamaz.
    func readSnapshot(accountID: String) async throws -> ClaudeAuthSurface.Snapshot {
        let credentials = await keychain.password(
            service: ClaudeAuthLocations.managedKeychainService, account: accountID
        )
        if case let .failed(detail) = credentials {
            throw LumiError.claudeAccountFailed(operation: "read", detail: detail)
        }
        return ClaudeAuthSurface.Snapshot(
            credentialsJSON: credentials.value,
            oauthAccountJSON: readOauthAccount(accountID: accountID)
        )
    }

    func write(_ snapshot: ClaudeAuthSurface.Snapshot, accountID: String) async throws {
        if let credentials = snapshot.credentialsJSON {
            try await keychain.setPassword(
                credentials,
                service: ClaudeAuthLocations.managedKeychainService,
                account: accountID
            )
        } else {
            try await keychain.deletePassword(
                service: ClaudeAuthLocations.managedKeychainService, account: accountID
            )
        }
        try writeOauthAccount(snapshot.oauthAccountJSON, accountID: accountID)
    }

    func remove(accountID: String) async throws {
        try await keychain.deletePassword(
            service: ClaudeAuthLocations.managedKeychainService, account: accountID
        )
        // Kök dışına çıkabilecek bir id burada zaten `nil` döner; silme
        // yalnız `<root>/<uuid>/` üzerinde çalışır.
        guard let authDirectory = ClaudeAuthLocations.managedAuthDirectory(
            accountID: accountID, root: root
        ) else { return }
        let directory = authDirectory.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Sistem varsayılanı

    /// Sistem varsayılanını yakalar.
    ///
    /// **Sıra bilinçli:** önce "yakalama başladı" işareti, sonra Keychain
    /// kaydı, en sonda işaretin tamamlanması. Yarıda kalan bir yakalama
    /// (çökme, reddedilen keychain yazımı) TAMAMLANMAMIŞ sayılır ve bir
    /// sonraki denemede yeniden yapılır — ters sırada, yarım kalan kayıt
    /// "sistem varsayılanı" diye okunup kullanıcının gerçek oturumunun yerine
    /// geçerdi.
    ///
    /// `force` ile yüzey kaydığında (kullanıcı terminalde elle login oldu)
    /// snapshot tazelenir.
    func captureSystemDefault(
        _ snapshot: ClaudeAuthSurface.Snapshot, force: Bool = false
    ) async throws {
        if !force, await hasCompleteSystemDefaultSnapshot() { return }
        try writeSystemDefaultMarker(snapshot, isComplete: false)
        if let credentials = snapshot.credentialsJSON {
            try await keychain.setPassword(
                credentials,
                service: ClaudeAuthLocations.managedKeychainService,
                account: Self.systemDefaultKey
            )
        } else {
            try await keychain.deletePassword(
                service: ClaudeAuthLocations.managedKeychainService,
                account: Self.systemDefaultKey
            )
        }
        try writeSystemDefaultMarker(snapshot, isComplete: true)
    }

    /// Tamamlanmış bir snapshot var mı? Marker'ın `complete` bayrağı ve —
    /// kimlik bilgisi bekleniyorsa — Keychain kaydının gerçekten okunabilir
    /// olması birlikte aranır.
    func hasCompleteSystemDefaultSnapshot() async -> Bool {
        guard let marker = readSystemDefaultMarker(), marker.isComplete else { return false }
        guard marker.hasCredentials else { return true }
        return await keychain.password(
            service: ClaudeAuthLocations.managedKeychainService, account: Self.systemDefaultKey
        ).value != nil
    }

    /// Yakalanmış sistem varsayılanı. Kimlik bilgisi beklenip de
    /// OKUNAMIYORSA fırlatır — `nil` dönmek, geri yüklemede yüzeyi
    /// boşaltmaya (kullanıcının oturumunu silmeye) yol açardı.
    func systemDefaultSnapshot() async throws -> ClaudeAuthSurface.Snapshot? {
        guard let marker = readSystemDefaultMarker(), marker.isComplete else { return nil }
        guard marker.hasCredentials else {
            return ClaudeAuthSurface.Snapshot(
                credentialsJSON: nil, oauthAccountJSON: marker.oauthAccountJSON
            )
        }
        switch await keychain.password(
            service: ClaudeAuthLocations.managedKeychainService, account: Self.systemDefaultKey
        ) {
        case let .found(credentials):
            return ClaudeAuthSurface.Snapshot(
                credentialsJSON: credentials, oauthAccountJSON: marker.oauthAccountJSON
            )
        case .missing:
            throw LumiError.claudeAccountFailed(
                operation: "restore", detail: "the saved system login is missing from the Keychain"
            )
        case let .failed(detail):
            throw LumiError.claudeAccountFailed(operation: "restore", detail: detail)
        }
    }

    /// Yakalanmış sistem varsayılanının token'sız `oauthAccount` bloğu —
    /// yalnız kimlik göstermek için; Keychain okunmaz.
    func systemDefaultOauthAccountJSON() -> String? {
        guard let marker = readSystemDefaultMarker(), marker.isComplete else { return nil }
        return marker.oauthAccountJSON
    }

    /// Sistem varsayılanına dönülüp yüzey geri yazıldıktan sonra çağrılır:
    /// snapshot tüketilmiştir, bir sonraki geçişte güncel hâl yakalanmalıdır.
    func clearSystemDefaultSnapshot() async throws {
        try await keychain.deletePassword(
            service: ClaudeAuthLocations.managedKeychainService,
            account: Self.systemDefaultKey
        )
        let url = systemDefaultMarkerURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Dosya tarafı

    /// Snapshot marker'ı: yakalamanın TAMAMLANIP tamamlanmadığını ve
    /// Keychain'de kimlik bilgisi beklenip beklenmediğini söyler.
    private struct SystemDefaultMarker {
        let hasCredentials: Bool
        let oauthAccountJSON: String?
        let isComplete: Bool
    }

    private func readSystemDefaultMarker() -> SystemDefaultMarker? {
        guard let data = FileManager.default.contents(atPath: systemDefaultMarkerURL.path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return SystemDefaultMarker(
            hasCredentials: (object["hasCredentials"] as? NSNumber)?.boolValue ?? false,
            oauthAccountJSON: object["oauthAccount"] as? String,
            // Eski (sertleştirme öncesi) marker'da bayrak yoktur; o dosyalar
            // tamamlanmış sayılır, aksi hâlde mevcut yedek görünmez olurdu.
            isComplete: (object["complete"] as? NSNumber)?.boolValue ?? true
        )
    }

    private func writeSystemDefaultMarker(
        _ snapshot: ClaudeAuthSurface.Snapshot, isComplete: Bool
    ) throws {
        let marker: [String: Any] = [
            "hasCredentials": snapshot.credentialsJSON != nil,
            "oauthAccount": snapshot.oauthAccountJSON ?? NSNull(),
            "complete": isComplete,
            "capturedAt": Date().timeIntervalSince1970,
        ]
        let url = systemDefaultMarkerURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted])
            .write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private var systemDefaultMarkerURL: URL {
        root.appendingPathComponent(Self.systemDefaultDirectoryName)
            .appendingPathComponent(Self.systemDefaultMarkerName)
    }

    private func oauthAccountURL(accountID: String) -> URL? {
        ClaudeAuthLocations.managedAuthDirectory(accountID: accountID, root: root)?
            .appendingPathComponent(ClaudeAuthLocations.oauthAccountFileName)
    }

    private func readOauthAccount(accountID: String) -> String? {
        guard let url = oauthAccountURL(accountID: accountID),
              let data = FileManager.default.contents(atPath: url.path)
        else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    private func writeOauthAccount(_ json: String?, accountID: String) throws {
        guard let url = oauthAccountURL(accountID: accountID) else {
            throw LumiError.claudeAccountFailed(
                operation: "store", detail: "invalid account id"
            )
        }
        guard let json else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data(json.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
