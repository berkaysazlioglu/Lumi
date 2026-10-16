import Foundation
import LumiKit

/// Additive codec for project appearance (karar 120):
/// `"projectAppearance": { "<absolute project path>": { "color": "blue", "icon": "sf:star", "title": "dev" } }`.
///
/// Every field is optional and validated on read through the model's own
/// constructors: unknown color, a symbol outside the allowlist, an emoji that is
/// not exactly one grapheme and a blank title are dropped; an entry left empty
/// and a non-absolute path are dropped too. Absent / mistyped key ⇒ `[:]`.
///
/// The map is ALWAYS written (empty as `{}`): config writes merge the overlay
/// into the raw dictionary shallowly, so skipping an empty map would leave the
/// last reset appearance on disk. Empty fields are never written.
enum ProjectAppearanceCodec {
    static func decodeMap(_ value: Any?) -> [String: ProjectAppearance] {
        guard let raw = value as? [String: Any] else { return [:] }
        var result: [String: ProjectAppearance] = [:]
        for (path, entry) in raw {
            guard !path.isEmpty, (path as NSString).isAbsolutePath,
                  let entry = entry as? [String: Any] else { continue }
            let appearance = decode(entry)
            if !appearance.isEmpty { result[path] = appearance }
        }
        return result
    }

    static func decode(_ entry: [String: Any]) -> ProjectAppearance {
        ProjectAppearance(
            color: (entry["color"] as? String).flatMap(ProjectColor.init(rawValue:)),
            icon: (entry["icon"] as? String).flatMap(ProjectIcon.init(persisted:)),
            rootTitle: entry["title"] as? String
        )
    }

    static func overlayMap(_ map: [String: ProjectAppearance]) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for (path, appearance) in map where !appearance.isEmpty {
            var entry: [String: String] = [:]
            if let color = appearance.color { entry["color"] = color.rawValue }
            if let icon = appearance.icon { entry["icon"] = icon.persisted }
            if let title = appearance.rootTitle { entry["title"] = title }
            result[path] = entry
        }
        return result
    }
}
