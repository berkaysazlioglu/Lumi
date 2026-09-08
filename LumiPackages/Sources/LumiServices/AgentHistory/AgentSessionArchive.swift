import Foundation
import LumiKit

/// `.lumisession.json` paketi: ana transkript kayıtları + Claude alt ajan
/// transkriptleri tek JSON belgesinde. Kayıtlar JSON satırı olarak değil,
/// nesne olarak taşınır — dosya okunabilir kalır ve yeniden yazım kolaydır.
struct AgentSessionArchive {
    static let format = "lumi-agent-session"
    static let version = 1
    static let fileExtension = "lumisession.json"

    struct Subagent {
        let id: String
        let meta: [String: Any]?
        let records: [[String: Any]]
    }

    let provider: AgentProvider
    let sessionID: String
    let cwd: String?
    let title: String
    /// Kaynak dosyanın adı (Codex `rollout-…` adını korumak için).
    let fileName: String
    let records: [[String: Any]]
    let subagents: [Subagent]

    func encode() throws -> Data {
        let payload: [String: Any] = [
            "format": Self.format,
            "version": Self.version,
            "provider": provider.rawValue,
            "sessionID": sessionID,
            "cwd": cwd as Any? ?? NSNull(),
            "title": title,
            "fileName": fileName,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "records": records,
            "subagents": subagents.map { sub -> [String: Any] in
                ["id": sub.id, "meta": sub.meta as Any? ?? NSNull(), "records": sub.records]
            },
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static func decode(_ data: Data) throws -> AgentSessionArchive {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LumiError.sessionTransferFailed(detail: "File is not a JSON object.")
        }
        guard root["format"] as? String == format else {
            throw LumiError.sessionTransferFailed(detail: "Not a Lumi session export.")
        }
        guard let version = root["version"] as? Int, version <= Self.version else {
            throw LumiError.sessionTransferFailed(detail: "Unsupported export version.")
        }
        guard let provider = (root["provider"] as? String).flatMap(AgentProvider.init(rawValue:)) else {
            throw LumiError.sessionTransferFailed(detail: "Unknown provider.")
        }
        guard let sessionID = root["sessionID"] as? String, Self.isValidSessionID(sessionID) else {
            throw LumiError.sessionTransferFailed(detail: "Invalid session ID.")
        }
        guard let records = root["records"] as? [[String: Any]], !records.isEmpty else {
            throw LumiError.sessionTransferFailed(detail: "Export contains no records.")
        }
        let subagents = try ((root["subagents"] as? [[String: Any]]) ?? []).map { raw -> Subagent in
            guard let id = raw["id"] as? String, Self.isValidSubagentID(id),
                  let records = raw["records"] as? [[String: Any]] else {
                throw LumiError.sessionTransferFailed(detail: "Malformed subagent entry.")
            }
            return Subagent(id: id, meta: raw["meta"] as? [String: Any], records: records)
        }
        let fileName = (root["fileName"] as? String).flatMap(Self.safeFileName) ?? "\(sessionID).jsonl"
        return AgentSessionArchive(
            provider: provider, sessionID: sessionID, cwd: root["cwd"] as? String,
            title: root["title"] as? String ?? "", fileName: fileName, records: records, subagents: subagents
        )
    }

    static func isValidSessionID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#, options: .regularExpression) != nil
    }

    static func isValidSubagentID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil
    }

    /// Dizin kaçışı yok, yalnız `.jsonl` uzantılı tek bileşen.
    private static func safeFileName(_ value: String) -> String? {
        guard value.range(of: #"^[A-Za-z0-9._:-]{1,255}\.jsonl$"#, options: .regularExpression) != nil,
              !value.hasPrefix(".") else { return nil }
        return value
    }
}
