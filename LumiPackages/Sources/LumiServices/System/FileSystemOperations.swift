import AppKit
import Foundation
import LumiKit

/// `context:delete-file` / `reveal-in-file-manager` karşılıkları.
///
/// **Path guard (design/02 §8 sapmasının kapatılması, refactor 3.9):** çöpe
/// atma ve Finder'da gösterme yalnız BİLİNEN köklerin (projectsRoot +
/// additionalPaths) altındaki path'lerde çalışır. Guard `RepoPathGuard` ile
/// paylaşılır (git tarafıyla tek kural). Kök listesi boşsa (henüz
/// yapılandırılmamış ilk açılış) ev dizinine düşülür — aksi halde tüm
/// operasyonlar sessizce kilitlenirdi.
public struct FileSystemOperations: Sendable {
    private let allowedRoots: @Sendable () async -> [String]
    private let guardian: RepoPathGuard
    private let trashItem: @Sendable (URL) throws -> Void
    private let reveal: @Sendable (URL) -> Void

    public init(
        allowedRoots: @escaping @Sendable () async -> [String] = { [NSHomeDirectory()] },
        pathGuard: RepoPathGuard = RepoPathGuard(),
        trashItem: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        },
        reveal: @escaping @Sendable (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        }
    ) {
        self.allowedRoots = allowedRoots
        self.guardian = pathGuard
        self.trashItem = trashItem
        self.reveal = reveal
    }

    public func trash(path: String) async throws {
        try await verify(path)
        do {
            try trashItem(URL(fileURLWithPath: path))
        } catch {
            throw LumiError.fileOperationFailed(path: path, detail: error.localizedDescription)
        }
    }

    /// Senkron sözleşme (`SystemServicing.revealInFinder`) korunur; guard
    /// ihlalinde sessizce no-op + log (kullanıcı akışında bir hata diyaloğu
    /// yoktur, ama iz bırakılır).
    public func revealInFinder(path: String) async {
        do {
            try await verify(path)
        } catch {
            fputs("[lumi-fs] reveal reddedildi (bilinen kök dışı): \(path)\n", stderr)
            return
        }
        reveal(URL(fileURLWithPath: path))
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
