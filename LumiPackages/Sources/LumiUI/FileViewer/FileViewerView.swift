import LumiKit
import LumiState
import SwiftUI

/// FileViewer modal'ı: view / diff / commit-diff modları.
/// Diff'ler side-by-side render (karar 4 revize); commit-diff dosya seçiminde
/// lazy yüklenir (karar 6). Markdown dosyaları render'lı tek kolon, görseller
/// before/after önizleme olarak gösterilir (karar 21).
///
/// Karartma + kapatma sözleşmesi ortak `ModalOverlay`'dedir, yüzey ortak
/// `Panel`'dir (Faz 7.2): dışarı tıklama ve Escape tek yerde tanımlıdır.
struct FileViewerView: View {
    let store: FileViewerStore
    let highlighter: any SyntaxHighlighting
    let markdownParser: any MarkdownParsing

    @Shell private var shell

    /// Modal'ın kabına oranı ve commit dosya listesinin genişliği — ölçek dışı
    /// geometri sabitleri.
    private enum Metrics {
        static let widthRatio: CGFloat = 0.85
        static let heightRatio: CGFloat = 0.8
        static var commitListWidth: CGFloat { Theme.scaled(220) }
        static var statusBadgeWidth: CGFloat { Theme.scaled(14) }
        /// Başlık şeridinin iç kenar payları (ölçek dışı ara değerler).
        static var headerInsetH: CGFloat { Theme.scaled(14) }
        static var headerInsetV: CGFloat { Theme.scaled(10) }
        /// `Raw | Preview` anahtarı — iki eşit bölme (karar 109).
        static var markdownSwitchWidth: CGFloat { Theme.scaled(150) }
        /// `Raw | Both | Preview` — üç eşit bölme (karar 112).
        static var markdownSwitchWideWidth: CGFloat { Theme.scaled(216) }
        /// Kaydedilmemiş değişiklik noktası (karar 110).
        static var unsavedDotSide: CGFloat { Theme.scaled(7) }
    }

    var body: some View {
        GeometryReader { geometry in
            ModalOverlay(onDismiss: store.close) {
                panel
                    .frame(
                        width: geometry.size.width * Metrics.widthRatio,
                        height: geometry.size.height * Metrics.heightRatio
                    )
            }
            if store.isConfirmingDiscard {
                UnsavedChangesPrompt(store: store)
            }
        }
    }

