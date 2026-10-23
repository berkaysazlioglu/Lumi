import LumiKit
import LumiState
import SwiftUI

/// İzlenen terminaller + Activity (karar 114 Faz 4) — popup'ın sağ sütunu ve
/// docked panelin Monitor bölmesi (karar 124) aynı görünümdür. Görünür olduğu
/// sürece gelen olaylar görülmüş sayılır (top bar noktası söner).
struct OrchestratorMonitorView: View {
    /// Terminal öne getirilmeden hemen önce — popup kendini kapatır ki
    /// terminal görülsün; panel yerinde kalır.
    var beforeFocus: () -> Void = {}

    @Shell private var shell

    private var store: OrchestratorStore { shell.orchestrator }

    var body: some View {
        OrchestratorActivityPanel(
            feed: store.activity,
            watched: Self.watchedTerminals(in: shell),
            onFocus: focus,
            onUnwatch: { store.watchList.unwatch($0) },
            isOpen: { shell.terminals.meta(for: $0) != nil },
            onOpen: open,
            onReply: reply
        )
        .onAppear { store.activity.markAllRead() }
        .onChange(of: store.activity.unreadCount) { _, count in
            if count > 0 { store.activity.markAllRead() }
        }
    }

    /// İzlenen canlı terminaller, terminal listesinin sırasıyla.
    @MainActor
    static func watchedTerminals(in shell: ShellContext) -> [TerminalMeta] {
        shell.terminals.terminals.filter { shell.orchestrator.watchList.isWatched($0) }
    }

    private func open(_ event: OrchestratorEvent) {
        guard let meta = shell.terminals.meta(for: event.terminalID) else { return }
        focus(meta)
    }

    private func focus(_ meta: TerminalMeta) {
        beforeFocus()
        shell.focusAgent(meta)
    }

    /// Codex'in composer'ına yanıt başlangıcı yazar (göndermez) ve odağı verir.
    private func reply(_ event: OrchestratorEvent) {
        store.typeIntoComposer("Reply to “\(event.terminalTitle)”: ")
    }
}

/// Docked panelin alt kısmı (karar 124): tıklanınca açılıp kapanan başlık ve
/// açıkken panel yüksekliğinin bir payı kadar Monitor. Durum `LayoutStore`'da
/// (`ui-state` → `orchestratorActivityCollapsed`).
struct OrchestratorMonitorSection: View {
    /// Açıkken panel gövdesinin ne kadarını kaplar.
    static let heightRatio: CGFloat = 0.42

    let availableHeight: CGFloat

    @Shell private var shell

    private var isExpanded: Bool { shell.layout.isOrchestratorActivityExpanded }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            header
            if isExpanded {
                Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                OrchestratorMonitorView()
                    .frame(height: availableHeight * Self.heightRatio)
            }
        }
    }

    private var header: some View {
        HoverReader { isHovering in
            Button { shell.layout.toggleOrchestratorActivity() } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(Theme.Typography.ui(.caption, weight: .semibold))
                    Text("MONITOR")
                        .font(Theme.Typography.ui(.caption, weight: .semibold))
                    Text(summary)
                        .font(Theme.Typography.captionMono)
                    Spacer(minLength: Theme.Spacing.xs)
                    if !isExpanded, unreadCount > 0 {
                        Text("\(unreadCount) new")
                            .font(Theme.Typography.captionMono)
                            .foregroundStyle(Theme.accentPrimary)
                    }
                }
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textMuted)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide watched terminals and activity" : "Show watched terminals and activity")
        }
    }

    private var unreadCount: Int { shell.orchestrator.activity.unreadCount }

    private var summary: String {
        let watching = OrchestratorMonitorView.watchedTerminals(in: shell).count
        return "· \(watching) watching"
    }
}
