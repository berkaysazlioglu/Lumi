import Foundation

/// Commit'e iliştirilmiş ref (branch / remote branch / tag).
///
/// `git log --decorate=full` çıktısının (`%D`) parse edilmiş hâli: ad her zaman
/// KISA biçimdir (`main`, `origin/main`, `v1.0`); `refs/heads/` gibi önekler
/// `kind` bilgisine dönüşür.
public struct GitRef: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Detached HEAD'in çıplak `HEAD` dekorasyonu.
        case head
        case localBranch
        case remoteBranch
        case tag
    }

    public var id: String { "\(kind)/\(name)" }
    public let name: String
    public let kind: Kind
    /// `HEAD -> …` ile işaretlenmiş ref (checkout edilmiş branch).
    public let isCurrent: Bool

    public init(name: String, kind: Kind, isCurrent: Bool = false) {
        self.name = name
        self.kind = kind
        self.isCurrent = isCurrent
    }
}

/// Commit log girdisi.
///
/// `parentHashes` ve `references` YALNIZ graph'lı history okumasında
/// (`GitReading.history`) dolar; branch bazlı `commits(repoPath:branch:)`
/// bunları boş bırakır (geriye uyumlu default'lar).
public struct GitCommit: Sendable, Equatable, Identifiable {
    public var id: String { hash }
    public let hash: String
    public let shortHash: String
    public let message: String
    public let author: String
    public let date: Date
    /// Topolojik sırada ilk parent birinci sıradadır; merge commit'te >1 eleman.
    public let parentHashes: [String]
    public let references: [GitRef]

    public init(
        hash: String,
        shortHash: String,
        message: String,
        author: String,
        date: Date,
        parentHashes: [String] = [],
        references: [GitRef] = []
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.message = message
        self.author = author
        self.date = date
        self.parentHashes = parentHashes
        self.references = references
    }

    public var isMerge: Bool { parentHashes.count > 1 }
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

/// Sadeleştirilmiş working-tree statüsü: staged/unstaged ayrımı yok.
public enum FileChangeStatus: String, Sendable, Equatable {
    case modified
    case added
    case deleted
    case renamed
    case untracked
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

// MARK: - Görsel önizleme (karar 21)

/// Görsel dosyanın karşılaştırmalı ham baytları (diff yerine önizleme).
/// `before`/`after` bağımsız olarak nil olabilir: eklenen dosyada `before`,
/// silinen dosyada `after` yoktur. İkisi de nil + `isTooLarge == false` ise
/// önizleme üretilemedi (UI placeholder gösterir).
public struct ImagePreview: Sendable, Equatable {
    /// Tek tarafın bellek sınırı (`GitService.maxImagePreviewBytes`) aşılırsa o
    /// taraf yüklenmez ve bu bayrak kalkar.
    public let filePath: String
    public let before: Data?
    public let after: Data?
    public let isTooLarge: Bool

    public init(filePath: String, before: Data?, after: Data?, isTooLarge: Bool = false) {
        self.filePath = filePath
        self.before = before
        self.after = after
        self.isTooLarge = isTooLarge
    }

    public var hasContent: Bool { before != nil || after != nil }
}

// MARK: - File tree

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
