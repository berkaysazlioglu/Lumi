import LumiKit
import LumiState
import SwiftUI

/// Orchestrator popup'ı (karar 114/123): pencerenin %80'ini kaplayan modal.
/// Solda kullanıcının doğrudan konuştuğu etkileşimli Codex terminali, sağda
/// izlenen terminaller ve onlardan gelen haiku özetleri (Activity).
///
/// Kapatmak (dışarı tık, ✕, ⌘J) yalnız GİZLER — Codex ve konuşma yaşar.
/// Escape terminaldeyken Codex'e gider (turn'ü keser), popup'ı kapatmaz.
/// Karar 124: docked panelin "popup olarak aç" butonuyla açılır; başlıktaki
/// dock butonu panele geri yerleştirir.
public struct OrchestratorOverlay: View {
    @Shell private var shell

    public init() {}

    /// Popup'ın pencereye oranı (her iki eksende).
    private static var windowRatio: CGFloat { 0.8 }
    private static var activityWidth: CGFloat { Theme.scaled(320) }

    private var store: OrchestratorStore { shell.orchestrator }

    public var body: some View {
        GeometryReader { proxy in
            ModalOverlay(onDismiss: dismiss) {
                Panel(variant: .modal) {
                    VStack(spacing: 0) {
                        OrchestratorHeader(
                            store: store,
                            layoutButton: .init(
                                systemName: "sidebar.right",
                                label: "Dock to panel",
                                action: { shell.orchestratorPresentation.dock() }
                            ),
                            onClose: dismiss
                        )
                        divider
                        HStack(spacing: 0) {
                            OrchestratorConsole(store: store)
                            Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                            OrchestratorMonitorView(beforeFocus: dismiss)
                                .frame(width: Self.activityWidth)
                        }
                    }
                }
                .frame(
                    width: proxy.size.width * Self.windowRatio,
                    height: proxy.size.height * Self.windowRatio
                )
            }
        }
        .task { await store.activate() }
        .onAppear {
            store.setPresented(.popup, true)
            store.focusTerminal()
        }
        .onDisappear { store.setPresented(.popup, false) }
        .onChange(of: store.terminalID) { store.focusTerminal() }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }

    private func dismiss() {
        shell.orchestratorPresentation.closePopup()
    }
}

/// Başlık: ad + Codex durumu, yeniden başlatma, yeni konuşma, sunum
/// değiştirme (popup ⇄ panel, karar 124) ve kapatma.
struct OrchestratorHeader: View {
    /// Diğer sunuma geçiren buton.
    struct LayoutButton {
        let systemName: String
        let label: String
        let action: () -> Void
    }

    let store: OrchestratorStore
    let layoutButton: LayoutButton
    /// Docked panel dar: daha az iç boşluk.
    var isCompact = false
    let onClose: () -> Void

    private static var buttonSide: CGFloat { Theme.scaled(28) }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: OrchestratorToolbarItem.iconName)
                .font(Theme.Typography.ui(.title, weight: .semibold))
                .foregroundStyle(Theme.accentPrimary)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Orchestrator")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                    Text(statusText)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            IconButton(
                systemName: "arrow.clockwise", label: "Restart Codex (same conversation)",
                size: .body, weight: .regular, side: Self.buttonSide, cornerRadius: Theme.Radius.md
            ) {
                Task { await store.restart() }
            }
            .disabled(!canRelaunch)
            IconButton(
                systemName: "square.and.pencil", label: "New conversation",
                size: .body, weight: .regular, side: Self.buttonSide, cornerRadius: Theme.Radius.md
            ) {
                Task { await store.newConversation() }
            }
            .disabled(!canRelaunch)
            IconButton(
                systemName: layoutButton.systemName, label: layoutButton.label,
                size: .body, weight: .regular, side: Self.buttonSide, cornerRadius: Theme.Radius.md,
                action: layoutButton.action
            )
            IconButton(
                systemName: "xmark", label: "Close orchestrator (⌘J)",
                side: Self.buttonSide, cornerRadius: Theme.Radius.md, action: onClose
            )
        }
        .padding(.horizontal, isCompact ? Theme.Spacing.lg : Theme.Spacing.xxl)
        .padding(.vertical, isCompact ? Theme.Spacing.md : Theme.Spacing.lg)
    }

    private var canRelaunch: Bool {
        store.phase == .running || store.phase == .stopped
    }

    private var statusText: String {
        switch store.phase {
        case .idle, .starting: return "Starting Codex…"
        case .running: return store.isResponding ? "Working…" : "Ready — Codex with Lumi's tools only"
        case .codexMissing: return "Codex is not installed"
        case .installing: return "Installing Codex…"
        case .stopped: return "Stopped"
        }
    }

    private var statusColor: Color {
        switch store.phase {
        case .idle, .starting, .installing: return Theme.warning
        case .running: return store.isResponding ? Theme.accentCyan : Theme.success
        case .codexMissing, .stopped: return Theme.textMuted
        }
    }
}

