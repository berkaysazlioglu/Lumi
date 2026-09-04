import LumiKit
import LumiState
import SwiftUI

/// Üst header çubuğu (ince yerleşim karar 30 — Orca paritesi). 36px,
/// traffic light'lar doğal macOS konumunda. Yalnız kompozisyon — parçalar kendi dosyalarında:
/// `RepoTabStrip` (tab'ler + reorder + (+)), `NewTerminalButton` (birincil
/// CTA + dropdown), `HeaderControls` (ikon butonları), `GridSettingsControl`,
/// `UsageIndicatorView`, `WindowDragArea` (boş alan = pencere sürükleme).
/// Sol grup: hamburger → logo → tab şeridi (kalan genişlik). Üretim bölgesi:
/// grid ayarı + New <Provider>, ardından ayraç. Sağ grup: usage + fullscreen ·
/// git · settings. Topbar ölçüleri LumiApp (titlebar büyütme) ile paylaşılır.
public enum TopBarMetrics {
    public static let height: CGFloat = 36
    /// Traffic light ilk butonunun sol kenarı (Orca `TRAFFIC_LIGHT_X`).
    public static let trafficLightLeading: CGFloat = 16
    /// İçeriğin başladığı x: 3 buton (16 + 2×20 + 12 = 68) + nefes payı.
    public static let contentLeading: CGFloat = 80
    /// Bar içi kontrol yüksekliği (ikon buton, chip, usage, grid).
    public static let controlHeight: CGFloat = 26
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

    var body: some View {
        HStack(spacing: 0) {
            // Sol grup: hamburger → logo → tab'ler + (+)
            HStack(spacing: 8) {
                HeaderIconButton(
                    icon: "line.3.horizontal",
                    isActive: workspace.leftSidebarOpen,
                    action: { workspace.toggleLeftSidebar() }
                )
                logoView
                tabStrip
            }
            Spacer(minLength: 8)
            // Üretim bölgesi: grid ayarı + birincil CTA (New <Provider>).
            // Birincil eylem en sağda — göz yapılacak eylemde durur.
            if let active = workspace.activeTab {
                HStack(spacing: 6) {
                    gridLayoutMenu(for: active)
                    NewTerminalButton(
                        provider: settings.current.aiProvider,
                        onNewProvider: {
                            terminals.spawn(in: active, command: settings.current.aiProvider.launchCommand)
                        },
                        onNewBash: { terminals.spawn(in: active, task: "Bash") }
                    )
                }
                .padding(.trailing, 10)
                // Üretim ↔ durum/global ayracı (Gestalt ayrımı)
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1, height: 16)
                    .padding(.trailing, 10)
            }
            // Durum + global grup: ambient kullanım göstergesi + kalıcı panel/global
            // toggle'lar (sağdan sola: settings, git, fullscreen).
            HStack(spacing: 4) {
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
        // Sol: traffic light alanı — içerik butonların sağından başlar
        .padding(.leading, TopBarMetrics.contentLeading)
        .padding(.trailing, 10)
        .frame(height: Self.height)
        // Renk hit-test'i kapalı: boş alanlardaki tıklamalar arkadaki
        // WindowDragArea'ya geçsin (pencere sürükleme + çift-tık zoom).
        .background(Theme.bgSurface.allowsHitTesting(false))
        .background(WindowDragArea())
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
    }

    // MARK: - Logo + ad (ince bar: 18×18 mascot + ad 12/600)

    private var logoView: some View {
        HStack(spacing: 6) {
            if let logo = LumiAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            }
            Text(Self.appName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Tab'ler (RepoTabStrip: scroll + reorder + (+))

    private var tabStrip: some View {
        RepoTabStrip(workspace: workspace, repoStore: repoStore)
    }

    private func gridLayoutMenu(for repoPath: String) -> some View {
        GridSettingsControl(
            layout: workspace.gridLayout(for: repoPath),
            onChange: { workspace.setGridLayout($0, for: repoPath) }
        )
    }
}
