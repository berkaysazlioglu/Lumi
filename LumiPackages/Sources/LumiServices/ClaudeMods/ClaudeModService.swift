import Foundation
import LumiKit

/// `~/.lumi/mods` klasörünü yöneten servis (karar 142): Lumi'nin kendi
/// modlarını kurar/günceller ve klasördeki modları listeler. Process
/// çalıştırmaz; yalnız dosya sistemi.
public struct ClaudeModService: ClaudeModServicing {
    public let directory: String
    private let bundled: [BundledClaudeMod]

    public init(directory: URL) {
        self.init(directory: directory, bundled: BundledClaudeMods.all)
    }

    init(directory: URL, bundled: [BundledClaudeMod]) {
        self.directory = directory.path
        self.bundled = bundled
    }

    public func installBundled() async throws {
        let fileManager = FileManager.default
        for mod in bundled {
            let root = URL(fileURLWithPath: directory).appendingPathComponent(mod.id)
            guard Self.manifest(in: root)?.version != mod.version else { continue }
            for (relativePath, contents) in mod.files {
                let file = root.appendingPathComponent(relativePath)
                try fileManager.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data(contents.utf8).write(to: file, options: .atomic)
            }
        }
    }

    public func list() async -> [ClaudeMod] {
        let root = URL(fileURLWithPath: directory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let bundledIDs = Set(bundled.map(\.id))
        return names
            .filter { !$0.hasPrefix(".") }
            .compactMap { name -> ClaudeMod? in
                let folder = root.appendingPathComponent(name)
                guard let manifest = Self.manifest(in: folder) else { return nil }
                return ClaudeMod(
                    id: name,
                    name: manifest.name ?? name,
                    description: manifest.description,
                    version: manifest.version,
                    path: folder.path,
                    isBundled: bundledIDs.contains(name)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct Manifest {
        let name: String?
        let description: String?
        let version: String?
    }

    /// `.claude-plugin/plugin.json`; yoksa ya da JSON nesnesi değilse `nil`
    /// (o klasör mod sayılmaz).
    private static func manifest(in folder: URL) -> Manifest? {
        let file = folder.appendingPathComponent(".claude-plugin/plugin.json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return Manifest(
            name: object["name"] as? String,
            description: object["description"] as? String,
            version: object["version"] as? String
        )
    }
}