/// Sol bölme: faza göre canlı terminal ya da durum paneli.
struct OrchestratorConsole: View {
    let store: OrchestratorStore

    var body: some View {
        Group {
            switch store.phase {
            case .running, .installing:
                if let terminalID = store.terminalID {
                    terminal(terminalID)
                } else {
                    OrchestratorStartingView()
                }
            case .idle, .starting:
                OrchestratorStartingView()
            case .codexMissing:
                OrchestratorInstallPanel(store: store)
            case .stopped:
                OrchestratorStoppedPanel(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDeep)
    }

    private func terminal(_ id: TerminalID) -> some View {
        TerminalHostView(terminalID: id, provider: store.viewProvider)
            .id(id)
            .padding(Theme.Spacing.md)
    }
}

struct OrchestratorStartingView: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Starting Codex…")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
        }
    }
}

/// Codex bulunamadı: tek tıkla kurulum ya da komutu kopyalayıp elle kurma.
struct OrchestratorInstallPanel: View {
    let store: OrchestratorStore
    @State private var didCopy = false

    private static var maxWidth: CGFloat { Theme.scaled(560) }
    private static let copiedResetDelay: Duration = .seconds(2)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Codex is not installed")
                .font(Theme.Typography.mono(.title, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("The orchestrator runs on OpenAI's Codex CLI. Install it here — the installer runs in this "
                + "window and the orchestrator starts when it finishes — or copy the command and run it yourself.")
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.sm) {
                Text(OrchestratorStore.installCommand)
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                IconButton(
                    systemName: didCopy ? "checkmark" : "doc.on.doc",
                    label: didCopy ? "Copied" : "Copy install command",
                    size: .body, action: copy
                )
            }
            .padding(Theme.Spacing.md)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
            )
            if let error = store.errorMessage {
                OrchestratorErrorRow(text: error)
            }
            HStack(spacing: Theme.Spacing.md) {
                LumiActionButton(title: "Install Codex", kind: .primary) { store.installCodex() }
                LumiActionButton(title: "I installed it — retry") {
                    Task { await store.restart() }
                }
            }
        }
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .padding(Theme.Spacing.xxl)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(OrchestratorStore.installCommand, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: Self.copiedResetDelay)
            didCopy = false
        }
    }
}

/// Codex çıktı ya da açılamadı.
struct OrchestratorStoppedPanel: View {
    let store: OrchestratorStore

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Codex is not running")
                .font(Theme.Typography.mono(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let error = store.errorMessage {
                OrchestratorErrorRow(text: error)
            }
            HStack(spacing: Theme.Spacing.md) {
                LumiActionButton(title: "Restart", kind: .primary) {
                    Task { await store.restart() }
                }
                LumiActionButton(title: "New conversation") {
                    Task { await store.newConversation() }
                }
            }
        }
        .padding(Theme.Spacing.xxl)
    }
}

struct OrchestratorErrorRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(Theme.Typography.labelMono)
            .foregroundStyle(Theme.error)
            .textSelection(.enabled)
    }
}

#if DEBUG
#Preview("Orchestrator") {
    OrchestratorOverlay()
        .frame(width: 1100, height: 760)
        .environment(\.shell, ShellContext.preview())
}
#endif
