import Foundation
import LumiKit

/// Additive codec for connected task sources (Tasks planı, Faz 2). Absent key
/// ⇒ `[]`. Entries with an unknown kind, a duplicate id, or a custom source
/// without a valid address are dropped. Tokens are never part of this record
/// — they live in the Keychain.
enum TaskSourceCodec {
    static func decodeList(_ value: Any?) -> [TaskSource] {
        guard let values = value as? [Any] else { return [] }
        var seen = Set<String>()
        return values.compactMap { raw in
            guard let raw = raw as? [String: Any],
                  let id = raw["id"] as? String, !id.isEmpty,
                  let kindRaw = raw["kind"] as? String,
                  let kind = TaskProviderKind(rawValue: kindRaw), kind.isAvailable,
                  seen.insert(id).inserted else { return nil }
            let name = (raw["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? kind.title
            var baseURL: String?
            if kind.needsEndpoint {
                guard let address = raw["baseURL"] as? String,
                      case .success(let url) = TaskEndpoint.normalize(address) else { return nil }
                baseURL = url.absoluteString
            }
            let template = TaskPromptTemplate(
                prefix: raw["promptPrefix"] as? String ?? "",
                suffix: raw["promptSuffix"] as? String ?? ""
            )
            return TaskSource(id: TaskSourceID(id), name: name, kind: kind, baseURL: baseURL, promptTemplate: template)
        }
    }

    static func overlayList(_ sources: [TaskSource]) -> [[String: Any]] {
        sources.map { source in
            var entry: [String: Any] = ["id": source.id.rawValue, "name": source.name, "kind": source.kind.rawValue]
            if let baseURL = source.baseURL { entry["baseURL"] = baseURL }
            // Additive: yalnız doluyken yazılır.
            if !source.promptTemplate.prefix.isEmpty { entry["promptPrefix"] = source.promptTemplate.prefix }
            if !source.promptTemplate.suffix.isEmpty { entry["promptSuffix"] = source.promptTemplate.suffix }
            return entry
        }
    }
}
