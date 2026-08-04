import Foundation
import LumiKit
import Observation

/// FileViewer modal state'i (spec/22 FileViewer; karar 4 unified diff,
/// karar 6 lazy commit-diff). Persist edilmez (spec/21 §11).
@Observable
@MainActor
public final class FileViewerStore {
    public enum Mode: Equatable {
        case view
        case diff
        case commitDiff
    }

    public struct CommitContext: Equatable {
        public let sha: String
        public let shortSha: String
        public let files: [CommitFile]
    }

    public private(set) var isPresented = false
    public private(set) var mode: Mode = .view
    public private(set) var repoPath = ""
    public private(set) var filePath = ""
    public private(set) var fileContent: String?
    public private(set) var diff: UnifiedDiff?
    /// Karar 21: görsel dosyalarda `diff`/`fileContent` yerine bu dolu olur.
    public private(set) var imagePreview: ImagePreview?
    public private(set) var commitContext: CommitContext?
    public private(set) var isLoading = false
    /// Markdown dosyalarında render'lı sunum (kapatılınca ham metin/diff).
    /// Oturumluk — persist edilmez (spec/21 §11).
    public var rendersMarkdown = true

    /// Aktif dosyanın sunum sınıfı (uzantıdan).
    public var previewKind: FilePreviewKind { FilePreviewKind.of(path: filePath) }

    @ObservationIgnored private let git: any GitServicing
    @ObservationIgnored private let toasts: ToastStore

    public init(git: any GitServicing, toasts: ToastStore) {
        self.git = git
        self.toasts = toasts
    }

    // MARK: - Sunum modları

    public func presentView(repoPath: String, filePath: String) async {
        // Görsel dosyada metin okuma anlamsız (binary → bozuk UTF8): önizleme
        guard FilePreviewKind.of(path: filePath) != .image else {
            await presentImage(mode: .view, repoPath: repoPath, filePath: filePath, sha: nil)
            return
        }
        let succeeded = await toasts.reporting {
            self.fileContent = try await self.git.readFile(repoPath: repoPath, file: filePath)
        }
        guard succeeded else { return }
        self.repoPath = repoPath
        self.filePath = filePath
        mode = .view
        diff = nil
        imagePreview = nil
        commitContext = nil
        isPresented = true
    }

    public func presentDiff(repoPath: String, filePath: String) async {
        guard FilePreviewKind.of(path: filePath) != .image else {
            await presentImage(mode: .diff, repoPath: repoPath, filePath: filePath, sha: nil)
            return
        }
        let succeeded = await toasts.reporting {
            self.diff = try await self.git.fileDiff(repoPath: repoPath, file: filePath)
        }
        guard succeeded else { return }
        self.repoPath = repoPath
        self.filePath = filePath
        mode = .diff
        fileContent = nil
        imagePreview = nil
        commitContext = nil
        isPresented = true
    }

    /// Karar 6: commit seçilince yalnız dosya listesi; ilk dosya default seçilir
    /// ve onun diff'i lazy yüklenir.
    public func presentCommit(repoPath: String, commit: GitCommit) async {
        let files = await git.commitFiles(repoPath: repoPath, sha: commit.hash)
        guard !files.isEmpty else {
            toasts.show(.info, title: commit.shortHash, message: "Commit has no file changes")
            return
        }
        self.repoPath = repoPath
        mode = .commitDiff
        fileContent = nil
        commitContext = CommitContext(sha: commit.hash, shortSha: commit.shortHash, files: files)
        isPresented = true
        await selectCommitFile(files[0].path)
    }

    public func selectCommitFile(_ path: String) async {
        guard let context = commitContext else { return }
        filePath = path
        isLoading = true
        defer { isLoading = false }
        diff = nil
        imagePreview = nil
        guard FilePreviewKind.of(path: path) != .image else {
            await presentImage(
                mode: .commitDiff,
                repoPath: repoPath,
                filePath: path,
                sha: context.sha
            )
            return
        }
        await toasts.reporting {
            self.diff = try await self.git.commitFileDiff(
                repoPath: self.repoPath,
                sha: context.sha,
                file: path
            )
        }
    }

    /// Karar 21: görsel dosyalar diff/metin yerine önizlemeyle sunulur. Git
    /// tarafı sessizdir (eksik taraf normaldir), o yüzden toast koridoru yok —
    /// üretilemeyen önizlemeyi UI placeholder ile bildirir.
    private func presentImage(
        mode newMode: Mode,
        repoPath: String,
        filePath: String,
        sha: String?
    ) async {
        let preview = await git.imagePreview(repoPath: repoPath, file: filePath, sha: sha)
        self.repoPath = repoPath
        self.filePath = filePath
        self.mode = newMode
        fileContent = nil
        diff = nil
        if newMode != .commitDiff { commitContext = nil }
        imagePreview = preview
        isPresented = true
    }

    public func close() {
        isPresented = false
        fileContent = nil
        diff = nil
        imagePreview = nil
        commitContext = nil
        filePath = ""
    }
}
