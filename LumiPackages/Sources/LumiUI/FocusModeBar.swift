import LumiKit
import LumiState
import SwiftUI

/// Focus mode hover-reveal kontrol çubuğu (spec/22): mouse üst bölgeye gelince
/// 500ms gecikmeyle belirir; içerik: terminal sayısı, grid menüsü, yeni
/// terminal, çıkış.
struct FocusModeBar: View {
    static let revealDelay: Duration = .milliseconds(500)

    let workspace: WorkspaceStore
    let terminals: TerminalListStore
    let repoPath: String
    let provider: AgentProvider

    @State private var isRevealed = false
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if isRevealed {
                bar
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Görünmez hover bölgesi — üstten yaklaşınca gecikmeli reveal
                Color.clear
                    .frame(height: 16)
                    .contentShape(Rectangle())
                    .onHover { entering in
                        if entering {
                            scheduleReveal()
                        } else {
                            revealTask?.cancel()
                        }
                    }
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: isRevealed)
    }

    private func scheduleReveal() {
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled else { return }
            isRevealed = true
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            Text("\(terminals.visibleTerminals(in: repoPath).count) terminal")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            gridLayoutMenu

            Button("New \(provider.displayName)") {
                terminals.spawn(in: repoPath, command: provider.launchCommand)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accentVivid)

            Spacer()

            Button("Exit Focus Mode") {
                workspace.exitFocusMode()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.bgSurface.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .onHover { inside in
            if !inside {
                isRevealed = false
            }
        }
    }

    private var gridLayoutMenu: some View {
        GridLayoutMenu(
            current: workspace.gridLayout(for: repoPath),
            onSelect: { workspace.setGridLayout($0, for: repoPath) }
        )
    }
}
