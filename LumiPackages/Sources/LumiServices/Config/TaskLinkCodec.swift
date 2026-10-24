import Foundation
import LumiKit

/// `ui-state.json` `taskLinks` girdisi (karar 137). Zaman Unix saniyesi.
enum TaskLinkCodec {
    static func decode(_ value: Any) -> TaskAgentLinkRecord? {
        guard let raw = value as? [String: Any],
              let source = raw["source"] as? String, !source.isEmpty,
              let taskID = raw["taskId"] as? String, !taskID.isEmpty,
              let sessionID = raw["sessionId"] as? String, !sessionID.isEmpty,
              let checkout = raw["checkoutPath"] as? String, checkout.hasPrefix("/"),
              let started = JSONValue.double(raw["startedAt"]) else { return nil }
        return TaskAgentLinkRecord(
            source: TaskSourceID(source), taskID: taskID, sessionID: sessionID, checkoutPath: checkout,
            model: (raw["model"] as? String).flatMap(ClaudeModelAlias.init(rawValue:)),
            startedAt: Date(timeIntervalSince1970: started),
            summary: raw["summary"] as? String
        )
    }

    static func overlay(_ record: TaskAgentLinkRecord) -> [String: Any] {
        var entry: [String: Any] = [
            "source": record.source.rawValue, "taskId": record.taskID, "sessionId": record.sessionID,
            "checkoutPath": record.checkoutPath, "startedAt": record.startedAt.timeIntervalSince1970,
        ]
        if let model = record.model { entry["model"] = model.rawValue }
        if let summary = record.summary { entry["summary"] = summary }
        return entry
    }
}
