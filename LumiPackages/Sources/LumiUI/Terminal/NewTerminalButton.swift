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
    /// Seçilebilir satırlarda (konum bölümü — karar 108) sağda tik.
    let isSelected: Bool
    let action: () -> Void

    var id: String { label }

    init(label: String, glyph: Glyph, isSelected: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.glyph = glyph
        self.isSelected = isSelected
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
    /// Karar 108: All Terminals'ta terminalin açılacağı konum (`~`); repo'da nil.
    var locationLabel: String?
    let onNewProvider: () -> Void
    let items: [NewTerminalMenuItem]
    /// Karar 108: dropdown'un "Open in" bölümü; boşsa bölüm çizilmez.
    var locationItems: [NewTerminalMenuItem] = []

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
                    if let locationLabel {
                        Text(locationLabel)
                            .font(Theme.Typography.mono(.label))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: Theme.scaled(140), alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .foregroundStyle(.white)
                // 10/7pt: ölçek dışı ara değerler (v1 paritesi korunuyor).
                .padding(.leading, Theme.scaled(10))
                .padding(.trailing, Theme.scaled(7))
                .frame(height: TopBarMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(locationLabel.map { "New \(provider.displayName) terminal in \($0)" } ?? "")
            .accessibilityLabel(
                locationLabel.map { "New \(provider.displayName) terminal in \($0)" }
                    ?? "New \(provider.displayName) terminal"
            )

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
                dropdownRow(item)
            }
            if !locationItems.isEmpty {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: Theme.Stroke.hairline)
                    .padding(.vertical, Theme.Spacing.xs)
                    .accessibilityHidden(true)
                Text("Open in")
                    .font(Theme.Typography.mono(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, Theme.scaled(10))
                    .padding(.vertical, Theme.Spacing.xxs)
                ForEach(locationItems) { item in
                    dropdownRow(item)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Theme.scaled(locationItems.isEmpty ? 220 : 260))
        .background(Theme.bgElevated)
    }
}

extension NewTerminalButton {
    fileprivate func dropdownRow(_ item: NewTerminalMenuItem) -> some View {
        NewTerminalDropdownItem(glyph: item.glyph, label: item.label, isSelected: item.isSelected) {
            isOpen = false
            item.action()
        }
    }
}

/// Kapsama bağlı split-button (karar 108): top bar ve boş durum aynı butonu
/// buradan kurar — spawn `ShellContext.spawnTerminal(in:)`'e gider, All
/// Terminals'ta konum etiketi ve "Open in" bölümü eklenir.
struct ScopedNewTerminalButton: View {
    let scope: TerminalScope

    @Shell private var shell

    var body: some View {
        let provider = shell.settings.current.aiProvider
        NewTerminalButton(
            provider: provider,
            locationLabel: NewTerminalMenu.locationLabel(shell: shell, scope: scope),
            onNewProvider: { shell.spawnTerminal(in: scope, command: provider.launchCommand) },
            items: NewTerminalMenu.items(shell: shell, scope: scope),
            locationItems: NewTerminalMenu.locationItems(shell: shell, scope: scope)
        )
    }
}

/// Dropdown satırı — hover'da highlight (v1 dark dropdown paritesi).
private struct NewTerminalDropdownItem: View {
    let glyph: NewTerminalMenuItem.Glyph
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                icon
                    .frame(width: Theme.Spacing.xl)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Theme.Typography.mono(.body))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.ui(.caption, weight: .semibold))
                        .foregroundStyle(Theme.accentPrimary)
                        .accessibilityHidden(true)
                }
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
