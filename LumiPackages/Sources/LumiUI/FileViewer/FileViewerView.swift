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

    @Shell private var shell

    /// Modal'ın kabına oranı ve commit dosya listesinin genişliği — ölçek dışı
    /// geometri sabitleri.
    private enum Metrics {
        static let widthRatio: CGFloat = 0.85
        static let heightRatio: CGFloat = 0.8
        static let commitListWidth: CGFloat = 220
        static let statusBadgeWidth: CGFloat = 14
        /// Başlık şeridinin iç kenar payları (ölçek dışı ara değerler).
        static let headerInsetH: CGFloat = 14
        static let headerInsetV: CGFloat = 10
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
            Spacer()
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

    /// Markdown'da render'lı ↔ ham geçişi (karar 21; oturumluk, persist edilmez).
    private var markdownToggle: some View {
        let isRendered = store.rendersMarkdown
        return Button {
            store.rendersMarkdown.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: isRendered ? "textformat" : "chevron.left.slash.chevron.right")
                    .accessibilityHidden(true)
                Text(isRendered ? "Rendered" : "Raw")
            }
            .font(Theme.Typography.mono(.caption, weight: .semibold))
            .foregroundStyle(isRendered ? Theme.accentPrimary : Theme.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            // 3pt: ölçek dışı ara değer (v1 paritesi korunuyor).
            .padding(.vertical, 3)
            .background((isRendered ? Theme.accentPrimary : Theme.textMuted).opacity(0.18))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isRendered ? "Show raw markdown diff" : "Show rendered markdown")
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
                RenderedMarkdownDocumentView(text: text)
            } else {
                HighlightedCodeView(
                    code: text,
                    fileName: store.filePath,
                    highlighter: highlighter
                )
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

/// Markdown dökümanı: model GeometryReader altında her body'de yeniden parse
/// ediliyordu; içerik değişince BİR KEZ kurulur (HighlightedCodeView kalıbı).
private struct RenderedMarkdownDocumentView: View {
    let text: String

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
        .task(id: text) {
            model = MarkdownDiffBuilder.buildDocument(text)
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

/// view modu içeriği: async highlight + 1MB üstü düz metin (HighlightrEngine).
private struct HighlightedCodeView: View {
    let code: String
    let fileName: String
    let highlighter: any SyntaxHighlighting

    @State private var attributed: NSAttributedString?

    var body: some View {
        Group {
            if let attributed {
                AttributedTextView(text: attributed)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: code) {
            attributed = await highlighter.highlight(
                code: code,
                fileName: fileName,
                fontSize: Theme.Typography.Size.base.points
            )
        }
    }
}

#if DEBUG
#Preview("FileViewerView — view") {
    let shell = ShellContext.preview()
    FileViewerView(store: shell.fileViewer, highlighter: shell.highlighter)
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
    FileViewerView(store: shell.fileViewer, highlighter: shell.highlighter)
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
