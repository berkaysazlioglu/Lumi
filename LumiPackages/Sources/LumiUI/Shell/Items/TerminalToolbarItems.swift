import LumiKit
import SwiftUI

/// Üretim bölgesi öğeleri (terminal feature'ının katkısı, Faz 6.4).
///
/// İkisi de yalnız **aktif repo route'unda** görünür — descriptor'ların
/// `isVisible` kapısı `TerminalFeatureAssembly`'de yazılıdır; repo-dışı bir
/// route (`.content`) veya hiç tab yokken (`.none`) `activeRepoPath` nil olduğu
/// için bar'dan düşerler (eski `if let active = shell.activeRepoPath` bloğunun
/// yapısal karşılığı).
public struct GridSettingsToolbarItem: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            GridSettingsControl(
                layout: shell.layout.gridLayout(for: repoPath),
                onChange: { shell.layout.setGridLayout($0, for: repoPath) }
            )
        }
    }
}

/// Terminal kartlarını elle sıralama modu (karar 97): `Edit` ↔ `Done`.
/// Repo'da sıralanacak en az iki terminal yoksa (gizliler dahil) çizilmez;
/// mod açıkken her durumda görünür ki çıkış kapısı kaybolmasın.
public struct ArrangeTerminalsToolbarItem: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            let isArranging = shell.layout.isArranging(in: repoPath)
            if isArranging || shell.terminals.terminals(in: repoPath).count > 1 {
                Button { shell.toggleArrangingTerminals(in: repoPath) } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: isArranging ? "checkmark" : "square.grid.2x2")
                            .font(Theme.Typography.ui(.caption, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(isArranging ? "Done" : "Edit")
                            .font(Theme.Typography.mono(.label, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(height: TopBarMetrics.controlHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverButtonStyle(hoverBackground: Theme.bgElevated, cornerRadius: Theme.Radius.md))
                .foregroundStyle(isArranging ? Theme.accentPrimary : Theme.textSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(isArranging ? Theme.accentPrimary : Theme.border, lineWidth: Theme.Stroke.hairline)
                        .allowsHitTesting(false)
                )
                .help(isArranging ? "Finish arranging terminals (Esc)" : "Arrange terminals — drag a card onto another to swap")
                .accessibilityLabel(isArranging ? "Done arranging terminals" : "Arrange terminals")
            }
        }
    }
}

/// Birincil CTA (New <Provider>).
///
/// Karar 55: üretim ↔ durum ayracı (dikey çizgi + payı) kaldırıldı — bar üç
/// parçaya bölündüğünden grubun sonunu artık bölge sınırı işaret ediyor,
/// butonun sağındaki çizgi ve boşluk gereksizdi.
public struct NewTerminalToolbarItem: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            NewTerminalButton(
                provider: shell.settings.current.aiProvider,
                onNewProvider: {
                    shell.terminals.spawn(
                        in: repoPath,
                        command: shell.settings.current.aiProvider.launchCommand
                    )
                },
                items: NewTerminalMenu.items(shell: shell, repoPath: repoPath)
            )
        }
    }
}
