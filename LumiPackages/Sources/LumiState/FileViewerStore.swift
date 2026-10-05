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

/// Markdown dosyasının sunumu (karar 112: `both` — solda ham, sağda render).
public enum MarkdownDisplay: Equatable, Sendable, CaseIterable {
    case raw
    case both
    case preview
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

private extension ViewerPresentation {
    /// Seçimin geçerli kaldığı kimlik: aynı dosyanın yüklemesi bitince seçim
    /// korunur, başka dosya/mod/kapanış sıfırlar.
    var selectionIdentity: String? {
        switch self {
        case .hidden: return nil
        case .file(let repoPath, let filePath, let mode, _): return "\(mode)|\(repoPath)|\(filePath)"
        case .commit(let repoPath, let context, let filePath, _): return "commit|\(repoPath)|\(context.sha)|\(filePath ?? "")"
        }
    }
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

    public private(set) var presentation: ViewerPresentation = .hidden {
        didSet {
            // Seçim ve taslak yalnız gösterildiği dosyaya aittir (karar 100/110).
            guard oldValue.selectionIdentity != presentation.selectionIdentity else { return }
            selectedLines = nil
            resetEditing()
        }
    }

    /// Karar 110: kaydedilmemiş düzenleme. `nil` = metin diskte okunanla aynı.
    public private(set) var draft: String?

    /// Karar 110: kaydetme durumu. `.conflict` — dosya yüklendikten sonra
    /// diskte değişti (ajan düzenlemesi); kullanıcı üzerine yazmayı ya da
    /// yeniden yüklemeyi seçer.
    public enum SaveState: Equatable, Sendable {
        case idle
        case saving
        case conflict
    }

    public private(set) var saveState: SaveState = .idle

    /// Editör metninin yeniden kurulma sayacı: yükleme, yeniden yükleme ve
    /// vazgeçmede artar. View metni yalnız bu değişince baştan basar; aradaki
    /// her değişiklik kullanıcının kendi yazdığıdır (karar 110).
    public private(set) var editorRevision = 0

    /// Kaydedilmemiş taslak varken istenen geçiş (kapatma, başka dosya) onay
    /// bekler; `true` iken viewer `Save / Discard / Cancel` sorar.
    public private(set) var isConfirmingDiscard = false
    @ObservationIgnored private var pendingTransition: (@MainActor () async -> Void)?

    /// Kod görünümündeki seçimin 1 tabanlı satır aralığı (karar 100); view
    /// katmanı NSTextView seçiminden yazar. Persist edilmez.
    public var selectedLines: ClosedRange<Int>?

    /// Markdown dosyalarında sunum tercihi (karar 21/109/112): ham metin,
    /// render ya da ikisi yan yana. Oturumluk — persist edilmez.
    public var markdownDisplay: MarkdownDisplay = .preview

    /// ISP (refactor 3.8): fırlatan içerik okumaları + sessiz `commitFiles`/
    /// `imagePreview`. Commit YAZIMI (`GitWriting`) bu store'un yüzeyinde yok.
    @ObservationIgnored private let git: any GitContentReading & GitReading & FileContentWriting
    @ObservationIgnored private let toasts: ToastStore

