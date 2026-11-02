import Foundation
import LumiKit
import os

/// `~/.lumi/mods` klasörünü yöneten servis (karar 142): Lumi'nin kendi
/// modlarını kurar/günceller ve klasördeki modları listeler. Process
/// çalıştırmaz; yalnız dosya sistemi.
public struct ClaudeModService: ClaudeModServicing {
    private static let logger = LumiLog.logger("claudeMods")
    /// Lumi'nin yazdığı mod klasörünün işareti. İşaretsiz klasör kullanıcınındır
    /// ve adı Lumi'nin bir moduyla çakışsa da ona dokunulmaz.
    static let bundledMarker = ".lumi-bundled"

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
        let root = URL(fileURLWithPath: directory)
        for mod in bundled {
            let destination = root.appendingPathComponent(mod.id)
            switch Self.installState(of: destination, for: mod) {
            case .current:
                continue
            case .userOwned:
                Self.logger.log("skip bundled \(mod.id, privacy: .public): folder belongs to the user")
                continue
            case .missing, .outdated:
                try Self.install(mod, at: destination, in: root)
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
                // `CLAUDE_CODE_PLUGIN_DIRS` `:` ile ayrılır ve kaçış yoktur.
                guard !folder.path.contains(":") else {
                    Self.logger.log("skip mod \(name, privacy: .public): path contains ':'")
                    return nil
                }
                return ClaudeMod(
                    id: name,
                    name: manifest.name ?? name,
                    description: manifest.description,
                    version: manifest.version,
                    path: folder.path,
                    // İşaret tek başına yetmez: varsayılan açıklık (karar 142)
                    // yalnız Lumi'nin bildiği bir mod adına verilir.
                    isBundled: bundledIDs.contains(name) && Self.isMarked(folder)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Kurulum

    enum InstallState: Equatable {
        case missing, current, outdated, userOwned
    }

    static func installState(of folder: URL, for mod: BundledClaudeMod) -> InstallState {
        guard FileManager.default.fileExists(atPath: folder.path) else { return .missing }
        let manifest = manifest(in: folder)
        // İşaretten önceki kurulum (1.0.0): Lumi'nin kendi manifest'i birebir.
        let isOurs = isMarked(folder)
            || (manifest?.name == mod.id && manifest.map { mod.legacyVersions.contains($0.version ?? "") } == true)
        guard isOurs else { return .userOwned }
        return manifest?.version == mod.version && isMarked(folder) ? .current : .outdated
    }

    /// Dosyalar noktalı bir geçici klasöre yazılır (`list()` noktalıları
    /// atlar) ve klasör tek adımda yerine konur: yarım yazılmış bir mod ne
    /// listede görünür ne de çalışan claude'ların izlediği klasöre düşer.
    private static func install(_ mod: BundledClaudeMod, at destination: URL, in root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".\(mod.id).staging-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }
        for (relativePath, contents) in mod.files {
            let file = staging.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
        }
        try Data(mod.version.utf8).write(to: staging.appendingPathComponent(bundledMarker))
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    private static func isMarked(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(bundledMarker).path)
    }

    // MARK: - Manifest

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
