import LumiKit
import LumiState
import SwiftUI

/// Sol üst bölümde All Terminals'ın altındaki view listesi (karar 135).
///
/// Boş view olmadığı için `+` yoktur: view, bir terminalin sağ tık menüsündeki
/// `Add to View ▸ New View` ile doğar. Satır sağ tıkı yeniden adlandırma
/// (satır içinde) ve silme (terminaller kapanmaz) sunar.
struct CustomViewsSection: View {
    @Shell private var shell
    @State private var renaming: CustomViewID?

    var body: some View {
        ForEach(shell.terminals.customViews.views) { view in
            CustomViewRow(
                view: view,
                isRenaming: Binding(
                    get: { renaming == view.id },
                    set: { renaming = $0 ? view.id : nil }
                )
            )
        }
    }
}

private struct CustomViewRow: View {
    let view: CustomTerminalView
    @Binding var isRenaming: Bool

    @Shell private var shell
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    private var route: WorkspaceRoute { CustomViewRoute.route(view.id) }

    var body: some View {
        let members = shell.terminals.terminals(in: .custom(view.id))
        let isActive = shell.navigation.activeRoute == route
        let needsAttention = members.contains { meta in
            TerminalAttention.isNeeded(
                status: meta.status,
                isAwaitingDecision: shell.terminals.awaitingDecisionIDs.contains(meta.id),
                isSelected: shell.terminals.activeTerminalID == meta.id
            )
        }
        HoverReader { isHovering in
            Button { shell.navigation.setRoute(route) } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: CustomViewRoute.icon)
                        .font(Theme.Typography.ui(.body))
                        .accessibilityHidden(true)
                    if isRenaming {
                        nameField
                    } else {
                        Text(view.name)
                            .font(Theme.Typography.bodyMono)
                            .lineLimit(1)
                            .attentionPulse(needsAttention)
                    }
                    Spacer(minLength: 0)
                    Text("\(members.count)")
                        .font(Theme.Typography.mono(.label))
                        .foregroundStyle(Theme.textMuted)
                        .monospacedDigit()
                }
                .foregroundStyle(nameColor(isActive: isActive, isHovering: isHovering, needsAttention: needsAttention))
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(isActive || isHovering ? Theme.bgElevated : Color.clear)
                .overlay(alignment: .leading) {
                    if isActive {
                        Rectangle().fill(Theme.accentPrimary).frame(width: Theme.Spacing.xxs)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .newViewHighlight(shell.highlightedCustomView == view.id)
        .contextMenu {
            Button("Rename…") { beginRename() }
            Button("Delete View", role: .destructive) { shell.terminals.deleteCustomView(view.id) }
        }
        .accessibilityLabel(
            needsAttention
                ? "\(view.name), \(members.count) terminals, needs attention"
                : "\(view.name), \(members.count) terminals"
        )
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var nameField: some View {
        TextField("View name", text: $draft)
            .textFieldStyle(.plain)
            .font(Theme.Typography.bodyMono)
            .foregroundStyle(Theme.textPrimary)
            .focused($isFieldFocused)
            .onSubmit(commitRename)
            .onExitCommand { isRenaming = false }
            .onChange(of: isFieldFocused) { _, focused in
                // Alanın dışına tıklamak da kaydeder (Finder paritesi).
                if !focused, isRenaming { commitRename() }
            }
            .onAppear { isFieldFocused = true }
    }

    private func beginRename() {
        draft = view.name
        isRenaming = true
    }

    /// Geçersiz (boş) ad sessizce eski ada döner — store reddeder.
    private func commitRename() {
        shell.terminals.renameCustomView(view.id, to: draft)
        isRenaming = false
    }

    private func nameColor(isActive: Bool, isHovering: Bool, needsAttention: Bool) -> Color {
        if needsAttention { return Theme.warning }
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }
}

/// Karar 136: az önce doğan view satırının vurgusu — sarı çerçeve, etrafında
/// nefes alan hale ve doğduğu an kısa bir büyüyüp küçülme. "Reduce motion"
/// açıksa yalnız sabit çerçeve çizilir.
private struct NewViewHighlight: ViewModifier {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPopped = false

    /// Doğuş anındaki büyüme oranı.
    private static let popScale: CGFloat = 1.05

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPopped ? Self.popScale : 1)
            .overlay {
                if isOn {
                    if reduceMotion {
                        frame(glow: 1)
                    } else {
                        TimelineView(.animation(minimumInterval: AttentionPulse.frameInterval)) { timeline in
                            frame(glow: AttentionPulse.opacity(at: timeline.date.timeIntervalSinceReferenceDate * 2))
                        }
                    }
                }
            }
            .onChange(of: isOn, initial: true) { _, on in
                guard on, !reduceMotion else { return }
                withAnimation(.spring(duration: Theme.Motion.panel, bounce: 0.5)) { isPopped = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(Theme.Motion.panel))
                    withAnimation(.spring(duration: Theme.Motion.panel, bounce: 0.5)) { isPopped = false }
                }
            }
    }

    private func frame(glow: Double) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md)
            .strokeBorder(Theme.warning.opacity(glow), lineWidth: Theme.Stroke.graph)
            .shadow(color: Theme.warning.opacity(AttentionPulse.glowOpacity * glow), radius: AttentionPulse.glowRadius)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension View {
    func newViewHighlight(_ isOn: Bool) -> some View {
        modifier(NewViewHighlight(isOn: isOn))
    }
}
