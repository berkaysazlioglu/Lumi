import LumiKit
import LumiState
import SwiftUI

/// Dropdown'daki tek seçenek (karar 54): ikon + etiket + eylem. Liste
/// çağırandan gelir — buton hangi ajanların kurulu olduğunu bilmez.
struct NewTerminalMenuItem: Identifiable {
    /// Satır ikonu: sağlayıcı marka glyph'i ya da SF Symbol.
    enum Glyph {
        case provider(AgentProvider)
        case symbol(String)
    }

    let label: String
    let glyph: Glyph
    let action: () -> Void

    var id: String { label }

    init(label: String, glyph: Glyph, action: @escaping () -> Void) {
        self.label = label
        self.glyph = glyph
        self.action = action
    }
}

/// Modern "New <Provider>" split-button (v1 paritesi): solid mor; sol kısım
/// aktif provider'ı spawn eder, sağ chevron özel koyu dropdown'u **tıklamayla**
/// açar/kapar (diğer ajanlar + New Bash). Popover transient'tır: bir eyleme
/// ya da dışarı tıklayınca kapanır. Fare popover'dan çıkarsa
/// `Theme.Motion.menuLeaveCloseDelay` sonra kapanır; bu sürede geri dönmek
/// kapanışı iptal eder. Native NSMenu DEĞİL — temalı popover.
struct NewTerminalButton: View {
    static let leaveCloseDelay = Theme.Motion.menuLeaveCloseDelay

    let provider: AgentProvider
    let onNewProvider: () -> Void
    let items: [NewTerminalMenuItem]

    @State private var isOpen = false
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
                .padding(.leading, Theme.scaled(10))
                .padding(.trailing, Theme.scaled(7))
                .frame(height: TopBarMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New \(provider.displayName) terminal")

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: Theme.Stroke.hairline, height: Theme.scaled(14))
                .accessibilityHidden(true)

            Button(action: toggle) {
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.ui(.micro, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.scaled(7))
                    .frame(height: TopBarMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("More agents")
            .accessibilityLabel("More agents")
        }
        .background(Theme.accentVivid)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            dropdown.onHover { updateHover($0) }
        }
        .onChange(of: isOpen) { _, open in
            if !open { cancelClose() }
        }
    }

    private func toggle() {
        cancelClose()
        isOpen.toggle()
    }

    /// Popover hover'ı: girişte bekleyen kapanış iptal edilir, çıkışta
    /// gecikmeli kapanış kurulur (kısa süreli taşma menüyü kapatmaz).
    private func updateHover(_ hovering: Bool) {
        cancelClose()
        guard !hovering else { return }
        closeTask = Task { @MainActor in
            try? await Task.sleep(for: Self.leaveCloseDelay)
            guard !Task.isCancelled else { return }
            isOpen = false
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            ForEach(items) { item in
                NewTerminalDropdownItem(glyph: item.glyph, label: item.label) {
                    isOpen = false
                    item.action()
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Theme.scaled(220))
        .background(Theme.bgElevated)
    }
}

/// Dropdown satırı — hover'da highlight (v1 dark dropdown paritesi).
private struct NewTerminalDropdownItem: View {
    let glyph: NewTerminalMenuItem.Glyph
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                icon
                    .frame(width: Theme.Spacing.xl)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Theme.Typography.mono(.body))
                Spacer(minLength: 0)
            }
            // 10/7pt: ölçek dışı ara değerler (v1 paritesi korunuyor).
            .padding(.horizontal, Theme.scaled(10))
            .padding(.vertical, Theme.scaled(7))
        }
        .buttonStyle(
            HoverButtonStyle(
                hoverBackground: Theme.bgSurface,
                cornerRadius: Theme.Radius.sm
            )
        )
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var icon: some View {
        switch glyph {
        case .provider(let provider):
            ProviderIcon(provider: provider, size: .body)
        case .symbol(let name):
            Image(systemName: name)
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textMuted)
        }
    }
}

#if DEBUG
#Preview("NewTerminalButton") {
    NewTerminalButton(
        provider: .claude,
        onNewProvider: {},
        items: [
            NewTerminalMenuItem(label: "New Codex", glyph: .provider(.codex), action: {}),
            NewTerminalMenuItem(label: "New DeepSeek", glyph: .symbol("sparkles"), action: {}),
            NewTerminalMenuItem(label: "New Bash", glyph: .symbol("terminal"), action: {}),
        ]
    )
        .padding(Theme.Spacing.xxl)
        .background(Theme.bgSurface)
}
#endif
