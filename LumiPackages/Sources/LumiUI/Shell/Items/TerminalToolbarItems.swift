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

/// Birincil CTA (New <Provider>) + üretim ↔ durum ayracı.
///
/// Ayraç bu öğenin PARÇASIDIR: Gestalt ayrımı üretim grubunun sonunu işaret
/// eder, dolayısıyla grup bar'dan düştüğünde ayraç da düşer.
public struct NewTerminalToolbarItem: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            HStack(spacing: 0) {
                NewTerminalButton(
                    provider: shell.settings.current.aiProvider,
                    onNewProvider: {
                        shell.terminals.spawn(
                            in: repoPath,
                            command: shell.settings.current.aiProvider.launchCommand
                        )
                    },
                    onNewBash: { shell.terminals.spawn(in: repoPath, task: "Bash") }
                )
                .padding(.trailing, TopBarMetrics.trailingPadding)
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1, height: 16)
                    .padding(.trailing, TopBarMetrics.trailingPadding)
            }
        }
    }
}
