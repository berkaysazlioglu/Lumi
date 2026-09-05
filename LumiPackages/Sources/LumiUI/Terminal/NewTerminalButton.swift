import LumiKit
import LumiState
import SwiftUI

/// Modern "New <Provider>" split-button (v1 paritesi): solid mor; sol kısım
/// aktif provider'ı spawn eder, sağ chevron özel koyu dropdown'u **hover'da**
/// açar (New Bash). Buton VEYA popover üstünde hover olduğu sürece
/// açık kalır; ikisinden de ayrılınca kısa grace period sonra kapanır. Native
/// NSMenu DEĞİL — temalı popover.
struct NewTerminalButton: View {
    static let hoverOpenDelay = Theme.Motion.hoverOpenDelay
    static let hoverCloseDelay = Theme.Motion.hoverCloseDelay

    let provider: AgentProvider
    let onNewProvider: () -> Void
    let onNewBash: () -> Void

    @State private var isOpen = false
    @State private var openTask: Task<Void, Never>?
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onNewProvider) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "plus")
                        .font(Theme.Typography.ui(.label, weight: .bold))
                        .accessibilityHidden(true)
                    Text("New \(provider.displayName)")
                        .font(Theme.Typography.mono(.label, weight: .semibold))
                }
                .foregroundStyle(.white)
                // 10/7pt: ölçek dışı ara değerler (v1 paritesi korunuyor).
                .padding(.leading, 10)
                .padding(.trailing, 7)
                .frame(height: TopBarMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New \(provider.displayName) terminal")

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: Theme.Stroke.hairline, height: 14)
                .accessibilityHidden(true)

            // Chevron yalnız görsel ipucu — açma/kapama hover'la sürülür.
            Image(systemName: "chevron.down")
                .font(Theme.Typography.ui(.micro, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: TopBarMetrics.controlHeight)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .background(Theme.accentVivid)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onHover { updateHover($0) }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            dropdown.onHover { updateHover($0) }
        }
    }

    /// Buton ya da popover hover'ı: girişte kısa açılış gecikmesi (yanlışlıkla
    /// üstünden geçince açılmaz) + bekleyen kapanışı iptal et; çıkışta grace
    /// period zamanlayıcısı kur (arada geçişte flicker olmaz).
    private func updateHover(_ hovering: Bool) {
        if hovering {
            closeTask?.cancel()
            closeTask = nil
            guard !isOpen, openTask == nil else { return }
            openTask = Task { @MainActor in
                try? await Task.sleep(for: Self.hoverOpenDelay)
                guard !Task.isCancelled else { return }
                isOpen = true
                openTask = nil
            }
        } else {
            openTask?.cancel()
            openTask = nil
            closeTask?.cancel()
            closeTask = Task { @MainActor in
                try? await Task.sleep(for: Self.hoverCloseDelay)
                guard !Task.isCancelled else { return }
                isOpen = false
            }
        }
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            NewTerminalDropdownItem(icon: "terminal", label: "New Bash") {
                isOpen = false
                onNewBash()
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 220)
        .background(Theme.bgElevated)
    }
}

/// Dropdown satırı — hover'da highlight (v1 dark dropdown paritesi).
private struct NewTerminalDropdownItem: View {
    let icon: String?
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: Theme.Spacing.xl)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(Theme.Typography.mono(.body))
                Spacer(minLength: 0)
            }
            // 10/7pt: ölçek dışı ara değerler (v1 paritesi korunuyor).
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(
            HoverButtonStyle(
                hoverBackground: Theme.bgSurface,
                cornerRadius: Theme.Radius.sm
            )
        )
        .accessibilityLabel(label)
    }
}

#if DEBUG
#Preview("NewTerminalButton") {
    NewTerminalButton(provider: .claude, onNewProvider: {}, onNewBash: {})
        .padding(Theme.Spacing.xxl)
        .background(Theme.bgSurface)
}
#endif
