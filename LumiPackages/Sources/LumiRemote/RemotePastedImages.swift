import Foundation
import LumiKit

/// Controller'dan yapıştırılan görseller (karar 143 ek): hub görseli diske yazar ve yolunu
/// terminale, yerel sürükle-bırakla aynı biçimde yazar — Claude Code görsel yolunu
/// `[Image #N]` eki yapar (görseli kendi önbelleğine kendisi kopyalar). Hub'ın panosuna
/// dokunulmaz.
enum RemotePastedImages {
    /// Relay'in 1 MB frame sınırı base64 ile ~750 KB ham veriye denk gelir.
    static let byteLimit = 750 * 1024
    /// Eski dosyalar yazımda temizlenir (Claude eki gönderimde okur, sonra gerekmez).
    static let retention: TimeInterval = 24 * 60 * 60

    enum Format: String, CaseIterable {
        case png, jpg

        /// Dosya imzası: uzantıya güvenilmez, içerik doğrulanır.
        func matches(_ data: Data) -> Bool {
            switch self {
            case .png: data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            case .jpg: data.starts(with: [0xFF, 0xD8, 0xFF])
            }
        }
    }

    enum Failure: Error, Equatable { case invalidImage, tooLarge }

    static func validate(base64: String?, ext: String?) throws -> (Data, Format) {
        guard let base64, let data = Data(base64Encoded: base64), !data.isEmpty,
              let format = Format(rawValue: (ext ?? "png").lowercased()), format.matches(data) else {
            throw Failure.invalidImage
        }
        guard data.count <= byteLimit else { throw Failure.tooLarge }
        return (data, format)
    }

    /// Görseli yazar, eskileri temizler ve terminale yazılacak metni döner.
    static func store(_ data: Data, format: Format,
                      directory: URL = defaultDirectory, now: Date = Date()) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        prune(directory, now: now)
        let stamp = Int(now.timeIntervalSince1970)
        let url = directory.appendingPathComponent(
            "pasted-\(stamp)-\(UUID().uuidString.prefix(8).lowercased()).\(format.rawValue)")
        try data.write(to: url, options: .atomic)
        return url.path.contains(where: { " '\"\\$`!*?[]();&|<>".contains($0) }) ? shellQuoted(url.path) : url.path
    }

    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lumi-remote-images", isDirectory: true)
    }

    private static func prune(_ directory: URL, now: Date) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > retention { try? fm.removeItem(at: file) }
        }
    }
}
