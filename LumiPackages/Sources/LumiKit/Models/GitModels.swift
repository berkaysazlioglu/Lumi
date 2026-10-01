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
    /// Konu satırı (`%s`).
    public let message: String
    /// Konu satırından sonraki gövde (`%b`) — yalnız graph'lı history okumasında
    /// dolar; hover kartı tam mesajı bundan kurar.
    public let body: String
    public let author: String
    public let date: Date
    /// Topolojik sırada ilk parent birinci sıradadır; merge commit'te >1 eleman.
    public let parentHashes: [String]
    public let references: [GitRef]

    public init(
        hash: String,
        shortHash: String,
        message: String,
        body: String = "",
        author: String,
        date: Date,
        parentHashes: [String] = [],
        references: [GitRef] = []
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.message = message
        self.body = body
        self.author = author
        self.date = date
        self.parentHashes = parentHashes
        self.references = references
    }

    public var isMerge: Bool { parentHashes.count > 1 }

    /// Konu + (varsa) boş satırla ayrılmış gövde — commit'in tam mesajı.
    public var fullMessage: String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBody.isEmpty ? message : "\(message)\n\n\(trimmedBody)"
    }
}

/// History graph'ının karşılaştırma bağlamı (Orca `GitHistoryResult` meta
/// alanları): checkout edilmiş branch, upstream'i ve ikisinin merge-base'i.
///
/// History yalnız `HEAD`ten okunur; upstream'in henüz çekilmemiş commit'leri
/// listede YOKTUR. Bu bağlam graph'a sentetik "Incoming / Outgoing Changes"
/// satırlarını ekletir (`CommitGraph.addBoundaryRows`).
public struct GitHistoryContext: Sendable, Equatable {
    public struct Upstream: Sendable, Equatable {
        /// Kısa ad — `origin/main`; `GitRef.name` ile birebir karşılaştırılır.
        public let name: String
        public let hash: String

        public init(name: String, hash: String) {
            self.name = name
            self.hash = hash
        }
    }

    /// `main` — detached HEAD'de nil.
    public let currentBranch: String?
    public let headHash: String
    public let upstream: Upstream?
    /// HEAD ile upstream ayrıştıysa ortak ataları; aynı commit'teyse nil.
    public let mergeBase: String?

    public init(currentBranch: String?, headHash: String, upstream: Upstream? = nil, mergeBase: String? = nil) {
        self.currentBranch = currentBranch
        self.headHash = headHash
        self.upstream = upstream
        self.mergeBase = mergeBase
    }

    /// Upstream'de, HEAD'de olmayan commit var.
    public var hasIncomingChanges: Bool {
        guard let upstream, let mergeBase else { return false }
        return upstream.hash != mergeBase
    }

    /// HEAD'de, upstream'de olmayan commit var.
    public var hasOutgoingChanges: Bool {
        guard upstream != nil, let mergeBase else { return false }
        return headHash != mergeBase
    }
}

/// Checkout edilmiş branch'in özet bağlamı (Source Control başlığı, karar 41):
/// upstream adı, ileri/geri commit sayısı ve çalışma ağacının satır istatistiği.
public struct GitBranchSummary: Sendable, Equatable {
    /// `origin/main` — upstream yoksa nil (yayınlanmamış branch).
    public let upstream: String?
    /// Upstream'e göre henüz push edilmemiş commit sayısı.
    public let ahead: Int
    /// Upstream'den henüz çekilmemiş commit sayısı.
    public let behind: Int
    /// Çalışma ağacındaki (HEAD'e göre) eklenen satırlar.
    public let insertions: Int
    /// Çalışma ağacındaki (HEAD'e göre) silinen satırlar.
    public let deletions: Int

    public init(upstream: String? = nil, ahead: Int = 0, behind: Int = 0, insertions: Int = 0, deletions: Int = 0) {
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.insertions = insertions
        self.deletions = deletions
    }

    public var hasLineChanges: Bool { insertions > 0 || deletions > 0 }
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
