import Foundation
import Security

/// A Mac pairing (decision 146): the relay server, the server token that opens it
/// (`Authorization: Bearer` on the handshake) and the Mac's room token.
public struct PairingInfo: Sendable, Equatable {
    public let relayUrl: String
    public let token: String
    public let serverToken: String

    public init(relayUrl: String, token: String, serverToken: String) {
        self.relayUrl = relayUrl
        self.token = token
        self.serverToken = serverToken
    }
}

public enum PairingError: Error, Sendable, Equatable {
    /// Not a Lumi pairing link at all.
    case invalid
    /// A pairing link from a Mac without decision 146 (no server token).
    case outdatedMac

    public var message: String {
        switch self {
        case .invalid: return "Couldn't resolve the connection. It must be in the form `lumi-remote://pair?...`."
        case .outdatedMac: return "This QR is from an older Lumi. Update Lumi on the Mac, connect it to a server, then scan again."
        }
    }
}

public enum Pairing {
    /// `lumi-remote://pair?url=<pct>&token=<pct>&stoken=<pct>` → PairingInfo.
    /// URLComponents percent-decodes the query values automatically.
    public static func parse(_ string: String) -> PairingInfo? {
        try? parseResult(string).get()
    }

    public static func parseResult(_ string: String) -> Result<PairingInfo, PairingError> {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme == "lumi-remote",
              components.host == "pair",
              let items = components.queryItems,
              let url = items.first(where: { $0.name == "url" })?.value,
              let token = items.first(where: { $0.name == "token" })?.value,
              token.count >= 16,
              url.hasPrefix("wss://") || url.hasPrefix("ws://")
        else { return .failure(.invalid) }
        let serverToken = items.first(where: { $0.name == "stoken" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !serverToken.isEmpty, !serverToken.contains(where: \.isWhitespace) else {
            return .failure(.outdatedMac)
        }
        return .success(PairingInfo(relayUrl: url, token: token, serverToken: serverToken))
    }

    /// Whether the scanner should stop on this code: a usable link, or one whose
    /// error is worth showing (an older Mac's QR).
    public static func isPairingLink(_ string: String) -> Bool {
        if case .failure(.invalid) = parseResult(string) { return false }
        return true
    }
}

/// Secure storage for pairing info. Keychain in production; in-memory in tests.
public protocol SecureStore: Sendable {
    func read() -> PairingInfo?
    func write(_ info: PairingInfo)
    func clear()
}

public final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PairingInfo?

    public init() {}

    public func read() -> PairingInfo? { lock.withLock { stored } }
    public func write(_ info: PairingInfo) { lock.withLock { stored = info } }
    public func clear() { lock.withLock { stored = nil } }
}

/// Single entry under kSecClassGenericPassword (design §7: token stored in Keychain).
/// Thin I/O layer — no unit tests, covered by Task 10 end-to-end verification.
public final class KeychainStore: SecureStore {
    private let service = "com.lumi.LumiMobile.pairing"
    private let account = "default"

    public init() {}

    public func read() -> PairingInfo? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let url = dict["relayUrl"], let token = dict["token"],
              // Pairings from before decision 146 have no server token — they can't open
              // any server, so they read as "not paired" and the pairing screen shows.
              let serverToken = dict["serverToken"], !serverToken.isEmpty
        else { return nil }
        return PairingInfo(relayUrl: url, token: token, serverToken: serverToken)
    }

    public func write(_ info: PairingInfo) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["relayUrl": info.relayUrl, "token": info.token, "serverToken": info.serverToken]
        ) else { return }
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
