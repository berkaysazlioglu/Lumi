import LumiKit
import LumiState
import SwiftUI

/// FileViewer modal'ı (spec/22): view / diff / commit-diff modları.
/// Diff'ler tek kolonlu unified render (karar 4); commit-diff dosya seçiminde
/// lazy yüklenir (karar 6).
struct FileViewerView: View {
    let store: FileViewerStore
    let highlighter: any SyntaxHighlighting

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.55)
                    .contentShape(Rectangle())
                    .onTapGesture { store.close() }
                panel
                    .frame(
                        width: geometry.size.width * 0.85,
                        height: geometry.size.height * 0.8
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            content
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        )
        .onExitCommand { store.close() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.accentPrimary)
            Text(headerTitle)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            Button {
                store.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.bgElevated)
    }

    private var headerIcon: String {
        switch store.mode {
        case .view: return "doc.text"
        case .diff: return "plus.forwardslash.minus"
        case .commitDiff: return "clock.arrow.circlepath"
        }
    }

    private var headerTitle: String {
        if store.mode == .commitDiff, let context = store.commitContext {
            return "\(context.shortSha) · \(context.files.count) files"
        }
        return store.filePath
    }

    @ViewBuilder
    private var content: some View {
        switch store.mode {
        case .view:
            HighlightedCodeView(
                code: store.fileContent ?? "",
                fileName: store.filePath,
                highlighter: highlighter
            )
        case .diff:
            diffContent
        case .commitDiff:
            HStack(spacing: 0) {
                commitFileList
                    .frame(width: 220)
                Rectangle().fill(Theme.border).frame(width: 1)
                diffContent
            }
        }
    }

    @ViewBuilder
    private var diffContent: some View {
        if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diff = store.diff {
            AttributedTextView(text: DiffAttributedTextBuilder.build(diff, fontSize: 12))
        } else {
            Text("(no diff)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var commitFileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(store.commitContext?.files ?? []) { file in
                    Button {
                        Task { await store.selectCommitFile(file.path) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(file.status.badge)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.fileChangeColor(for: file.status))
                                .frame(width: 14)
                            Text((file.path as NSString).lastPathComponent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(
                                    store.filePath == file.path
                                        ? Theme.textPrimary : Theme.textSecondary
                                )
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            store.filePath == file.path ? Theme.bgElevated : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(file.path)
                }
            }
            .padding(.vertical, 6)
        }
        .background(Theme.bgSurface)
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
            attributed = await highlighter.highlight(code: code, fileName: fileName, fontSize: 13)
        }
    }
}
