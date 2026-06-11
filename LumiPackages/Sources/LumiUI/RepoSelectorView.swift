import LumiKit
import LumiState
import SwiftUI

/// Kaynak bazlı gruplu repo seçici (spec/21 §15 gruplama kuralları).
struct RepoSelectorView: View {
    let groups: [RepoStore.RepoGroup]
    let onSelect: (Repo) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if groups.isEmpty {
                    Text("Repo bulunamadı — Projects Root ayarlayın")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .padding(8)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.label)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                        if group.repos.isEmpty {
                            Text("(boş)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                                .padding(.horizontal, 12)
                        }
                        ForEach(group.repos) { repo in
                            Button {
                                onSelect(repo)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: repo.isGitRepo ? "folder.badge.gearshape" : "folder")
                                        .font(.system(size: 11))
                                        .foregroundStyle(repo.isGitRepo ? Theme.accentPrimary : Theme.textMuted)
                                    Text(repo.name)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 280, height: 360)
        .background(Theme.bgElevated)
    }
}
