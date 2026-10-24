import Foundation
import LumiKit

/// Lumi Tasks Protocol v1 ↔ ortak model (saf; `TaskSetupPrompt` metninin
/// söylediği JSON biçimi).
///
/// Okuma **hoşgörülüdür**: her ajan protokolü biraz farklı yazar. Sayı olarak
/// gelen kimlik string'e çevrilir, bilinmeyen alanlar yok sayılır; zorunlu bir
/// alan bozuksa task atılmaz, `needsAttention` ile işaretlenir (Verify bunu
/// raporlar). Yalnız kimliği olmayan task gösterilemez ve atlanır.
enum LumiTasksWire {
    static let protocolName = "lumi-tasks"

    // MARK: - Discovery

    enum DiscoveryProblem: Error, Equatable {
        case notAnObject
        case wrongProtocol(String?)
        case missingVersion
    }

    static func discovery(_ json: Any?) throws -> TaskSourceInfo {
        guard let object = json as? [String: Any] else { throw DiscoveryProblem.notAnObject }
        let name = object["protocol"] as? String
        guard name == protocolName else { throw DiscoveryProblem.wrongProtocol(name) }
        guard let version = int(object["version"]) else { throw DiscoveryProblem.missingVersion }
        let capabilities = Set((object["capabilities"] as? [Any] ?? []).compactMap {
            ($0 as? String).flatMap(TaskCapability.init(rawValue:))
        })
        var fields: [TaskField: TaskFieldAccess] = [:]
        for (key, value) in object["fields"] as? [String: Any] ?? [:] {
            guard let field = TaskField(rawValue: key),
                  let access = (value as? String).flatMap(TaskFieldAccess.init(rawValue:)) else { continue }
            fields[field] = access
        }
        return TaskSourceInfo(
            name: object["name"] as? String,
            version: version,
            capabilities: capabilities,
            fields: fields,
            me: user(object["me"])
        )
    }

    // MARK: - Task

    static func task(_ json: Any?) -> TaskItem? {
        guard let object = json as? [String: Any], let id = string(object["id"]), !id.isEmpty else { return nil }
        var needsAttention = false
        let title: String
        if let value = object["title"] as? String, !value.isEmpty {
            title = value
        } else {
            title = "(untitled)"
            needsAttention = true
        }
        let status: TaskStatus
        if let value = (object["status"] as? String).flatMap(TaskStatus.init(rawValue:)) {
            status = value
        } else {
            status = .todo
            needsAttention = true
        }
        let updatedAt: Date
        if let value = date(object["updatedAt"]) {
            updatedAt = value
        } else {
            updatedAt = .distantPast
            needsAttention = true
        }
        return TaskItem(
            id: id,
            title: title,
            status: status,
            updatedAt: updatedAt,
            createdAt: date(object["createdAt"]),
            body: object["body"] as? String,
            project: project(object["project"]),
            priority: (object["priority"] as? String).flatMap(TaskPriority.init(rawValue:)),
            labels: (object["labels"] as? [Any] ?? []).compactMap { $0 as? String },
            assignee: user(object["assignee"]),
            dueDate: day(object["dueDate"]),
            url: (object["url"] as? String).flatMap(URL.init(string:)),
            images: (object["images"] as? [Any] ?? []).compactMap(image),
            needsAttention: needsAttention
        )
    }

    static func user(_ json: Any?) -> TaskUser? {
        guard let object = json as? [String: Any], let id = string(object["id"]), !id.isEmpty else { return nil }
        let name = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        return TaskUser(id: id, name: name, email: object["email"] as? String)
    }

    static func project(_ json: Any?) -> TaskProjectRef? {
        guard let object = json as? [String: Any], let key = string(object["key"]), !key.isEmpty else { return nil }
        return TaskProjectRef(key: key, name: object["name"] as? String, repo: object["repo"] as? String)
    }

    static func image(_ json: Any?) -> TaskImage? {
        guard let object = json as? [String: Any],
              let url = (object["url"] as? String).flatMap(URL.init(string:)),
              url.scheme != nil else { return nil }
        return TaskImage(
            url: url,
            thumbnailURL: (object["thumbnailUrl"] as? String).flatMap(URL.init(string:)),
            name: object["name"] as? String,
            width: int(object["width"]),
            height: int(object["height"])
        )
    }

    // MARK: - İstek gövdeleri

    static func body(for patch: TaskPatch) -> [String: Any] {
        var body: [String: Any] = [:]
        if let status = patch.status { body["status"] = status.rawValue }
        if let title = patch.title { body["title"] = title }
        if let priority = patch.priority { body["priority"] = priority.rawValue }
        switch patch.assignee {
        case .assign(let user): body["assigneeId"] = user.id
        case .unassign: body["assigneeId"] = NSNull()
        case nil: break
        }
        return body
    }

    static func body(for draft: TaskDraft) -> [String: Any] {
        var body: [String: Any] = ["title": draft.title, "status": draft.status.rawValue]
        if let value = draft.body { body["body"] = value }
        if let value = draft.projectKey { body["projectKey"] = value }
        if let value = draft.priority { body["priority"] = value.rawValue }
        if let value = draft.assignee { body["assigneeId"] = value.id }
        return body
    }

    // MARK: - Hata zarfı

    /// `{ "error": { "code", "message" } }` — yoksa nil'ler.
    static func envelope(_ json: Any?) -> (code: String?, message: String?) {
        guard let error = (json as? [String: Any])?["error"] else { return (nil, nil) }
        if let object = error as? [String: Any] {
            return (object["code"] as? String, object["message"] as? String)
        }
        // Yaygın sapma: `{ "error": "message" }`.
        return (nil, error as? String)
    }

    // MARK: - Değerler

    static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string)
        default: nil
        }
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// `2026-11-01` (UTC gün başı). Tam zaman damgası gelirse o da kabul.
    static func day(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: String(text.prefix(10))) ?? date(text)
    }
}
