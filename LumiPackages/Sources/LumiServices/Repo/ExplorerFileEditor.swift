import Foundation
import LumiKit

struct ExplorerFileEditor {
    func apply(_ edit: ExplorerFileEdit, repoPath: String) throws {
        let guardPath = RepoPathGuard()
        let root = URL(fileURLWithPath: repoPath).standardizedFileURL.resolvingSymlinksInPath().path
        func resolve(_ relative: String) throws -> String {
            guard !relative.isEmpty, !(relative as NSString).isAbsolutePath,
                  !relative.split(separator: "/").contains(".git") else {
                throw LumiError.pathOutsideRepo(path: relative)
            }
            var cursor = URL(fileURLWithPath: root)
            for component in relative.split(separator: "/") {
                guard component != ".", component != ".." else {
                    throw LumiError.pathOutsideRepo(path: relative)
                }
                cursor.appendPathComponent(String(component))
                guard (try? FileManager.default.destinationOfSymbolicLink(atPath: cursor.path)) == nil else {
                    throw LumiError.pathOutsideRepo(path: relative)
                }
            }
            let path = try guardPath.resolve(repoPath: repoPath, relativePath: relative)
            guard path != root else { throw LumiError.pathOutsideRepo(path: relative) }
            return path
        }
        switch edit {
        case .createFile(let path):
            let destination = try resolve(path)
            try Data().write(to: URL(fileURLWithPath: destination), options: .withoutOverwriting)
        case .createFolder(let path):
            try FileManager.default.createDirectory(atPath: resolve(path), withIntermediateDirectories: false)
        case .move(let source, let destination):
            let from = try resolve(source)
            let to = try resolve(destination)
            try FileManager.default.moveItem(atPath: from, toPath: to)
        }
    }
}
