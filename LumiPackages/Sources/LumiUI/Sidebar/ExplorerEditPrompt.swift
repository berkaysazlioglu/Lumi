import Foundation
import LumiKit

struct ExplorerEditPrompt {
    enum Kind { case newFile, newFolder, rename }
    let kind: Kind
    let repoPath: String
    let path: String

    var title: String {
        switch kind {
        case .newFile: "New File"
        case .newFolder: "New Folder"
        case .rename: "Rename"
        }
    }

    func edit(name: String) -> ExplorerFileEdit? {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
        let parent = kind == .rename ? (path as NSString).deletingLastPathComponent : path
        let destination = parent.isEmpty ? name : parent + "/" + name
        switch kind {
        case .newFile: return .createFile(path: destination)
        case .newFolder: return .createFolder(path: destination)
        case .rename: return .move(from: path, to: destination)
        }
    }
}
