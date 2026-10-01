import Foundation

/// Claude hesaplarının eklenmesi/silinmesi/seçilmesi (karar 56).
///
/// Servis, seçilen hesabın kimlik bilgisini Claude Code'un okuduğu "aktif
/// yüzeye" (Keychain + `~/.claude`) materialize eder; store yalnız sonucu
/// görür. Her çağrı güncel listeyi + seçimi döndürür, böylece UI ayrı bir
/// okuma turuna girmez.
public protocol ClaudeAccountServicing: Sendable {
    /// Kayıtlı hesaplar + aktif seçim. Seçim diskteki hesaplara göre
    /// doğrulanır (silinmiş id sistem varsayılanına düşer).
    func accounts() async -> ClaudeAccountsSnapshot

    /// Yeni hesap ekler: yalıtılmış bir `CLAUDE_CONFIG_DIR` altında
    /// `claude auth login` koşar, kimliği yakalar ve hesabı kaydeder.
    /// Zaten ekli bir hesap (e-posta + organizasyon) reddedilir.
    func addAccount() async throws -> ClaudeAccountsSnapshot

    /// Süren `addAccount`/`reauthenticate` login'ini iptal eder.
    func cancelPendingLogin() async

    /// Var olan hesabı yeniden doğrular (token'lar yenilenir, kimlik güncellenir).
    func reauthenticate(accountID: String) async throws -> ClaudeAccountsSnapshot

    /// Hesabı ve kimlik bilgisini siler. Aktif hesap silinirse seçim sistem
    /// varsayılanına döner ve yüzey geri yüklenir.
    func removeAccount(accountID: String) async throws -> ClaudeAccountsSnapshot

    /// Açılışta seçili hesabı aktif yüzeye yeniden materialize eder
    /// (başka bir araç üzerine yazmış olabilir). Hata yutulur.
    func syncActiveSelection() async

    /// Seçimi değiştirir ve kimlik bilgisini aktif yüzeye materialize eder.
    func select(_ selection: ClaudeAccountSelection) async throws -> ClaudeAccountsSnapshot
}

/// Servisin UI'a döndürdüğü tam durum.
public struct ClaudeAccountsSnapshot: Sendable, Equatable {
    public let accounts: [ClaudeAccount]
    public let selection: ClaudeAccountSelection
    /// Mac'teki kendi Claude login'inin e-postası (`System default` satırı
    /// adıyla görünsün diye). Okunamazsa `nil`.
    public let systemDefaultEmail: String?

    public init(
        accounts: [ClaudeAccount],
        selection: ClaudeAccountSelection,
        systemDefaultEmail: String? = nil
    ) {
        self.accounts = accounts
        self.selection = selection
        self.systemDefaultEmail = systemDefaultEmail
    }

    public static let empty = ClaudeAccountsSnapshot(accounts: [], selection: .systemDefault)

    public var activeAccount: ClaudeAccount? {
        selection.accountID.flatMap { id in accounts.first { $0.id == id } }
    }
}
