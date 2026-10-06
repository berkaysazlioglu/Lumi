import Foundation
import LumiKit
import Observation

/// Bir link eyleminin NE YAPACAĞI (karar 57). Store yalnız niyeti üretir;
/// yürütme kabuk katmanındadır (`ShellContext`) — sekme açma, FileViewer ve
/// Finder zaten orada yaşıyor.
public enum TerminalLinkIntent: Sendable, Equatable {
    /// Sistemdeki varsayılan tarayıcı (Lumi içine tarayıcı konmaz).
    case openURL(URL)
    case switchWorkspace(path: String)
    case openFile(repoPath: String, filePath: String)
    /// Bilinen bir kökün dışındaki dosya: FileViewer repo-göreli çalıştığı için
    /// sistemin varsayılan uygulamasına devredilir.
    case openWithDefaultApp(path: String)
    /// `.html`/`.htm` dosyası sistemin varsayılan TARAYICISINDA (karar 116) —
    /// varsayılan uygulama bir editör olabilir.
    case openInBrowser(path: String)
    case revealInFinder(path: String)
}

/// Popover'daki tek satır.
public struct TerminalLinkAction: Identifiable, Equatable, Sendable {
    public enum Slot: String, Sendable {
        case primary
        case alternate
        /// Kısayolu olmayan üçüncü satır (yalnız tıkla çalışır).
        case extra
    }

    public let slot: Slot
    public let title: String
    public let intent: TerminalLinkIntent

    public init(slot: Slot, title: String, intent: TerminalLinkIntent) {
        self.slot = slot
        self.title = title
        self.intent = intent
    }

    public var id: String { slot.rawValue }

    /// Satırın sağındaki tuş kombinasyonu; üçüncü satırın kısayolu yoktur.
    public var shortcutKeys: [String] {
        switch slot {
        case .primary: return ["⌘", "Click"]
        case .alternate: return ["⇧", "⌘", "Click"]
        case .extra: return []
        }
    }
}

/// Açık popover'ın durumu.
public struct TerminalLinkRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Popover kapanınca klavye odağının geri verileceği terminal.
    public let terminalID: TerminalID
    public let target: TerminalLinkTarget
    /// Kabuk koordinat uzayında tık noktası.
    public let anchor: CGPoint
    public let primary: TerminalLinkAction
    public let alternate: TerminalLinkAction?
    /// Kısayolsuz üçüncü satır (ör. repo içindeki bir PDF'i sistem
    /// uygulamasında açmak).
    public let extra: TerminalLinkAction?

    public var destination: String { target.displayText }

    /// Kopyala butonu yalnız URL'lerde çıkar (Orca paritesi).
    public var isCopyable: Bool {
        if case .url = target { return true }
        return false
    }

    public var actions: [TerminalLinkAction] {
        [primary, alternate, extra].compactMap { $0 }
    }

    public init(
        id: UUID = UUID(),
        terminalID: TerminalID,
        target: TerminalLinkTarget,
        anchor: CGPoint,
        primary: TerminalLinkAction,
        alternate: TerminalLinkAction?,
        extra: TerminalLinkAction? = nil
    ) {
        self.id = id
        self.terminalID = terminalID
        self.target = target
        self.anchor = anchor
        self.primary = primary
        self.alternate = alternate
        self.extra = extra
    }
}

/// Terminal link tıklamalarının tek karar noktası (karar 57).
///
/// Hedefi çözer (URL / workspace / dizin / dosya), jeste göre ya popover'ı açar
/// ya da eylemi doğrudan işletir. Dosya sistemi sorgusu enjekte edilir; testler
/// diske hiç dokunmaz.
@Observable
@MainActor
public final class TerminalLinkActionStore {
    public private(set) var request: TerminalLinkRequest?

