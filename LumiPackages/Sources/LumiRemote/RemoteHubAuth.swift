import CommonCrypto
import Foundation
import LumiKit

/// Hub şifresinin diskteki biçimi (docs/design/08): düz şifre hiçbir yere yazılmaz,
/// Keychain'de `pbkdf2-sha256$<iterasyon>$<salt b64>$<hash b64>` durur.
public enum HubPasswordHash {
    static let scheme = "pbkdf2-sha256"
    public static let defaultIterations = 120_000
    static let saltLength = 16
    static let hashLength = 32

    /// Rastgele salt'la yeni kayıt üretir.
    public static func make(password: String, iterations: Int = defaultIterations) -> String? {
        var salt = [UInt8](repeating: 0, count: saltLength)
        guard SecRandomCopyBytes(kSecRandomDefault, saltLength, &salt) == errSecSuccess,
              let hash = derive(password: password, salt: salt, iterations: iterations) else { return nil }
        return [scheme, String(iterations), Data(salt).base64EncodedString(), Data(hash).base64EncodedString()]
            .joined(separator: "$")
    }

    /// Şifre kayda uyuyor mu? Bozuk kayıt her zaman `false` döner. Karşılaştırma sabit zamanlıdır.
    public static func verify(password: String, record: String) -> Bool {
        let parts = record.split(separator: "$", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == scheme,
              let iterations = Int(parts[1]), iterations > 0,
              let salt = Data(base64Encoded: String(parts[2])),
              let expected = Data(base64Encoded: String(parts[3])),
              let actual = derive(password: password, salt: [UInt8](salt), iterations: iterations),
              actual.count == expected.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(actual, expected) { difference |= a ^ b }
        return difference == 0
    }

    private static func derive(password: String, salt: [UInt8], iterations: Int) -> [UInt8]? {
        let passwordBytes = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: hashLength)
        let status = passwordBytes.withUnsafeBufferPointer { pw in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pw.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                pw.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &out, out.count
            )
        }
        return status == kCCSuccess ? out : nil
    }
}

public enum RemoteHubError: Error, Equatable {
    case emptyPassword
    case hashFailed
    /// Hub olarak paylaşmak için ağ token'ı ve şifre gerekir.
    case notConfigured
}

/// Hub'ın Keychain'deki iki gizli kaydı: şifre hash'i ve relay'de kimliği sahiplenen `hubKey`.
public struct RemoteHubSecrets: Sendable {
    public static let service = "com.lumi.remote-hub"
    static let passwordAccount = "password"
    static let hubKeyAccount = "hub-key"

    private let keychain: any KeychainAccessing

    public init(keychain: any KeychainAccessing) {
        self.keychain = keychain
    }

    public func passwordRecord() async -> KeychainReadResult {
        await keychain.password(service: Self.service, account: Self.passwordAccount)
    }

    /// Yeni şifrenin hash'ini yazar. Boş şifre kabul edilmez.
    public func setPassword(_ password: String) async throws {
        guard !password.isEmpty else { throw RemoteHubError.emptyPassword }
        guard let record = HubPasswordHash.make(password: password) else { throw RemoteHubError.hashFailed }
        try await keychain.setPassword(record, service: Self.service, account: Self.passwordAccount)
    }

    public func removePassword() async throws {
        try await keychain.deletePassword(service: Self.service, account: Self.passwordAccount)
    }

    /// Kayıtlı `hubKey`; yoksa üretip yazar. Okunamıyorsa (`failed`) `nil` — yeni anahtar
    /// ÜRETİLMEZ, yoksa relay'deki kimlik bu kurulumun elinden giderdi.
    public func hubKey() async -> String? {
        switch await keychain.password(service: Self.service, account: Self.hubKeyAccount) {
        case .found(let key):
            return key
        case .failed:
            return nil
        case .missing:
            let key = generateToken()
            do {
                try await keychain.setPassword(key, service: Self.service, account: Self.hubKeyAccount)
                return key
            } catch {
                rlog("hub: hubKey Keychain'e yazılamadı: \(error)")
                return nil
            }
        }
    }
}

/// Aynı controller'dan art arda yanlış şifreye kısa kilit (relay'in IP sınırına ek).
struct HubAttemptLimiter {
    static let maxFailures = 5
    static let window: TimeInterval = 60
    static let lockout: TimeInterval = 60

    private var failures: [String: [Date]] = [:]
    private var lockedUntil: [String: Date] = [:]

    func isLocked(_ controllerId: String, now: Date) -> Bool {
        guard let until = lockedUntil[controllerId] else { return false }
        return until > now
    }

    mutating func recordFailure(_ controllerId: String, now: Date) {
        let recent = (failures[controllerId] ?? []).filter { now.timeIntervalSince($0) < Self.window } + [now]
        if recent.count >= Self.maxFailures {
            lockedUntil[controllerId] = now.addingTimeInterval(Self.lockout)
            failures[controllerId] = nil
        } else {
            failures[controllerId] = recent
        }
    }

    mutating func recordSuccess(_ controllerId: String) {
        failures[controllerId] = nil
        lockedUntil[controllerId] = nil
    }
}
