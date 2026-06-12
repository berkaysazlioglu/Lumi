import LumiKit
import LumiState
import SwiftUI

/// Aktif repo'nun görünür terminal kartlarını GridLayoutMath frame'leriyle dizer.
/// `fit` viewport'a sığar (scroll yok); `scroll` min boyutu koruyup dikey scroll'lanır.
struct TerminalGridView: View {
    let terminals: [TerminalMeta]
    let layout: LumiKit.GridLayout
    let activeTerminalID: TerminalID?
    let viewProvider: any TerminalViewProviding
    let onFocus: (TerminalID) -> Void
    let onMinimize: (TerminalID) -> Void
    let onMaximize: (TerminalID) -> Void
    let onClose: (TerminalID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let frames = GridLayoutMath.frames(
                layout: layout,
                container: geometry.size,
                visibleCount: terminals.count
            )
            if layout.heightMode == .fit {
                placedCards(frames: frames)
            } else {
                ScrollView {
                    placedCards(frames: frames)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: GridLayoutMath.contentHeight(frames: frames),
                            alignment: .topLeading
                        )
                }
            }
        }
    }

    private func placedCards(frames: [CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(terminals.enumerated()), id: \.element.id) { index, meta in
                if index < frames.count {
                    let frame = frames[index]
                    TerminalCardView(
                        meta: meta,
                        isActive: activeTerminalID == meta.id,
                        viewProvider: viewProvider,
                        onFocus: { onFocus(meta.id) },
                        onMinimize: { onMinimize(meta.id) },
                        onMaximize: { onMaximize(meta.id) },
                        onClose: { onClose(meta.id) }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
    }
}

/// Terminal kartı: başlık çubuğu (dot + başlık + minimize/kapat) + canlı terminal.
/// Başlık önceliği (spec/20 §10): oscTitle > task > name > "Terminal".
struct TerminalCardView: View {
    let meta: TerminalMeta
    let isActive: Bool
    let viewProvider: any TerminalViewProviding
    let onFocus: () -> Void
    let onMinimize: () -> Void
    let onMaximize: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            TerminalHostView(terminalID: meta.id, provider: viewProvider)
                .id(meta.id)
                .padding(8)
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Theme.accentPrimary : Theme.border, lineWidth: 1)
        )
        // v1 odak halkası: 1px ring + mor glow (globals.css .terminal-card.active)
        .shadow(
            color: isActive ? Theme.accentVivid.opacity(0.2) : .clear,
            radius: isActive ? 15 : 0
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(status: meta.status)
            Text(meta.oscTitle ?? meta.task ?? meta.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            CardHeaderButton(systemName: "arrow.up.left.and.arrow.down.right", action: onMaximize)
            CardHeaderButton(systemName: "minus", action: onMinimize)
            CardHeaderButton(systemName: "xmark", isDestructive: true, action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.bgElevated)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        // Başlığa çift tık → maximize/solo (spec/20 — rahat çalışma)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onMaximize))
    }
}

/// Durum noktası (spec/23): working / waiting-unseen pulse'lı, gerisi sabit.
struct StatusDot: View {
    let status: TerminalStatus

    @State private var isPulsing = false

    private var shouldPulse: Bool {
        status == .working || status == .waitingUnseen
    }

    var body: some View {
        let color = Theme.statusColor(for: status)
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: shouldPulse ? color.opacity(0.8) : .clear, radius: 3)
            .opacity(shouldPulse && isPulsing ? 0.4 : 1)
            .animation(
                shouldPulse
                    ? .easeInOut(duration: 1).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .onChange(of: shouldPulse) { _, pulse in
                isPulsing = pulse
            }
    }
}

/// Kart header butonu (v1: 24×24, hover'da kapatma kırmızıya döner).
struct CardHeaderButton: View {
    let systemName: String
    var isDestructive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hoverColor)
                .frame(width: 24, height: 24)
                .background(isHovering ? hoverBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var hoverColor: Color {
        guard isHovering else { return Theme.textMuted }
        return isDestructive ? Theme.error : Theme.textPrimary
    }

    private var hoverBackground: Color {
        isDestructive ? Theme.error.opacity(0.2) : Theme.bgSurface
    }
}