    private var panel: some View {
        Panel(variant: .card) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                content
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: headerIcon)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.accentPrimary)
                .accessibilityHidden(true)
            Text(headerTitle)
                .font(Theme.Typography.baseMono)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if store.hasUnsavedChanges {
                Circle()
                    .fill(Theme.warning)
                    .frame(width: Metrics.unsavedDotSide, height: Metrics.unsavedDotSide)
                    .help("Unsaved changes")
                    .accessibilityLabel("Unsaved changes")
            }
            Spacer()
            if store.mentionReference != nil {
                MentionInChatButton(store: store)
            }
            if store.isEditable || store.hasUnsavedChanges {
                SaveFileButton(store: store)
            }
            if store.previewKind == .markdown {
                markdownToggle
            }
            IconButton(
                systemName: "xmark",
                label: "Close file viewer",
                size: .caption,
                side: 22
            ) {
                store.close()
            }
        }
        .padding(.horizontal, Metrics.headerInsetH)
        .padding(.vertical, Metrics.headerInsetV)
        .background(Theme.bgElevated)
    }

    private var headerIcon: String {
        if store.previewKind == .image { return "photo" }
        if store.previewKind == .binary { return "doc.zipper" }
        switch store.mode {
        case .view: return "doc.text"
        case .diff: return "plus.forwardslash.minus"
        case .commitDiff: return "clock.arrow.circlepath"
        }
    }

    /// Markdown'da ham ↔ render'lı geçişi (karar 21; oturumluk, persist
    /// edilmez). Karar 109: header'ın sağında hep görünen anahtar. Karar 112:
    /// view modunda üçüncü seçenek `Both` — solda düzenlenebilir ham metin,
    /// sağda canlı önizleme; diff'te yan yana zaten iki taraf olduğu için yok.
    private var markdownToggle: some View {
        let isView = store.mode == .view
        let options: [MarkdownDisplay] = isView ? [.raw, .both, .preview] : [.raw, .preview]
        return SegmentedModeSwitch(
            options: options,
            selection: Binding(
                get: { store.effectiveMarkdownDisplay },
                set: { display in
                    guard display != store.effectiveMarkdownDisplay else { return }
                    store.markdownDisplay = display
                    store.selectedLines = nil
                }
            ),
            title: { display in
                switch display {
                case .raw: return "Raw"
                case .both: return "Both"
                case .preview: return "Preview"
                }
            },
            help: { display in
                switch (display, isView) {
                case (.preview, true): return "Show rendered markdown"
                case (.raw, true): return "Show raw markdown source"
                case (.both, _): return "Edit the source with a live preview beside it"
                case (.preview, false): return "Show rendered markdown diff"
                case (.raw, false): return "Show raw side-by-side diff"
                }
            },
            accessibilityLabel: "Markdown display"
        )
        .frame(width: isView ? Metrics.markdownSwitchWideWidth : Metrics.markdownSwitchWidth)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.border, lineWidth: Theme.Stroke.hairline)
                .allowsHitTesting(false)
        )
    }

    private var headerTitle: String {
        if store.mode == .commitDiff, let context = store.commitContext {
            return "\(context.shortSha) · \(context.files.count) files"
        }
        return store.filePath
    }

    @ViewBuilder
    private var content: some View {
        switch store.presentation {
        case .hidden:
            EmptyView()
        case .file(_, _, let mode, let loadable):
            loadableContent(loadable, showsImageComparison: mode == .diff)
        case .commit(_, _, _, let loadable):
            HStack(spacing: 0) {
                commitFileList
                    .frame(width: Metrics.commitListWidth)
                Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                if let loadable {
                    loadableContent(loadable, showsImageComparison: true)
                } else {
                    placeholder("(no file selected)")
                }
            }
        }
    }

    /// Tek içerik koridoru (refactor 5.3): yükleniyor → spinner, hata →
    /// görünür mesaj, yüklendi → içerik tipine göre render. Eski dosyanın
    /// içeriği hiçbir durumda ekranda kalmaz.
    @ViewBuilder
    private func loadableContent(
        _ loadable: Loadable<ViewerContent>,
        showsImageComparison: Bool
    ) -> some View {
        switch loadable {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            failureState(message)
        case .loaded(let viewerContent):
            loadedContent(viewerContent, showsImageComparison: showsImageComparison)
        }
    }

    @ViewBuilder
    private func loadedContent(
        _ viewerContent: ViewerContent,
        showsImageComparison: Bool
    ) -> some View {
        switch viewerContent {
        case .image(let preview):
            ImagePreviewView(preview: preview, showsComparison: showsImageComparison)
        case .text(let text):
            if store.isRenderedMarkdown {
                // Karar 110: Preview kaydedilmemiş taslağı da gösterir.
                markdownPreview(store.draft ?? text)
            } else if store.isSplitMarkdown {
                // Karar 112: solda editör, sağda aynı taslağın canlı önizlemesi.
                HStack(spacing: 0) {
                    codeView(text)
                        .frame(maxWidth: .infinity)
                    Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                    markdownPreview(store.draft ?? text)
                        .frame(maxWidth: .infinity)
                }
            } else {
                codeView(text)
            }
        case .diff(let diff):
            if store.isRenderedMarkdown {
                RenderedMarkdownDiffView(diff: diff)
            } else {
                SideBySideDiffView(diff: diff, size: .body)
            }
        case .unsupported(let reason):
            unsupportedState(reason)
        }
    }

    private func markdownPreview(_ text: String) -> some View {
        RenderedMarkdownDocumentView(
            text: text,
            parser: markdownParser,
            highlighter: highlighter,
            onOpenLink: openMarkdownLink
        )
    }

    private func codeView(_ text: String) -> some View {
        HighlightedCodeView(
            code: store.draft ?? text,
            revision: store.editorRevision,
            fileName: store.filePath,
            highlighter: highlighter,
            onSelectLines: { store.selectedLines = $0 },
            onTextChange: store.isEditable ? { store.updateDraft($0) } : nil,
            onCancel: store.close
        )
    }

    /// Karar 109: göreli link aynı viewer'da açılır (GitHub paritesi), şemalı
    /// link sisteme gider; `#bölüm` ve kökten taşan yol yutulur.
    private func openMarkdownLink(_ url: URL) {
        switch MarkdownLinkTarget.resolve(url, from: store.filePath) {
        case .external(let url):
            shell.actions.openURL(url)
        case .file(let path):
            let repoPath = store.repoPath
            Task { await store.presentView(repoPath: repoPath, filePath: path) }
        case .anchor, .invalid:
            break
        }
    }

    /// Binary dosya (video, arşiv…): hata değil, "önizleme yok" bilgisi.
    private func unsupportedState(_ reason: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.zipper")
                .font(Theme.Typography.ui(.heading))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            Text(reason)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xxl)
            Button("Reveal in Finder") {
                shell.reveal(store.filePath)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Theme.Typography.ui(.heading))
                .foregroundStyle(Theme.error)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ text: String) -> some View {
        EmptyStatePlaceholder(text, density: .full)
    }

    private var commitFileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                ForEach(store.commitContext?.files ?? []) { file in
                    commitFileRow(file)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.bgSurface)
    }

    private func commitFileRow(_ file: CommitFile) -> some View {
        Button {
            Task { await store.selectCommitFile(file.path) }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(file.status.badgeText)
                    .font(Theme.Typography.mono(.caption, weight: .bold))
                    .foregroundStyle(Theme.fileChangeColor(for: file.status))
                    .frame(width: Metrics.statusBadgeWidth)
                Text((file.path as NSString).lastPathComponent)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(
                        store.filePath == file.path
                            ? Theme.textPrimary : Theme.textSecondary
                    )
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                store.filePath == file.path ? Theme.bgElevated : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.path)
    }
}

