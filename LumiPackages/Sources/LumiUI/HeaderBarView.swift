import LumiKit
import LumiState
import SwiftUI

/// Üst header çubuğu (v1 paritesi, globals.css; spec/22). 52px, traffic
/// light hizasında. Yalnız kompozisyon — parçalar kendi dosyalarında:
/// `RepoTabStrip` (tab'ler + reorder + (+)), `NewTerminalButton` (birincil
/// CTA + dropdown), `HeaderControls` (ikon butonları), `GridSettingsControl`,
/// `UsageIndicatorView`, `WindowDragArea` (boş alan = pencere sürükleme).
/// Sol grup: hamburger → logo → tab şeridi (kalan genişlik). Üretim bölgesi:
/// grid ayarı + New <Provider>, ardından ayraç. Sağ grup: usage + fullscreen ·
/// git · settings. Topbar ölçüleri LumiApp (titlebar büyütme) ile paylaşılır.
public enum TopBarMetrics {
    public static let height: CGFloat = 52
}

struct HeaderBarView: View {
    static let height: CGFloat = TopBarMetrics.height

    /// Logo yanındaki ürün adı — dev (debug) build'de "dev", release'de "Lumi".
    static let appName: String = {
        #if DEBUG
        return "dev"
        #else
        return "Lumi"
        #endif
    }()

    let workspace: WorkspaceStore
    let repoStore: RepoStore
    let terminals: TerminalListStore
    let settings: SettingsStore
    let usage: UsageStore
    let tabInteraction: TabStripInteractionModel

    var body: some View {
        HStack(spacing: 0) {
            // Sol grup (v1 header-left, gap 12): hamburger → logo → tab'ler + (+)
            HStack(spacing: 12) {
                HeaderIconButton(
                    icon: "line.3.horizontal",
                    isActive: workspace.leftSidebarOpen,
                    action: { workspace.toggleLeftSidebar() }
                )
                logoView
                tabStrip
            }
            Spacer(minLength: 12)
            // Üretim bölgesi: grid ayarı + birincil CTA (New <Provider>).
            // Birincil eylem en sağda — göz yapılacak eylemde durur.
            if let active = workspace.activeTab {
                HStack(spacing: 8) {
                    gridLayoutMenu(for: active)
                    NewTerminalButton(
                        provider: settings.current.aiProvider,
                        onNewProvider: {
                            terminals.spawn(in: active, command: settings.current.aiProvider.launchCommand)
                        },
                        onNewBash: { terminals.spawn(in: active, task: "Bash") }
                    )
                }
                .padding(.trailing, 12)
                // Üretim ↔ durum/global ayracı (Gestalt ayrımı)
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1, height: 22)
                    .padding(.trailing, 12)
            }
            // Durum + global grup: ambient kullanım göstergesi + kalıcı panel/global
            // toggle'lar (sağdan sola: settings, git, fullscreen).
            HStack(spacing: 8) {
                UsageIndicatorView(store: usage)
                HeaderIconButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    isActive: workspace.isFocusMode,
                    action: { workspace.toggleFocusMode() }
                )
                HeaderIconButton(
                    icon: "arrow.triangle.branch",
                    isActive: workspace.rightSidebarOpen,
                    action: { workspace.toggleRightSidebar() }
                )
                HeaderIconButton(
                    icon: "gearshape",
                    isActive: workspace.isSettingsOpen,
                    action: { workspace.isSettingsOpen = true }
                )
            }
        }
        // Sol 80px: traffic light alanı — içerik trafiğin hizasında (v1 paritesi)
        .padding(.leading, 80)
        .padding(.trailing, 16)
        .frame(height: Self.height)
        // Renk hit-test'i kapalı: boş alanlardaki tıklamalar arkadaki
        // WindowDragArea'ya geçsin (pencere sürükleme + çift-tık zoom).
        .background(Theme.bgSurface.allowsHitTesting(false))
        .background(WindowDragArea())
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
    }

    // MARK: - Logo + ad (v1: 26×26 mascot + "Lumi" 14/600)

    private var logoView: some View {
        HStack(spacing: 8) {
            if let logo = LumiAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
            }
            Text(Self.appName)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Tab'ler (RepoTabStrip: scroll + reorder + (+))

    private var tabStrip: some View {
        RepoTabStrip(workspace: workspace, repoStore: repoStore, interaction: tabInteraction)
    }

    private func gridLayoutMenu(for repoPath: String) -> some View {
        GridSettingsControl(
            layout: workspace.gridLayout(for: repoPath),
            onChange: { workspace.setGridLayout($0, for: repoPath) }
        )
    }
}
