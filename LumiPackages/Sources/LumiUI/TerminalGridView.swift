import LumiKit
import LumiState
import SwiftUI

/// Aktif repo'nun görünür terminal kartlarını GridLayoutMath frame'leriyle dizer.
/// rows modu viewport'a sığar (scroll yok); auto/columns dikey scroll'lanır.
struct TerminalGridView: View {
    let terminals: [TerminalMeta]
    let layout: LumiKit.GridLayout
    let activeTerminalID: TerminalID?
    let viewProvider: any TerminalViewProviding
    let onFocus: (TerminalID) -> Void
    let onMinimize: (TerminalID) -> Void
    let onClose: (TerminalID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let frames = GridLayoutMath.frames(
                layout: layout,
                container: geometry.size,
                visibleCount: terminals.count
            )
            if layout.mode == .rows {
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
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            TerminalHostView(terminalID: meta.id, provider: viewProvider)
                .id(meta.id)
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Theme.accentPrimary : Theme.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.statusColor(for: meta.status))
                .frame(width: 8, height: 8)
            Text(meta.oscTitle ?? meta.task ?? meta.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            headerButton(systemName: "minus", action: onMinimize)
            headerButton(systemName: "xmark", action: onClose)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.bgElevated)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