/// Markdown dökümanı (karar 109): cmark-gfm ağacı içerik değişince BİR KEZ
/// kurulur (HighlightedCodeView kalıbı) ve GitHub düzeninde çizilir.
private struct RenderedMarkdownDocumentView: View {
    let text: String
    let parser: any MarkdownParsing
    let highlighter: any SyntaxHighlighting
    let onOpenLink: (URL) -> Void

    @State private var document: MarkdownDocument?

    var body: some View {
        Group {
            if let document {
                MarkdownDocumentView(document: document, highlighter: highlighter, onOpenLink: onOpenLink)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: text) {
            // Karar 112: Both'ta her tuşta yeniden ayrıştırma — yazarken kısa
            // sükûnet beklenir; ilk açılış beklemez.
            if document != nil {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            document = parser.parse(text)
        }
    }
}

/// Markdown diff'i — aynı kalıp; diff değişince bir kez hesaplanır.
private struct RenderedMarkdownDiffView: View {
    let diff: UnifiedDiff

    @State private var model: MarkdownDiffBuilder.Model?

    var body: some View {
        Group {
            if let model {
                MarkdownDiffView(model: model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: diff) {
            model = MarkdownDiffBuilder.build(diff)
        }
    }
}

/// view modu içeriği: async highlight + 1MB üstü düz metin (HighlightJSEngine).
///
/// Karar 110: düzenlenirken her değişiklik yeniden vurgulanır; `task(id:)`
/// iptali kısa bekleme ile birleşince yazarken vurgulama ertelenir. Vurgu
/// hangi revizyon için üretildiyse onunla editöre iner (bayat vurgu yeni
/// yüklenen metni ezmesin).
private struct HighlightedCodeView: View {
    let code: String
    let revision: Int
    let fileName: String
    let highlighter: any SyntaxHighlighting
    let onSelectLines: (ClosedRange<Int>?) -> Void
    let onTextChange: ((String) -> Void)?
    let onCancel: () -> Void

    private struct Highlighted {
        let revision: Int
        let code: String
        let text: NSAttributedString
    }

    private struct Request: Equatable {
        let revision: Int
        let code: String
    }

    @State private var highlighted: Highlighted?

    /// Yazarken yeniden vurgulamadan önceki sükûnet süresi.
    private static let editDebounce: Duration = .milliseconds(250)

    var body: some View {
        Group {
            if let highlighted {
                AttributedTextView(
                    text: highlighted.text,
                    revision: highlighted.revision,
                    onSelectLines: onSelectLines,
                    onTextChange: onTextChange,
                    onCancel: onCancel
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: Request(revision: revision, code: code)) {
            let isEdit = highlighted?.revision == revision
            if isEdit {
                try? await Task.sleep(for: Self.editDebounce)
                guard !Task.isCancelled else { return }
            }
            let text = await highlighter.highlight(
                code: code,
                fileName: fileName,
                fontSize: Theme.Typography.Size.base.scaledPoints
            )
            guard !Task.isCancelled else { return }
            highlighted = Highlighted(revision: revision, code: code, text: text)
        }
    }
}

#if DEBUG
#Preview("FileViewerView — view") {
    let shell = ShellContext.preview()
    FileViewerView(store: shell.fileViewer, highlighter: shell.highlighter, markdownParser: shell.markdownParser)
        .frame(width: 900, height: 600)
        .background(Theme.bgDeep)
        .task {
            await shell.fileViewer.presentView(
                repoPath: "/Users/preview/Projects/lumi",
                filePath: "README.md"
            )
        }
}

#Preview("FileViewerView — diff") {
    let shell = ShellContext.preview()
    FileViewerView(store: shell.fileViewer, highlighter: shell.highlighter, markdownParser: shell.markdownParser)
        .frame(width: 900, height: 600)
        .background(Theme.bgDeep)
        .task {
            await shell.fileViewer.presentDiff(
                repoPath: "/Users/preview/Projects/lumi",
                filePath: "Sources/Lumi/App.swift"
            )
        }
}
#endif
