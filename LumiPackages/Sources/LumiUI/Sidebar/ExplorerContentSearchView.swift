import LumiKit
import LumiState
import SwiftUI

/// İçerik araması sonuç listesi (Explorer'ın Contents kipi).
///
/// Sorgu artık buraya AİT DEĞİL: tek arama şeridi (`ExplorerQueryStrip`)
/// yukarıda duruyor ve metni binding olarak veriyor — kip değişince sorgu
/// kaybolmuyor.
///
/// Sonuçlar dosya başına gruplanır (VS Code / Orca arama görünümü): düz bir
/// "path:line" listesinde aynı dosyanın 40 eşleşmesi diğer dosyaları ekrandan
/// atıyordu. Başlık satırı katlanabilir, eşleşme sayısını gösterir.
struct ExplorerContentSearchView: View {
    let repoPath: String
    @Binding var query: String
    @Shell private var shell
    @State private var result = ExplorerContentResult()
    @State private var loading = false
    @State private var error: String?
    /// Katlanmış dosya başlıkları — varsayılan AÇIK (boş küme).
    @State private var collapsed: Set<String> = []

    private struct Request: Equatable {
        let path: String
        let query: String
        let options: ExplorerOptions
        let revision: Int
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var request: Request {
        Request(path: repoPath, query: trimmedQuery,
                options: shell.repos.explorerOptions[repoPath] ?? ExplorerOptions(),
                revision: shell.repos.fileTreeRevisions[repoPath] ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !result.matches.isEmpty { summary }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    status
                    ForEach(result.fileGroups) { group in
                        fileHeader(group)
                        if !collapsed.contains(group.path) {
                            ForEach(group.matches) { matchRow($0) }
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .task(id: request) { await runSearch() }
        .onChange(of: repoPath) { collapsed = [] }
    }

    // MARK: - Üst özet ve durumlar

    private var summary: some View {
        Text(Self.summaryText(matches: result.matches.count, files: result.fileCount))
            .font(Theme.Typography.ui(.caption))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.bgSurface)
    }

    /// "12 results in 3 files" — tekil/çoğul ayrımı korunur.
    static func summaryText(matches: Int, files: Int) -> String {
        let matchLabel = matches == 1 ? "result" : "results"
        let fileLabel = files == 1 ? "file" : "files"
        return "\(matches) \(matchLabel) in \(files) \(fileLabel)"
    }

    @ViewBuilder
    private var status: some View {
        if loading {
            ProgressView().controlSize(.small).padding(Theme.Spacing.md)
        }
        if let error {
            Text(error)
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.error)
                .padding(Theme.Spacing.md)
        }
        if result.isLimited {
            Text("Search limit reached. Narrow your query.")
                .font(Theme.Typography.ui(.caption))
                .foregroundStyle(Theme.warning)
                .padding(Theme.Spacing.md)
        }
        if result.matches.isEmpty && !loading && error == nil {
            EmptyStatePlaceholder(
                trimmedQuery.isEmpty ? "Search across project files" : "No matches",
                density: .inline
            )
        }
    }

    // MARK: - Satırlar

    private func fileHeader(_ group: ExplorerContentFileGroup) -> some View {
        let isCollapsed = collapsed.contains(group.path)
        return HoverReader { hovering in
            Button { toggle(group.path) } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(Theme.Typography.ui(.caption))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: Theme.Spacing.lg)
                    FileKindIcon(kind: FileKind.classify(
                        name: group.name, isFolder: false, isExpanded: false
                    ))
                    Text(group.name)
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !group.directory.isEmpty {
                        Text(group.directory)
                            .font(Theme.Typography.ui(.caption))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer(minLength: 0)
                    Badge(
                        text: "\(group.matches.count)",
                        size: .caption,
                        weight: .regular,
                        style: .neutral,
                        shape: .capsule
                    )
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Row.compact)
                .background(hovering ? Theme.bgElevated : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(group.path)
            .accessibilityLabel("\(group.path), \(group.matches.count) matches")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func matchRow(_ match: ExplorerContentMatch) -> some View {
        HoverReader { hovering in
            Button { shell.presentFile(match.path) } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("\(match.line)")
                        .font(Theme.Typography.mono(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: Theme.Spacing.xxl, alignment: .trailing)
                    Text(highlighted(match))
                        .font(Theme.Typography.mono(.body))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Theme.Spacing.lg)
                .padding(.trailing, Theme.Spacing.md)
                .frame(height: Theme.Row.compact)
                .background(hovering ? Theme.bgElevated : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(match.path):\(match.line)")
        }
    }

    /// Eşleşen alt dizgiyi vurgulayan satır metni; ön ek gerekirse soldan
    /// kırpılır (`ExplorerMatchPreview`), böylece vurgu dar panelde görünür kalır.
    private func highlighted(_ match: ExplorerContentMatch) -> AttributedString {
        let preview = ExplorerMatchPreview.make(text: match.text, query: trimmedQuery)
        var before = AttributedString(preview.before)
        before.foregroundColor = Theme.textSecondary
        var hit = AttributedString(preview.match)
        hit.foregroundColor = Theme.textPrimary
        hit.backgroundColor = Theme.warning.opacity(0.3)
        var after = AttributedString(preview.after)
        after.foregroundColor = Theme.textSecondary
        return before + hit + after
    }

    // MARK: - Davranış

    private func toggle(_ path: String) {
        // Immutable güncelleme: yeni küme yazılır, mevcut küme mutasyona uğramaz.
        collapsed = collapsed.contains(path)
            ? collapsed.subtracting([path])
            : collapsed.union([path])
    }

    private func runSearch() async {
        result = ExplorerContentResult()
        error = nil
        guard !trimmedQuery.isEmpty else { loading = false; return }
        loading = true
        do {
            try await Task.sleep(for: Theme.Motion.searchDebounce)
            let found = try await shell.repos.searchContents(trimmedQuery, in: repoPath)
            try Task.checkCancellation()
            result = found
            loading = false
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription; loading = false }
        }
    }
}
