import LumiKit
import LumiState
import SwiftUI

/// Maximize/solo görünümü (design/03 — tek terminalle rahat çalışma): seçili
/// terminal tüm içerik alanını kaplar; diğer görünür terminaller altta chip
/// şeridine iner. Chip → o terminale geç; restore butonu/Esc → grid'e dön.
struct MaximizedTerminalView: View {
    let maximized: TerminalMeta
    let others: [TerminalMeta]
    let viewProvider: any TerminalViewProviding
    @Bindable var promptQueue: PromptQueueStore
    let onSwitch: (TerminalID) -> Void
    let onMinimize: (TerminalID) -> Void
    let onClose: (TerminalID) -> Void
    let onRestore: () -> Void

    @State private var isQueueOpen = false

    var body: some View {
        VStack(spacing: 8) {
            terminalCard
            if !others.isEmpty {
                switcherStrip
            }
        }
        // Esc → grid'e dön (macOS exit-command)
        .onExitCommand(perform: onRestore)
    }

    private var terminalCard: some View {
        VStack(spacing: 0) {
            header
            TerminalHostView(terminalID: maximized.id, provider: viewProvider)
                .id(maximized.id)
                .padding(8)
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.accentPrimary, lineWidth: 1)
        )
        .shadow(color: Theme.accentVivid.opacity(0.2), radius: 15)
        .promptQueueOverlay(isOpen: $isQueueOpen, terminalID: maximized.id, store: promptQueue)
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(status: maximized.status)
            Text(maximized.oscTitle ?? maximized.task ?? maximized.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            PromptQueueToggleButton(
                count: promptQueue.count(for: maximized.id),
                isPaused: promptQueue.isPaused(maximized.id),
                isOpen: $isQueueOpen
            )
            // Geri-küçült (maximize'ı kapatır)
            CardHeaderButton(systemName: "arrow.down.right.and.arrow.up.left", action: onRestore)
            CardHeaderButton(systemName: "minus", action: { onMinimize(maximized.id) })
            CardHeaderButton(systemName: "xmark", isDestructive: true, action: { onClose(maximized.id) })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.bgElevated)
        .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
        // Başlığa çift tık → grid'e dön (kart başlığındaki maximize'ın tersi)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded(onRestore))
    }

    private var switcherStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(others) { meta in
                    Button {
                        onSwitch(meta.id)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Theme.statusColor(for: meta.status))
                                .frame(width: 6, height: 6)
                            Text(meta.oscTitle ?? meta.task ?? meta.name)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.bgSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(height: 24)
    }
}
