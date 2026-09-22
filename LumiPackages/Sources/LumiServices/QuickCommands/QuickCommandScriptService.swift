import Foundation
import LumiKit

/// Hızlı komut script'lerini `~/.lumi/quick-commands/` altına yazar (karar 92).
/// Dosyalar kullanıcıya özeldir (0600) — çalıştırma `sh <dosya>` ile olduğu
/// için çalıştırma biti gerekmez. Ad yalnız `QuickCommandRun.fileName`'den
/// gelir; yine de dizin dışına çıkan ad reddedilir.
public actor QuickCommandScriptService: QuickCommandScriptWriting {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func writeScript(named fileName: String, contents: String) throws -> String {
        let target = directory.appendingPathComponent(fileName).standardizedFileURL
        guard !fileName.contains("/"), target.deletingLastPathComponent().path == directory.standardizedFileURL.path else {
            throw LumiError.fileOperationFailed(path: fileName, detail: "invalid script name")
        }
        do {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try Data(contents.utf8).write(to: target, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch {
            throw LumiError.fileOperationFailed(path: target.path, detail: error.localizedDescription)
        }
        return target.path
    }
}
