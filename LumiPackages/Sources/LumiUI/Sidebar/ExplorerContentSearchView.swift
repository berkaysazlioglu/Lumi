import LumiKit
import LumiState
import SwiftUI

struct ExplorerContentSearchView: View {
    let repoPath: String
    @Shell private var shell
    @State private var query = ""
    @State private var result = ExplorerContentResult()
    @State private var loading = false
    @State private var error: String?

    private struct Request: Equatable {
        let path: String
        let query: String
        let options: ExplorerOptions
        let revision: Int
    }

    private var request: Request {
        Request(path: repoPath, query: query,
                options: shell.repos.explorerOptions[repoPath] ?? ExplorerOptions(),
                revision: shell.repos.fileTreeRevisions[repoPath] ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search file contents…", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .font(Theme.Typography.ui(.body))
                .padding(Theme.Spacing.md)
                .background(Theme.bgDeep)
                .onKeyPress(.escape) { query = ""; return .handled }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if loading { ProgressView().controlSize(.small).padding(Theme.Spacing.md) }
                    if let error {
                        Text(error).foregroundStyle(Theme.error).font(Theme.Typography.ui(.body))
                    }
                    if result.isLimited {
                        Text("Search limit reached. Narrow your query.")
                            .font(Theme.Typography.ui(.caption)).foregroundStyle(Theme.warning)
                            .padding(Theme.Spacing.md)
                    }
                    if result.matches.isEmpty && !loading {
                        EmptyStatePlaceholder(query.isEmpty ? "Search across project files" : "No matches", density: .inline)
                    }
                    ForEach(result.matches) { match in
                        Button { shell.presentFile(match.path) } label: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("\(match.path):\(match.line)")
                                    .font(Theme.Typography.ui(.caption)).foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1).truncationMode(.head)
                                Text(match.text).font(Theme.Typography.mono(.body))
                                    .foregroundStyle(Theme.textPrimary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: request) {
            result = ExplorerContentResult()
            error = nil
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { loading = false; return }
            loading = true
            do {
                try await Task.sleep(for: Theme.Motion.searchDebounce)
                let found = try await shell.repos.searchContents(needle, in: repoPath)
                try Task.checkCancellation()
                result = found
                loading = false
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription; loading = false }
            }
        }
        .onChange(of: repoPath) { query = "" }
    }
}
