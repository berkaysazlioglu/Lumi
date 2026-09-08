import Foundation
import LumiKit

/// Additive codec for managed workspace records. Unknown config keys remain
/// untouched by ConfigService's raw dictionary merge.
enum ProjectWorkspaceCodec {
    static func decodeList(_ value: Any?) -> [ProjectWorkspace] {
        guard let values = value as? [Any] else { return [] }
        var seen = Set<String>()
        return values.compactMap { raw in
            guard let raw = raw as? [String: Any],
                  let projectPath = raw["projectPath"] as? String,
                  let path = raw["path"] as? String,
                  let name = raw["name"] as? String,
                  let branch = raw["branch"] as? String,
                  let scmRaw = raw["scm"] as? String,
                  let scm = WorkspaceSCM(rawValue: scmRaw), scm != .none,
                  projectPath.hasPrefix("/"), path.hasPrefix("/"), projectPath != path,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !branch.isEmpty else { return nil }
            guard seen.insert(path).inserted else { return nil }
            return ProjectWorkspace(projectPath: projectPath, path: path, name: name, branch: branch, scm: scm)
        }
    }

    static func overlayList(_ records: [ProjectWorkspace]) -> [[String: Any]] {
        records.map {
            ["projectPath": $0.projectPath, "path": $0.path, "name": $0.name,
             "branch": $0.branch, "scm": $0.scm.rawValue]
        }
    }
}
