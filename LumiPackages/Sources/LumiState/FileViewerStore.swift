import Foundation
import LumiKit
import Observation

/// FileViewer'ın gösterdiği içerik (karar 4 side-by-side diff, karar 21
/// render'lı markdown + görsel önizleme). Üç seçenek birbirini dışlar.
public enum ViewerContent: Equatable, Sendable {
    case text(String)
    case diff(UnifiedDiff)
    case image(ImagePreview)
    /// Metin olarak sunulamayan dosya (video, arşiv, derlenmiş çıktı…). Bir
    /// HATA değildir: toast düşmez, modal açık kalır ve nedeni gösterir.
    case unsupported(reason: String)
}

/// Seçili commit'in kimliği + dosya listesi (karar 6: diff lazy yüklenir).
public struct CommitContext: Equatable, Sendable {
    public let sha: String
    public let shortSha: String
    public let files: [CommitFile]

    public init(sha: String, shortSha: String, files: [CommitFile]) {
        self.sha = sha
        self.shortSha = shortSha
        self.files = files
    }
}

/// FileViewer'ın TEK state alanı (refactor 5.3).
///
/// Önceki model `mode` + 4 opsiyonel alan tutuyordu: 48 kombinasyondan ~5'i
/// geçerliydi ve her sunum yolu diğer alanları elle `nil`liyordu. Sum type'ta
/// "diff varken metin de dolu", "kapalı ama içerik duruyor", "hata aldık ama
/// eski dosya ekranda" gibi durumlar temsil EDİLEMEZ.
public enum ViewerPresentation: Equatable, Sendable {
    /// Tek dosya sunumunun kaynağı: çalışma kopyası içeriği mi, diff mi.
    /// (Yükleme sürerken ve hata durumunda içerikten türetilemediği için
    /// vakanın kendisinde taşınır.)
    public enum FileMode: Equatable, Sendable {
        case view
        case diff
    }

    case hidden
    case file(
        repoPath: String,
        filePath: String,
        mode: FileMode,
        content: Loadable<ViewerContent>
    )
    /// `filePath`/`content` birlikte hareket eder: dosya seçilene kadar ikisi de
    /// `nil` (commit açıldı, ilk dosyanın yüklemesi henüz başlamadı).
    case commit(
        repoPath: String,
        context: CommitContext,
        filePath: String?,
        content: Loadable<ViewerContent>?
    )
}

/// FileViewer modal state'i (karar 4 side-by-side diff, karar 6 lazy
/// commit-diff, karar 21 markdown/görsel sunumu). Persist edilmez.
///
/// **Hata yolu tek kuraldır (karar 5):** herhangi bir yükleme başarısız olursa
/// içerik `.failed(mesaj)` olur ve toast düşer — modal yeni dosyanın adıyla
/// açık kalır, ÖNCEKİ dosyanın içeriği asla ekranda kalmaz.
@Observable
@MainActor
public final class FileViewerStore {
    /// View katmanının okuduğu geniş mod (facade); commit sunumu `.commitDiff`.
    public enum Mode: Equatable, Sendable {
        case view
        case diff
        case commitDiff
    }

    public private(set) var presentation: ViewerPresentation = .hidden

    /// Markdown dosyalarında render'lı sunum (kapatılınca ham metin/diff).
    /// Oturumluk — persist edilmez (design/03 §6 Rendered ⇄ Raw rozeti).
    public var rendersMarkdown = true

    /// ISP (refactor 3.8): fırlatan içerik okumaları + sessiz `commitFiles`/
    /// `imagePreview`. Commit YAZIMI (`GitWriting`) bu store'un yüzeyinde yok.
    @ObservationIgnored private let git: any GitContentReading & GitReading
    @ObservationIgnored private let toasts: ToastStore

    public init(git: any GitContentReading & GitReading, toasts: ToastStore) {
        self.git = git
        self.toasts = toasts
    }

    // MARK: - Türev okumalar (view'ların facade'ı)

    public var isPresented: Bool {
        if case .hidden = presentation { return false }
        return true
    }

    public var mode: Mode {
        switch presentation {
        case .hidden: return .view
        case .file(_, _, let mode, _): return mode == .diff ? .diff : .view
        case .commit: return .commitDiff
        }
    }

    public var repoPath: String {
        switch presentation {
        case .hidden: return ""
        case .file(let repoPath, _, _, _): return repoPath
        case .commit(let repoPath, _, _, _): return repoPath
        }
    }

    /// Gösterilen dosya; commit'te henüz dosya seçilmemişse boş.
    public var filePath: String {
        switch presentation {
        case .hidden: return ""
        case .file(_, let filePath, _, _): return filePath
        case .commit(_, _, let filePath, _): return filePath ?? ""
        }
    }

    public var commitContext: CommitContext? {
        if case .commit(_, let context, _, _) = presentation { return context }
        return nil
    }

    public var content: Loadable<ViewerContent>? {
        switch presentation {
        case .hidden: return nil
        case .file(_, _, _, let content): return content
        case .commit(_, _, _, let content): return content
        }
    }

    public var isLoading: Bool { content?.isLoading ?? false }

    public var failureMessage: String? { content?.failureMessage }

    /// Aktif dosyanın sunum sınıfı (uzantıdan türetilir).
    public var previewKind: FilePreviewKind { FilePreviewKind.of(path: filePath) }