    public init(git: any GitContentReading & GitReading & FileContentWriting, toasts: ToastStore) {
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

    /// Fiilen uygulanan markdown sunumu: markdown olmayan dosyada hep `.raw`;
    /// diff/commit'te yan yana görünüm yoktur (iki taraf zaten diff'tir) —
    /// `.both` orada `.preview` sayılır (karar 112).
    public var effectiveMarkdownDisplay: MarkdownDisplay {
        guard previewKind == .markdown else { return .raw }
        if markdownDisplay == .both, mode != .view { return .preview }
        return markdownDisplay
    }

    /// Yalnız render'lı tam sunum (Preview) açık mı.
    public var isRenderedMarkdown: Bool { effectiveMarkdownDisplay == .preview }

    /// Solda ham editör, sağda canlı önizleme (karar 112).
    public var isSplitMarkdown: Bool { effectiveMarkdownDisplay == .both }

    /// "Mention in Chat" ile ajana yapıştırılacak referans (karar 100).
    /// Yalnız çalışma kopyasının ham metin görünümünde vardır: diff ve
    /// render'lı markdown satırları dosyanın satırlarına birebir eşlenmez.
    /// Kaydedilmemiş taslakta da yoktur: ajan dosyayı diskten okur, satırlar
    /// kaymış olabilir (karar 110).
    public var mentionReference: String? {
        guard mode == .view, !isRenderedMarkdown, draft == nil, let lines = selectedLines,
              case .loaded(.text) = content else { return nil }
        return CodeMention.reference(filePath: filePath, repoPath: repoPath, lines: lines)
    }

    // MARK: - Düzenleme (karar 110)

    /// Diskte okunan metin — taslağın karşılaştırma tabanı.
    public var loadedText: String? {
        guard case .file(_, _, .view, .loaded(.text(let text))) = presentation else { return nil }
        return text
    }

    /// Ekranda olması gereken metin: taslak varsa o, yoksa diskteki.
    public var displayedText: String? { draft ?? loadedText }

    public var hasUnsavedChanges: Bool { draft != nil }

    /// Düzenlenebilir mi: çalışma kopyasının ham metin görünümü. Diff, commit
    /// ve render'lı markdown satırları dosyaya birebir eşlenmez; UTF-8 olmayan
    /// dosya okumada `U+FFFD`'ye çevrildiği için yazmak onu bozardı.
    public var isEditable: Bool {
        !isRenderedMarkdown && loadedText != nil && isLosslessText
    }

    /// Yüklenen metin UTF-8'den kayıpsız mı çözüldü (yüklemede bir kez
    /// hesaplanır — her tuşta 8 MB'lık taramayı önler).
    private var isLosslessText = true

    /// Editörden gelen metin; diskle aynıya dönerse taslak düşer.
    public func updateDraft(_ text: String) {
        guard isEditable else { return }
        let next = text == loadedText ? nil : text
        guard next != draft else { return }
        draft = next
        if saveState == .conflict { saveState = .idle }
    }

    /// Taslağı diske yazar. Dosya yüklendikten sonra diskte değiştiyse
    /// (`overwrite` istenmedikçe) yazmaz, `.conflict`'e geçer. Başarıda
    /// yazılan metin yeni taban olur; başarısızlık toast + taslak korunur.
    @discardableResult
    public func save(overwrite: Bool = false) async -> Bool {
        guard let draft, saveState != .saving,
              case .file(let repoPath, let filePath, .view, .loaded(.text(let original))) = presentation
        else { return false }
        saveState = .saving
        do {
            if !overwrite {
                let onDisk = try await git.readFile(repoPath: repoPath, file: filePath)
                guard onDisk == original else {
                    if isStillPresenting(repoPath: repoPath, filePath: filePath, mode: .view) { saveState = .conflict }
                    return false
                }
            }
            try await git.writeFile(repoPath: repoPath, file: filePath, contents: draft)
        } catch {
            saveState = .idle
            toasts.show(error: (error as? LumiError) ?? .underlying(domain: "unknown", message: "\(error)"))
            return false
        }
        guard isStillPresenting(repoPath: repoPath, filePath: filePath, mode: .view) else { return true }
        // Taban yeni metne geçer; editörün metni zaten bu — yeniden basılmaz.
        let savedDraft = draft
        presentation = .file(repoPath: repoPath, filePath: filePath, mode: .view, content: .loaded(.text(savedDraft)))
        if self.draft == savedDraft { self.draft = nil }
        saveState = .idle
        return true
    }

    /// Çakışmada diskteki sürümü yükler; taslak atılır.
    public func reloadFromDisk() async {
        guard case .file(let repoPath, let filePath, .view, _) = presentation else { return }
        resetEditing()
        await presentFile(mode: .view, repoPath: repoPath, filePath: filePath)
    }

    /// Onay: taslağı at ve bekleyen geçişi sürdür.
    public func confirmDiscard() async {
        let transition = pendingTransition
        resetEditing()
        await transition?()
    }

    /// Onay: kaydet, başarılıysa bekleyen geçişi sürdür.
    public func saveAndContinue() async {
        let transition = pendingTransition
        isConfirmingDiscard = false
        pendingTransition = nil
        guard await save() else { return }
        await transition?()
    }

    public func cancelDiscard() {
        isConfirmingDiscard = false
        pendingTransition = nil
    }

    /// Taslak varsa geçişi onaya bağlar ve `false` döner (çağıran durur).
    private func allowsTransition(_ transition: @escaping @MainActor () async -> Void) -> Bool {
        guard draft != nil else { return true }
        pendingTransition = transition
        isConfirmingDiscard = true
        return false
    }

    private func resetEditing() {
        draft = nil
        saveState = .idle
        isConfirmingDiscard = false
        pendingTransition = nil
        editorRevision += 1
    }

    // MARK: - Sunum modları

    public func presentView(repoPath: String, filePath: String) async {
        guard allowsTransition({ [weak self] in await self?.presentView(repoPath: repoPath, filePath: filePath) })
        else { return }
        await presentFile(mode: .view, repoPath: repoPath, filePath: filePath)
    }

    public func presentDiff(repoPath: String, filePath: String) async {
        guard allowsTransition({ [weak self] in await self?.presentDiff(repoPath: repoPath, filePath: filePath) })
        else { return }
        await presentFile(mode: .diff, repoPath: repoPath, filePath: filePath)
    }

    /// Karar 6: commit seçilince yalnız dosya listesi; ilk dosya (ya da
    /// listede varsa `initialFile`) seçilir ve onun diff'i lazy yüklenir.
    public func presentCommit(repoPath: String, commit: GitCommit, initialFile: String? = nil) async {
        guard allowsTransition({ [weak self] in
            await self?.presentCommit(repoPath: repoPath, commit: commit, initialFile: initialFile)
        }) else { return }
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
        let initial = files.first { $0.path == initialFile } ?? files[0]
        await selectCommitFile(initial.path)
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

    /// Kaydedilmemiş taslak varsa önce onay sorulur (karar 110).
    public func close() {
        guard allowsTransition({ [weak self] in self?.close() }) else { return }
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
        if case .loaded(.text(let text)) = loaded { isLosslessText = !text.contains("\u{FFFD}") }
        editorRevision += 1
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
