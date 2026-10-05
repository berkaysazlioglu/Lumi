import Foundation
import LumiKit

/// Additive codec for project favorite files (karar 107). Absent key ⇒ `[]`;
/// malformed entries (non-absolute project, path escaping the checkout) are
/// dropped, ids and `(projectPath, relativePath)` pairs deduplicated.
enum FavoriteFileCodec {
    static func decodeList(_ value: Any?) -> [ProjectFavoriteFile] {
        guard let values = value as? [Any] else { return [] }
        var seenIDs = Set<String>()
        var seenPaths = Set<String>()
        return values.compactMap { raw in
            guard let raw = raw as? [String: Any],
                  let id = raw["id"] as? String, !id.isEmpty,
                  let projectPath = raw["projectPath"] as? String, projectPath.hasPrefix("/"),
                  let relativePath = raw["relativePath"] as? String else { return nil }
            let favorite = ProjectFavoriteFile(id: id, projectPath: projectPath, relativePath: relativePath)
            guard favorite.isValid,
                  seenIDs.insert(id).inserted,
                  seenPaths.insert(projectPath + "\0" + relativePath).inserted else { return nil }
            return favorite
        }
    }

    static func overlayList(_ favorites: [ProjectFavoriteFile]) -> [[String: Any]] {
        favorites.map { ["id": $0.id, "projectPath": $0.projectPath, "relativePath": $0.relativePath] }
    }
}
