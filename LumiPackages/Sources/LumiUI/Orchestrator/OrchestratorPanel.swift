import LumiKit
import LumiState
import SwiftUI

/// Orchestrator'ın docked paneli (karar 124): orta alan ile sağ panelin
/// arasındaki `.innerRight` yuvasında, kapanınca yalnız gizlenen Codex
/// terminali; altında daraltılabilir Monitor bölmesi (izlenen terminaller +
/// Activity). Başlıktaki buton aynı terminali %80'lik popup'a taşır; popup
/// açıkken terminal ve Monitor oradadır, panel yalnız bunu söyler.
public struct OrchestratorPanel: View {
    @Shell private var shell

    public init() {}

    private var store: OrchestratorStore { shell.orchestrator }
    private var presentation: OrchestratorPresentation { shell.orchestratorPresentation }

    public var body: some View {
        VStack(spacing: 0) {
            OrchestratorHeader(
                store: store,
                layoutButton: .init(
                    systemName: "arrow.up.forward.app",
                    label: "Open as popup",
                    action: { presentation.openPopup() }
                ),
                isCompact: true,
                onClose: { presentation.closePanel() }
            )
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            if presentation.isPopupOpen {
                OrchestratorPoppedOutView(onShowHere: { presentation.closePopup() })
            } else {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        OrchestratorConsole(store: store)
                            // Terminal bu yüzeyde çizildiği sürece önde kalır.
                            .onAppear { store.setPresented(.panel, true) }
                            .onDisappear { store.setPresented(.panel, false) }
                        OrchestratorMonitorSection(availableHeight: proxy.size.height)
                    }
                }
            }
        }
        .task { await store.activate() }
    }
}

/// Popup açıkken panelin gövdesi.
struct OrchestratorPoppedOutView: View {
    let onShowHere: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Orchestrator is open in a popup")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
            LumiActionButton(title: "Show here", action: onShowHere)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDeep)
    }
}

#if DEBUG
#Preview("Orchestrator panel") {
    OrchestratorPanel()
        .frame(width: 460, height: 700)
        .environment(\.shell, ShellContext.preview())
}
#endif
