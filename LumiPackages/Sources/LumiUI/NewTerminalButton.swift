import LumiKit
import LumiState
import SwiftUI

/// Modern "New <Provider>" split-button (v1 paritesi): solid mor; sol kısım
/// aktif provider'ı spawn eder, sağ chevron özel koyu dropdown'u **hover'da**
/// açar (New Bash). Buton VEYA popover üstünde hover olduğu sürece
/// açık kalır; ikisinden de ayrılınca kısa grace period sonra kapanır. Native
/// NSMenu DEĞİL — temalı popover.
struct NewTerminalButton: View {
    static let hoverOpenDelay: Duration = .milliseconds(350)
    static let hoverCloseDelay: Duration = .milliseconds(200)

    let provider: AgentProvider
    let onNewProvider: () -> Void
    let onNewBash: () -> Void

    @State private var isOpen = false
    @State private var openTask: Task<Void, Never>?
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onNewProvider) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("New \(provider.displayName)")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.leading, 10)
                .padding(.trailing, 7)
                .frame(height: TopBarMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 14)

            // Chevron yalnız görsel ipucu — açma/kapama hover'la sürülür.
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: TopBarMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .background(Theme.accentVivid)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        VStack(alignment: .leading, spacing: 2) {
            NewTerminalDropdownItem(icon: "terminal", label: "New Bash") {
                isOpen = false
                onNewBash()
            }
        }
        .padding(6)
        .frame(width: 220)
        .background(Theme.bgElevated)
    }
}

/// Dropdown satırı — hover'da highlight (v1 dark dropdown paritesi).
private struct NewTerminalDropdownItem: View {
    let icon: String?
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 16)
                }
                Text(label)
                    .font(.system(size: 12, design: .monospaced))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHovering ? Theme.bgSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
