public enum ExplorerFileEdit: Sendable, Equatable {
    case createFile(path: String)
    case createFolder(path: String)
    case move(from: String, to: String)
}
