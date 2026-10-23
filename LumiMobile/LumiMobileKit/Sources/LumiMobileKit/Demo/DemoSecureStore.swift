import Foundation

/// Pairing store for demo mode: always "paired" with a dummy relay so
/// `AppModel.isPaired` is true and `start()` proceeds. Writes/clears are no-ops,
/// so the demo never touches the real Keychain pairing.
public final class DemoSecureStore: SecureStore {
    public static let pairing = PairingInfo(relayUrl: "wss://demo.lumi.invalid", token: "demo-token-0000000000")

    public init() {}

    public func read() -> PairingInfo? { Self.pairing }
    public func write(_ info: PairingInfo) {}
    public func clear() {}
}