    /// Markdown render'ı fiilen açık mı: uzantı + oturumluk tercih.
    public var isRenderedMarkdown: Bool { previewKind == .markdown && rendersMarkdown }

    // MARK: - Sunum modları

    public func presentView(repoPath: String, filePath: String) async {
        await presentFile(mode: .view, repoPath: repoPath, filePath: filePath)
    }

    public func presentDiff(repoPath: String, filePath: String) async {
        await presentFile(mode: .diff, repoPath: repoPath, filePath: filePath)
    }

    /// Karar 6: commit seçilince yalnız dosya listesi; ilk dosya default seçilir
    /// ve onun diff'i lazy yüklenir.
    public func presentCommit(repoPath: String, commit: GitCommit) async {
        let files = await git.commitFiles(repoPath: repoPath, sha: commit.hash)
        guard !files.isEmpty else {
            toasts.show(.info, title: commit.shortHash, message: "Commit has no file changes")
            return
        }
        let context = CommitContext(sha: commit.hash, shortSha: commit.shortHash, files: files)
        presentation = .commit(
            repoPath: repoPath,
            context: context,
            filePath: nil,
            content: nil
        )
        await selectCommitFile(files[0].path)
    }

    public func selectCommitFile(_ path: String) async {
        guard case .commit(let repoPath, let context, _, _) = presentation else { return }
        presentation = .commit(
            repoPath: repoPath,
            context: context,
            filePath: path,
            content: .loading
        )
        let loaded = await load(repoPath: repoPath, filePath: path, mode: .diff, sha: context.sha)
        guard isStillSelected(commitSha: context.sha, filePath: path) else { return }
        presentation = .commit(
            repoPath: repoPath,
            context: context,
            filePath: path,
            content: loaded
        )
    }

    public func close() {
        presentation = .hidden
    }

    // MARK: - Yükleme

    private func presentFile(
        mode: ViewerPresentation.FileMode,
        repoPath: String,
        filePath: String
    ) async {
        presentation = .file(
            repoPath: repoPath,
            filePath: filePath,
            mode: mode,
            content: .loading
        )
        let loaded = await load(repoPath: repoPath, filePath: filePath, mode: mode, sha: nil)
        guard isStillPresenting(repoPath: repoPath, filePath: filePath, mode: mode) else { return }
        presentation = .file(
            repoPath: repoPath,
            filePath: filePath,
            mode: mode,
            content: loaded
        )
    }

    /// Tek yükleme koridoru: dosya türü yolu seçer, hata tek kurala düşer.
    private func load(
        repoPath: String,
        filePath: String,
        mode: ViewerPresentation.FileMode,
        sha: String?
    ) async -> Loadable<ViewerContent> {
        // Görsel dosyada metin/diff okuma anlamsız (binary → bozuk UTF8).
        // Git tarafı sessizdir (eksik taraf normaldir) — placeholder'ı UI çizer.
        let kind = FilePreviewKind.of(path: filePath)
        guard kind != .image else {
            let preview = await git.imagePreview(repoPath: repoPath, file: filePath, sha: sha)
            return .loaded(.image(preview))
        }
        // Video/arşiv gibi binary'ler view modunda hiç OKUNMAZ (yüzlerce MB'lık
        // dosyayı UTF8'e çevirip NSTextView'a basmak çöküyordu). Diff yollarında
        // git binary'yi kendisi işaretler (`UnifiedDiff.isBinary`).
        if kind == .binary, mode == .view, sha == nil {
            let fileExtension = (filePath as NSString).pathExtension.lowercased()
            return .loaded(.unsupported(
                reason: "No preview for .\(fileExtension) files (binary content)"
            ))
        }
        do {
            return .loaded(try await readContent(
                repoPath: repoPath,
                filePath: filePath,
                mode: mode,
                sha: sha
            ))
        } catch let error as LumiError {
            toasts.show(error: error)
            return .failed(error.localizedDescription)
        } catch {
            let wrapped = LumiError.underlying(domain: "unknown", message: "\(error)")
            toasts.show(error: wrapped)
            return .failed(wrapped.localizedDescription)
        }
    }

    private func readContent(
        repoPath: String,
        filePath: String,
        mode: ViewerPresentation.FileMode,
        sha: String?
    ) async throws -> ViewerContent {
        if let sha {
            return .diff(try await git.commitFileDiff(repoPath: repoPath, sha: sha, file: filePath))
        }
        switch mode {
        case .view:
            return .text(try await git.readFile(repoPath: repoPath, file: filePath))
        case .diff:
            return .diff(try await git.fileDiff(repoPath: repoPath, file: filePath))
        }
    }

    // MARK: - Yarış koruması
    //
    // Yükleme sürerken kullanıcı başka bir dosya açabilir; geç dönen sonuç
    // yeni sunumu EZMEZ (eski davranışta alanlar sırasız yazılabiliyordu).

    private func isStillPresenting(
        repoPath: String,
        filePath: String,
        mode: ViewerPresentation.FileMode
    ) -> Bool {
        guard case .file(let currentRepo, let currentFile, let currentMode, _) = presentation
        else { return false }
        return currentRepo == repoPath && currentFile == filePath && currentMode == mode
    }

    private func isStillSelected(commitSha: String, filePath: String) -> Bool {
        guard case .commit(_, let context, let currentFile, _) = presentation else { return false }
        return context.sha == commitSha && currentFile == filePath
    }
}
