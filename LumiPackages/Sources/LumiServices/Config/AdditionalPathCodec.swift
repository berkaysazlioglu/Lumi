import Foundation
import LumiKit

/// `config.json` → `additionalPaths` dizisi ↔ `[AdditionalPath]`.
/// Eksik/bozuk girdi sessizce DÜŞÜRÜLÜR (Electron migration kuralı); dizi
/// değilse sonuç boş listedir.
enum AdditionalPathCodec {
    static func decodeList(_ value: Any?) -> [AdditionalPath] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { decode($0 as? [String: Any]) }
    }

    static func overlayList(_ paths: [AdditionalPath]) -> [[String: Any]] {
        paths.map(overlay)
    }

    static func decode(_ dict: [String: Any]?) -> AdditionalPath? {
        guard let dict,
              let id = dict["id"] as? String,
              let path = dict["path"] as? String,
              let typeRaw = dict["type"] as? String,
              let type = AdditionalPath.PathType(rawValue: typeRaw) else {
            return nil
        }
        return AdditionalPath(id: id, path: path, type: type, label: dict["label"] as? String)
    }

    static func overlay(_ path: AdditionalPath) -> [String: Any] {
        var entry: [String: Any] = [
            "id": path.id,
            "path": path.path,
            "type": path.type.rawValue,
        ]
        // label yalnız DOLU iken yazılır: nil'i `null` diye yazmak Electron
        // çıktısından sapardı (karar 9).
        if let label = path.label {
            entry["label"] = label
        }
        return entry
    }
}
