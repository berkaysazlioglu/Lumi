import LumiKit
import LumiState
import SwiftUI

/// Terminal kartının ORTAK çerçevesi (refactor 6.7).
///
/// Grid kartı (`TerminalCardView`) ile maximize görünümü (`MaximizedTerminalView`)
/// aynı kabuğu kullanır: bgSurface zemin, 8pt köşe, aktifken accent kenarlık +
/// mor glow (v1 `.terminal-card.active`), üstünde prompt-kuyruğu overlay'i.
/// Önceden iki dosyada birebir kopyaydı; ölçüler DEĞİŞMEDİ.
struct TerminalCardChrome<Header: View, Content: View>: View {
    /// Aktif kart: 1px accent ring + 15pt glow. Maximize'da her zaman `true`.
    let isActive: Bool
    let terminalID: TerminalID
    let promptQueue: PromptQueueStore
    @Binding var isQueueOpen: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    private static var cornerRadius: CGFloat { 8 }

    var body: some View {
        VStack(spacing: 0) {
            header()
            content()
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(isActive ? Theme.accentPrimary : Theme.border, lineWidth: 1)
        )
        .shadow(
            color: isActive ? Theme.accentVivid.opacity(0.2) : .clear,
            radius: isActive ? 15 : 0
        )
        .promptQueueOverlay(isOpen: $isQueueOpen, terminalID: terminalID, store: promptQueue)
    }
}

/// Terminal kartının ORTAK header'ı (refactor 6.7): durum noktası + stalled
/// rozeti + başlık + kuyruk düğmesi + zoom/minimize/kapat.
///
/// Grid ve maximize varyantları yalnız `Style` (boşluk/punto/padding) ve zoom
/// düğmesinin ikonu/eylemi ile ayrışır — görsel parite için ölçüler birebir
/// korunur (grid: karar 31'in ince header'ı).
struct TerminalCardHeader: View {
    struct Style {
        let spacing: CGFloat
        let titleSize: CGFloat
        let leadingPadding: CGFloat
        let trailingPadding: CGFloat
        let verticalPadding: CGFloat

        /// Karar 31: ince kart header'ı (20px butonlar, 3px dikey padding).
        static let grid = Style(
            spacing: 6,
            titleSize: 11,
            leadingPadding: 10,
            trailingPadding: 6,
            verticalPadding: 3
        )

        /// Maximize: tek kart ekranı kapladığı için biraz daha ferah.
        static let maximized = Style(
            spacing: 8,
            titleSize: 12,
            leadingPadding: 12,
            trailingPadding: 12,
            verticalPadding: 6
        )
    }

    let meta: TerminalMeta
    let isActive: Bool
    let isStalled: Bool
    let style: Style
    let promptQueue: PromptQueueStore
    @Binding var isQueueOpen: Bool
    /// Grid'de "büyüt", maximize'da "geri küçült" — ikon farkı, eylem farkı.
    let zoomIcon: String
    let onZoom: () -> Void
    let onMinimize: () -> Void
    let onClose: () -> Void
    /// Tek tık davranışı yalnız grid'de var (kartı odakla); maximize'da nil.
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: style.spacing) {
            StatusDot(status: meta.status)
            if isStalled { StalledBadge() }
            Text(meta.displayTitle)
                .font(.system(size: style.titleSize, design: .monospaced))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            PromptQueueToggleButton(
                count: promptQueue.count(for: meta.id),
                isPaused: promptQueue.isPaused(meta.id),
                isOpen: $isQueueOpen
            )
            CardHeaderButton(systemName: zoomIcon, action: onZoom)
            CardHeaderButton(systemName: "minus", action: onMinimize)
            CardHeaderButton(systemName: "xmark", isDestructive: true, action: onClose)
        }
        .padding(.leading, style.leadingPadding)
        .padding(.trailing, style.trailingPadding)
        .padding(.vertical, style.verticalPadding)
        .background(Theme.bgElevated)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        // Başlığa çift tık zoom'u çevirir (grid → maximize, maximize → grid)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onZoom))
    }
}

/// Feed akışı donduğunda (Ek A §A.2-10) header'da beliren küçük uyarı rozeti.
/// Siyah/boş kart yerine görünür durum: "veri geliyor ama ekrana çizilemiyor".
struct StalledBadge: View {
    var body: some View {
        Text("stalled")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.warning)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Terminal stalled")
    }
}

/// Durum noktası: working / waiting-unseen pulse'lı, gerisi sabit.
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
            .frame(width: 7, height: 7)
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

/// Kart header butonu (ince: 20×20, hover'da kapatma kırmızıya döner).
struct CardHeaderButton: View {
    let systemName: String
    var isDestructive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hoverColor)
                .frame(width: 20, height: 20)
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
