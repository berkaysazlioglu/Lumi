import Foundation

/// Commit log girdisi (spec/12 §2).
public struct GitCommit: Sendable, Equatable, Identifiable {
    public var id: String { hash }
    public let hash: String
    public let shortHash: String
    public let message: String
    public let author: String
    public let date: Date

    public init(hash: String, shortHash: String, message: String, author: String, date: Date) {
        self.hash = hash
        self.shortHash = shortHash
        self.message = message
        self.author = author
        self.date = date
    }
}

public struct GitBranch: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let isCurrent: Bool

    public init(name: String, isCurrent: Bool) {
        self.name = name
        self.isCurrent = isCurrent
    }
}

/// Sadeleştirilmiş working-tree statüsü (spec/12 §4): staged/unstaged ayrımı yok.
public enum FileChangeStatus: String, Sendable, Equatable {
    case modified
    case added
    case deleted
    case renamed
    case untracked

    /// Changes panelindeki tek harfli rozet.
    public var badge: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "U"
        }
    }
}

public struct GitFileChange: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let status: FileChangeStatus

    public init(path: String, status: FileChangeStatus) {
        self.path = path
        self.status = status
    }
}

/// Commit'in dosya listesi girdisi (karar 6: içerik lazy yüklenir).
public struct CommitFile: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let status: FileChangeStatus

    public init(path: String, status: FileChangeStatus) {
        self.path = path
        self.status = status
    }
}

// MARK: - Unified diff modeli (karar 4)

public struct UnifiedDiff: Sendable, Equatable {
    public let filePath: String
    public let isBinary: Bool
    public let hunks: [DiffHunk]

    public init(filePath: String, isBinary: Bool, hunks: [DiffHunk]) {
        self.filePath = filePath
        self.isBinary = isBinary
        self.hunks = hunks
    }

    public var isEmpty: Bool { hunks.isEmpty && !isBinary }
}

public struct DiffHunk: Sendable, Equatable {
    public let header: String
    public let lines: [DiffLine]

    public init(header: String, lines: [DiffLine]) {
        self.header = header
        self.lines = lines
    }
}

public struct DiffLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case context
        case addition
        case deletion
    }

    public let kind: Kind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let text: String

    public init(kind: Kind, oldLineNumber: Int?, newLineNumber: Int?, text: String) {
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
    }
}

// MARK: - File tree (spec/12 §9)

public struct FileTreeNode: Sendable, Equatable, Identifiable {
    public enum NodeType: Sendable, Equatable {
        case file
        case folder
    }

    /// Repo köküne göre, '/' ayraçlı relative path.
    public var id: String { path }
    public let name: String
    public let path: String
    public let type: NodeType
    public let isIgnored: Bool
    public let children: [FileTreeNode]

    public init(
        name: String,
        path: String,
        type: NodeType,
        isIgnored: Bool,
        children: [FileTreeNode] = []
    ) {
        self.name = name
        self.path = path
        self.type = type
        self.isIgnored = isIgnored
        self.children = children
    }
}
