import LumiKit
import LumiState
import SwiftUI

/// Focus mode hover-reveal kontrol çubuğu: mouse üst bölgeye gelince
/// 500ms gecikmeyle belirir; içerik: terminal sayısı, grid menüsü, yeni
/// terminal, çıkış.
struct FocusModeBar: View {
    static let revealDelay = Theme.Motion.hoverRevealDelay

    let repoPath: String

    @Shell private var shell

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
                    .frame(height: Theme.Spacing.xl)
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
        .animation(Theme.Motion.standardEase, value: isRevealed)
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
        HStack(spacing: Theme.Spacing.lg) {
            Text("\(shell.terminals.visibleTerminals(in: repoPath).count) terminal")
                .font(Theme.Typography.mono(.body))
                .foregroundStyle(Theme.textSecondary)

            gridLayoutMenu

            Button("New \(provider.displayName)") {
                shell.terminals.spawn(in: repoPath, command: provider.launchCommand)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accentVivid)

            Spacer()

            Button("Exit Focus Mode") {
                shell.layout.exitFocusMode()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.bgSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
        }
        .onHover { inside in
            if !inside {
                isRevealed = false
            }
        }
    }

    private var provider: AgentProvider { shell.settings.current.aiProvider }

    private var gridLayoutMenu: some View {
        GridSettingsControl(
            layout: shell.layout.gridLayout(for: repoPath),
            onChange: { shell.layout.setGridLayout($0, for: repoPath) }
        )
    }
}

#if DEBUG
#Preview("FocusModeBar") {
    FocusModeBar(repoPath: "/Users/preview/Projects/lumi")
        .frame(width: 720, height: 120)
        .background(Theme.bgDeep)
        .environment(\.shell, ShellContext.preview())
}
#endif
