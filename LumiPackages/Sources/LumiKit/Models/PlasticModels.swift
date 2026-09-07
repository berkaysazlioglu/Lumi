import Foundation

/// Plastic SCM çalışma alanının başlık bağlamı (karar 45): `cm status
/// --header` çıktısındaki changeset + repo@server ve `cm showselector`'daki
/// branch. Branch, seçici yalnız changeset'e sabitlenmişse nil olabilir.
public struct PlasticWorkspaceInfo: Sendable, Equatable {
    public let changesetID: Int
    public let repository: String
    public let server: String
    /// `/main`, `/main/release` — Plastic branch adları `/` ile başlar.
    public let branch: String?

    public init(changesetID: Int, repository: String, server: String, branch: String?) {
        self.changesetID = changesetID
        self.repository = repository
        self.server = server
        self.branch = branch
    }

    /// `sand_out@uncosoft@cloud` — Plastic'in kendi repo spec biçimi.
    public var repositorySpec: String { "\(repository)@\(server)" }
}

/// Repo-geneli changeset girdisi (`cm find changesets`). Branch bazlı değil:
/// Plastic'te branch'ler görünür bir bilgidir ve satır başına gösterilir.
public struct PlasticChangeset: Sendable, Equatable, Identifiable {
    public var id: Int { changesetID }
    public let changesetID: Int
    public let branch: String
    public let owner: String
    public let date: Date
    public let comment: String
    public let parentID: Int?

    public init(changesetID: Int, branch: String, owner: String, date: Date, comment: String, parentID: Int? = nil) {
        self.changesetID = changesetID
        self.branch = branch
        self.owner = owner
        self.date = date
        self.comment = comment
        self.parentID = parentID
    }
}

/// Çalışma alanındaki değişiklik; durum sözlüğü Git ile ortaktır
/// (`FileChangeStatus`) ki Explorer/Source Control renkleri tek fonksiyondan
/// gelsin. Eşleme: CH/CO → modified, AD/CP → added, DE/LD → deleted,
/// MV/LM/RP → renamed, PR (private) → untracked.
public struct PlasticFileChange: Sendable, Equatable, Identifiable {
    public var id: String { path }
    /// Çalışma alanı köküne göre, '/' ayraçlı relative path.
    public let path: String
    public let status: FileChangeStatus

    public init(path: String, status: FileChangeStatus) {
        self.path = path
        self.status = status
    }
}
