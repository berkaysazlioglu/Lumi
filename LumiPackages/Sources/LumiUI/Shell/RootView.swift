import LumiKit
import LumiState
import SwiftUI

/// Pencerenin kök view'ı (Faz 6.1).
///
/// Tek parametresi kayıt defteridir; **tüm store'lar, köprüler ve aksiyonlar
/// `@Environment(\.shell)`'den gelir** — eski 15 parametreli prop-drilling
/// (RootView → HeaderBar → RepoTabStrip, `usageStores`'un iki yoldan taşınması)
/// tamamen kalktı. Kurulum `RootViewFactory`'dedir:
///
/// ```swift
/// NSHostingView(rootView: RootView(registries: registries).environment(\.shell, context))
/// ```
public struct RootView: View {
    private let registries: ShellRegistries

    public init(registries: ShellRegistries) {
        self.registries = registries
    }

    @Shell private var shell

    public var body: some View {
        Group {
            if shell.dialogs.isOnboardingActive {
                OnboardingView(store: shell.onboarding)
            } else {
                AppShellView(registries: registries)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Kabuğun iskeleti: header + (sol panel · route · sağ panel) + overlay host.
///
/// Hiçbir özel görünüm adı geçmez — panel öğeleri, orta alan ve overlay'ler
/// registry'den gelir (Faz 6.2/6.3/6.5).
struct AppShellView: View {
    let registries: ShellRegistries

    @Shell private var shell

    var body: some View {
        VStack(spacing: 0) {
            // Focus mode: header gizlenir, hover-reveal bar (overlay) devralır
            if !shell.layout.isFocusMode {
                HeaderBarView(registry: registries.toolbar)
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }
            HStack(spacing: 0) {
                PanelHostView(slot: .left, registry: registries.panels)
                ContentRouterView(registry: registries.routes)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PanelHostView(slot: .right, registry: registries.panels)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bgDeep)
        .overlay {
            OverlayHost(registry: registries.overlays)
        }
    }
}

/// Hiç repo tab'ı açık değilken orta alan (route `.none`).
public struct WelcomeView: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("Lumi")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accentPrimary)
            Text("Open a repo and start a terminal")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            Button("Open Repo") {
                shell.dialogs.isRepoSelectorOpen = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
