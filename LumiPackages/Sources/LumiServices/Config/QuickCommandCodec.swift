import Foundation
import LumiKit

/// Additive codec for project quick commands (karar 92). Absent key ⇒ `[]`;
/// malformed entries are dropped and ids deduplicated. `role` (karar 93) is
/// additive too: absent/unknown ⇒ `action`; only the first `startApp` of a
/// project survives.
enum QuickCommandCodec {
    static func decodeList(_ value: Any?) -> [ProjectQuickCommand] {
        guard let values = value as? [Any] else { return [] }
        var seen = Set<String>()
        var startAppProjects = Set<String>()
        return values.compactMap { raw in
            guard let raw = raw as? [String: Any],
                  let id = raw["id"] as? String, !id.isEmpty,
                  let projectPath = raw["projectPath"] as? String, projectPath.hasPrefix("/"),
                  let name = raw["name"] as? String,
                  let script = raw["script"] as? String else { return nil }
            let role = (raw["role"] as? String).flatMap(QuickCommandRole.init(rawValue:)) ?? .action
            let command = ProjectQuickCommand(
                id: id, projectPath: projectPath, name: name, script: script,
                request: raw["request"] as? String ?? "", role: role
            )
            guard command.isValid, seen.insert(id).inserted else { return nil }
            if role == .startApp, !startAppProjects.insert(projectPath).inserted { return nil }
            return command
        }
    }

    static func overlayList(_ commands: [ProjectQuickCommand]) -> [[String: Any]] {
        commands.map {
            ["id": $0.id, "projectPath": $0.projectPath, "name": $0.name,
             "script": $0.script, "request": $0.request, "role": $0.role.rawValue]
        }
    }
}
