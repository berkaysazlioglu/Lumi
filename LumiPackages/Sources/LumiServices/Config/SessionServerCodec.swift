import Foundation
import LumiKit

/// Additive codec for the connected session server (karar 138):
/// `"sessionServer": { "id", "name", "baseURL" }` or `null`. A record without
/// an id or with an invalid address is dropped. The token is never part of
/// this record — it lives in the Keychain.
enum SessionServerCodec {
    static func decode(_ value: Any?) -> SessionServer? {
        guard let raw = value as? [String: Any],
              let id = raw["id"] as? String, !id.isEmpty,
              let address = raw["baseURL"] as? String,
              case .success(let url) = TaskEndpoint.normalize(address) else { return nil }
        let name = (raw["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url.host ?? address
        return SessionServer(id: id, name: name, baseURL: url.absoluteString)
    }

    static func overlay(_ server: SessionServer) -> [String: Any] {
        ["id": server.id, "name": server.name, "baseURL": server.baseURL]
    }
}