    @ObservationIgnored private let terminals: TerminalListStore
    @ObservationIgnored private let repos: RepoStore
    @ObservationIgnored private let workspaces: ProjectWorkspaceStore
    @ObservationIgnored private let homeDirectory: String
    @ObservationIgnored private let pathKind: @Sendable (String) -> TerminalLinkPathKind
    /// Asılı bir ağ mount'unda tık süresiz beklemesin.
    private static let pathKindTimeout: Duration = .seconds(1)
    /// Kabuk bağlar; bağlanmazsa eylem sessizce düşer (test/preview).
    @ObservationIgnored public var onIntent: ((TerminalLinkIntent) -> Void)?

    public init(
        terminals: TerminalListStore,
        repos: RepoStore,
        workspaces: ProjectWorkspaceStore,
        homeDirectory: String = NSHomeDirectory(),
        pathKind: @escaping @Sendable (String) -> TerminalLinkPathKind = TerminalLinkActionStore.diskPathKind
    ) {
        self.terminals = terminals
        self.repos = repos
        self.workspaces = workspaces
        self.homeDirectory = homeDirectory
        self.pathKind = pathKind
    }

    public nonisolated static func diskPathKind(_ path: String) -> TerminalLinkPathKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .missing
        }
        return isDirectory.boolValue ? .directory : .file
    }

    // MARK: - Giriş

    /// Dosya sistemi sorgusu MainActor'dan ÇIKARILIR: ağ mount'unda asılan tek
    /// bir `fileExists` tüm uygulamayı (terminal feed'i dahil) dondururdu.
    public func handle(_ activation: TerminalLinkActivation) async {
        guard let resolved = await makeRequest(activation) else {
            request = nil
            return
        }
        switch activation.gesture {
        case .actions:
            request = resolved
        case .primary:
            // Popover'ın kendi ipucu "⌘ Click → birincil eylem" diyor; dosyada
            // da doğrudan çalışır. "Lumi mi Finder mı" sorusu DÜZ tıkın işidir.
            perform(resolved.primary)
        case .alternate:
            // Alternatifi olmayan hedefte (URL, dizin) ⇧⌘ birincil eylemi işletir.
            perform(resolved.alternate ?? resolved.primary)
        }
    }

    public func perform(_ action: TerminalLinkAction) {
        request = nil
        onIntent?(action.intent)
    }

    public func dismiss() {
        request = nil
    }

    // MARK: - Çözümleme

    /// Bilinen kökler: sidebar projeleri + oluşturulan workspace'ler.
    private var knownRoots: [String] {
        repos.repos.map(\.path) + workspaces.records.map(\.path)
    }

    func makeRequest(_ activation: TerminalLinkActivation) async -> TerminalLinkRequest? {
        let basePath = terminals.meta(for: activation.terminalID)?.repoPath ?? ""
        let roots = knownRoots
        guard let candidate = TerminalLinkResolver.candidate(
            link: activation.link, basePath: basePath, homeDirectory: homeDirectory
        ) else { return nil }

        let kind = await pathKind(of: candidate)
        // Diskte olmayan yol hedef üretmez (karar 116): popover açılmaz.
        guard let target = TerminalLinkResolver.classify(candidate, knownRoots: roots, kind: kind) else {
            return nil
        }
        let actions = Self.actions(for: target, knownRoots: roots)
        return TerminalLinkRequest(
            terminalID: activation.terminalID,
            target: target,
            anchor: activation.anchor,
            primary: actions.primary,
            alternate: actions.alternate,
            extra: actions.extra
        )
    }

    /// Arka planda sorar ve `pathKindTimeout` içinde dönmezse `.file` sayar —
    /// asılı bir mount tıkı süresiz askıda bırakmasın. Cevapsızlık "yok"
    /// demek değildir: hedef düşürülmez, hata eylem çalışınca görünür.
    private func pathKind(of candidate: TerminalLinkCandidate) async -> TerminalLinkPathKind {
        guard case let .path(path) = candidate else { return .missing }
        let probe = pathKind
        return await withTaskGroup(of: TerminalLinkPathKind?.self) { group in
            group.addTask { probe(path) }
            group.addTask {
                try? await Task.sleep(for: Self.pathKindTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .file
        }
    }

    static func actions(
        for target: TerminalLinkTarget,
        knownRoots: [String]
    ) -> (primary: TerminalLinkAction, alternate: TerminalLinkAction?, extra: TerminalLinkAction?) {
        switch target {
        case .url(let url):
            return (.init(slot: .primary, title: "Open link", intent: .openURL(url)), nil, nil)
        case .workspace(let path):
            return (
                .init(slot: .primary, title: "Switch workspace", intent: .switchWorkspace(path: path)),
                .init(slot: .alternate, title: "Open in Finder", intent: .revealInFinder(path: path)),
                nil
            )
        case .directory(let path):
            return (
                .init(slot: .primary, title: "Open in Finder", intent: .revealInFinder(path: path)),
                nil,
                nil
            )
        case .file(let path) where isHTML(path):
            return htmlActions(path: path, knownRoots: knownRoots)
        case .file(let path):
            let finder = TerminalLinkAction(
                slot: .alternate, title: "Open in Finder", intent: .revealInFinder(path: path)
            )
            // Bilinen kökün İÇİ: Lumi'nin kendi görüntüleyicisi repo-göreli çalışır.
            if let root = TerminalLinkResolver.enclosingRoot(of: path, in: knownRoots),
               let relative = TerminalLinkResolver.relativePath(of: path, in: root) {
                let lumi = TerminalLinkAction(
                    slot: .primary, title: "Open in Lumi",
                    intent: .openFile(repoPath: root, filePath: relative)
                )
                // Üçüncü satır: FileViewer'ın gösteremediği türler (PDF, görsel
                // düzenleyici, ofis dosyası) için sistem uygulaması.
                let defaultApp = defaultAppAction(slot: .extra, path: path)
                return (lumi, finder, defaultApp)
            }
            // Kök dışı: FileViewer yok. Varsayılan uygulama güvenliyse birincil,
            // değilse tek seçenek Finder'dır.
            guard let defaultApp = defaultAppAction(slot: .primary, path: path) else {
                return (
                    .init(slot: .primary, title: "Open in Finder", intent: .revealInFinder(path: path)),
                    nil,
                    nil
                )
            }
            return (defaultApp, finder, nil)
        }
    }

    /// HTML (karar 116, Orca'nın "⇧⌘+click for default browser" ipucu): kök
    /// içinde birincil yine Lumi'nin görüntüleyicisi, ⇧⌘ tarayıcı; kök dışında
    /// tarayıcı birincildir. Finder her iki durumda da bir satır aşağıdadır.
    private static func htmlActions(
        path: String, knownRoots: [String]
    ) -> (primary: TerminalLinkAction, alternate: TerminalLinkAction?, extra: TerminalLinkAction?) {
        if let root = TerminalLinkResolver.enclosingRoot(of: path, in: knownRoots),
           let relative = TerminalLinkResolver.relativePath(of: path, in: root) {
            return (
                .init(slot: .primary, title: "Open in Lumi", intent: .openFile(repoPath: root, filePath: relative)),
                .init(slot: .alternate, title: "Open in Browser", intent: .openInBrowser(path: path)),
                .init(slot: .extra, title: "Open in Finder", intent: .revealInFinder(path: path))
            )
        }
        return (
            .init(slot: .primary, title: "Open in Browser", intent: .openInBrowser(path: path)),
            .init(slot: .alternate, title: "Open in Finder", intent: .revealInFinder(path: path)),
            nil
        )
    }

    private static let htmlExtensions: Set<String> = ["html", "htm"]

    private static func isHTML(_ path: String) -> Bool {
        htmlExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Çalıştırılabilir türlerde (`.command`, `.scpt`, `.pkg`, `.app`…) "varsayılan
    /// uygulamada aç" HİÇ önerilmez: `NSWorkspace.open` onları açmaz, çalıştırır ve
    /// terminale basılan metin güvenilmez bir kaynaktır (karar 57 sertleştirmesi).
    private static func defaultAppAction(
        slot: TerminalLinkAction.Slot, path: String
    ) -> TerminalLinkAction? {
        guard !TerminalLinkSafety.isExecutable(path: path) else { return nil }
        return .init(slot: slot, title: "Open with default app", intent: .openWithDefaultApp(path: path))
    }
}
