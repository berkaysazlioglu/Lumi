import AppKit
import Foundation
import LumiKit

/// `context:delete-file` / `reveal-in-file-manager` karşılıkları.
///
/// **Path guard (design/02 §8 sapmasının kapatılması, refactor 3.9; daralt:
/// karar 70):** yalnız ÇÖPE ATMA bilinen köklere (projectsRoot +
/// additionalPaths + workspaces) kapalıdır. Guard `RepoPathGuard` ile
/// paylaşılır (git tarafıyla tek kural). Kök listesi boşsa (henüz
/// yapılandırılmamış ilk açılış) ev dizinine düşülür — aksi halde silme
/// tamamen kilitlenirdi. Finder'da gösterme ve varsayılan uygulamada açma
/// yıkıcı olmadığı için guard'ın dışındadır.
public struct FileSystemOperations: Sendable {
    private let allowedRoots: @Sendable () async -> [String]
    private let guardian: RepoPathGuard
    private let trashItem: @Sendable (URL) throws -> Void
    private let reveal: @Sendable (URL) -> Void
    private let openFile: @Sendable (URL) -> Void
    private let openInDefaultBrowser: @Sendable (URL) -> Void

    public init(
        allowedRoots: @escaping @Sendable () async -> [String] = { [NSHomeDirectory()] },
        pathGuard: RepoPathGuard = RepoPathGuard(),
        trashItem: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        },
        reveal: @escaping @Sendable (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        },
        openFile: @escaping @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) },
        openInDefaultBrowser: @escaping @Sendable (URL) -> Void = FileSystemOperations.openWithBrowserApp
    ) {
        self.allowedRoots = allowedRoots
        self.guardian = pathGuard
        self.trashItem = trashItem
        self.reveal = reveal
        self.openFile = openFile
        self.openInDefaultBrowser = openInDefaultBrowser
    }

    public func trash(path: String) async throws {
        try await verify(path)
        do {
            try trashItem(URL(fileURLWithPath: path))
        } catch {
            throw LumiError.fileOperationFailed(path: path, detail: error.localizedDescription)
        }
    }

    /// Kök guard'ı YOKTUR (karar 70): Finder'da gösterme yıkıcı değildir ve
    /// terminalde tıklanan yol (ör. `/private/tmp/...`) neredeyse hiçbir zaman
    /// projectsRoot altında olmaz — guard bu eylemi sessizce öldürüyordu.
    public func revealInFinder(path: String) async {
        guard !path.isEmpty else { return }
        reveal(URL(fileURLWithPath: path))
    }

    /// Karar 57 + 67: `reveal` ile aynı sözleşme. Çalıştırılabilir türlerin
    /// elenmesi çağıran katmanda (`TerminalLinkSafety`) kalır.
    public func openWithDefaultApp(path: String) async {
        guard !path.isEmpty else { return }
        openFile(URL(fileURLWithPath: path))
    }

    /// Karar 116: guard'sız (`openWithDefaultApp` ile aynı sözleşme).
    public func openInBrowser(path: String) async {
        guard !path.isEmpty else { return }
        openInDefaultBrowser(URL(fileURLWithPath: path))
    }

    /// `https` adresini açan uygulama sistemin varsayılan tarayıcısıdır; `.html`
    /// dosyasının varsayılan uygulaması ise bir editör olabilir. Tarayıcı
    /// çözülemezse sistemin dosya için seçtiği uygulamaya düşülür.
    public static func openWithBrowserApp(_ fileURL: URL) {
        let workspace = NSWorkspace.shared
        guard let probe = URL(string: "https://example.com"),
              let browser = workspace.urlForApplication(toOpen: probe) else {
            workspace.open(fileURL)
            return
        }
        workspace.open([fileURL], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
    }

    private func verify(_ path: String) async throws {
        let roots = await effectiveRoots()
        guard guardian.isInside(anyOf: roots, path: path) else {
            throw LumiError.pathOutsideRepo(path: path)
        }
    }

    private func effectiveRoots() async -> [String] {
        let roots = await allowedRoots().filter { !$0.isEmpty }
        return roots.isEmpty ? [NSHomeDirectory()] : roots
    }
}
