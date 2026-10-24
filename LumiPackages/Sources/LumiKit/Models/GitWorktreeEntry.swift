import Foundation

/// `git worktree list --porcelain` satırının sadeleştirilmiş hâli (karar 115).
///
/// Projects panelinin Git checkout'ları artık Lumi'nin kendi kaydından değil
/// git'in canlı listesinden keşfedilir (Orca paritesi); config kaydı yalnız
/// gösterilmeyi kalıcılaştırır.
public struct GitWorktreeEntry: Sendable, Equatable {
    /// Kanonik yol (sembolik bağlar çözülmüş; `/tmp` ↔ `/private/tmp` eşitlenir).
    public let path: String
    /// Kısa dal adı (`refs/heads/` öneksiz); detached HEAD'de nil.
    public let branch: String?
    /// Listenin ilk girdisi: projenin kendisi.
    public let isMain: Bool
    public let isBare: Bool
    public let isLocked: Bool
    /// Git'in `prunable` işareti ya da klasörün diskte olmaması. Böyle bir
    /// girdi asla satır olarak gösterilmez.
    public let isPrunable: Bool
    /// Lumi'nin yönetilen kökü (`~/lumi/workspaces`) altında mı? Bu kökteki
    /// worktree'ler kendiliğinden görünür, diğerleri opt-in'dir.
    public let isInsideManagedRoot: Bool

    public init(
        path: String, branch: String?, isMain: Bool = false, isBare: Bool = false,
        isLocked: Bool = false, isPrunable: Bool = false, isInsideManagedRoot: Bool = false
    ) {
        self.path = path
        self.branch = branch
        self.isMain = isMain
        self.isBare = isBare
        self.isLocked = isLocked
        self.isPrunable = isPrunable
        self.isInsideManagedRoot = isInsideManagedRoot
    }

    /// Checkout olarak listelenebilir mi: projenin kendisi, bare girdi,
    /// kaydı kalmış ama klasörü gitmiş worktree ve başka bir aracın
    /// oluşturmakta olduğu geçici worktree satır olamaz.
    public var isListable: Bool { !isMain && !isBare && !isPrunable && !isTransient }

    /// Başka bir aracın hazırlık aşamasındaki worktree'si (ör. Orca'nın
    /// `.orca-preparing/<id>` klasörü, `orca-create-preparation` kilidiyle):
    /// kilitli + detached ya da gizli (`.` ile başlayan) bir ara klasörün
    /// hemen altında. İş bitince araç onu asıl yerine taşır; listelemek
    /// UUID adlı, kısa ömürlü bir satır üretir.
    public var isTransient: Bool {
        if isLocked, branch == nil { return true }
        let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        return parent.hasPrefix(".")
    }

    /// Satır adı: klasör adı (Lumi'nin oluşturduğu workspace'te de klasör
    /// adı workspace adının slug'ıdır).
    public var folderName: String { (path as NSString).lastPathComponent }
}
