import LumiKit
import LumiState
import SwiftUI

/// Terminal kartının ORTAK çerçevesi (refactor 6.7).
///
/// Grid kartı (`TerminalCardView`) ile maximize görünümü (`MaximizedTerminalView`)
/// aynı kabuğu kullanır. Faz 7.2'de zemin/köşe/kenarlık/gölge yığını ortak
/// `Panel` bileşenine devredildi; ölçüler DEĞİŞMEDİ (bgSurface, 8pt köşe,
/// aktifken accent kenarlık + mor glow).
struct TerminalCardChrome<Header: View, Content: View>: View {
    /// Aktif kart: 1px accent ring + 15pt glow. Maximize'da her zaman `true`.
    let isActive: Bool
    let terminalID: TerminalID
    let promptQueue: PromptQueueStore
    @Binding var isQueueOpen: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        Panel(
            variant: .card,
            borderColor: isActive ? Theme.accentPrimary : Theme.border,
            glow: isActive ? .accent() : nil
        ) {
            VStack(spacing: 0) {
                header()
                content()
            }
        }
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
        let titleSize: Theme.Typography.Size
        let leadingPadding: CGFloat
        let trailingPadding: CGFloat
        let verticalPadding: CGFloat

        /// Karar 31: ince kart header'ı (20px butonlar, 3px dikey padding).
        static let grid = Style(
            spacing: Theme.Spacing.sm,
            titleSize: .label,
            leadingPadding: 10, // ölçek dışı ara değer (karar 31 paritesi)
            trailingPadding: Theme.Spacing.sm,
            verticalPadding: 3 // ölçek dışı ara değer (karar 31 paritesi)
        )

        /// Maximize: tek kart ekranı kapladığı için biraz daha ferah.
        static let maximized = Style(
            spacing: Theme.Spacing.md,
            titleSize: .body,
            leadingPadding: Theme.Spacing.lg,
            trailingPadding: Theme.Spacing.lg,
            verticalPadding: Theme.Spacing.sm
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
    /// Zoom düğmesinin erişilebilirlik etiketi (ikon tek başına anlamsız).
    let zoomLabel: String
    let onZoom: () -> Void
    let onMinimize: () -> Void
    let onClose: () -> Void
    /// Tek tık davranışı yalnız grid'de var (kartı odakla); maximize'da nil.
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: style.spacing) {
            StatusDot(status: meta.status)
            TerminalIdentityIcon(provider: meta.provider, size: style.titleSize)
            if isStalled {
                Badge(text: "stalled", color: Theme.warning)
                    .accessibilityLabel("Terminal stalled")
            }
            Text(meta.displayTitle)
                .font(Theme.Typography.mono(style.titleSize))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            PromptQueueToggleButton(
                count: promptQueue.count(for: meta.id),
                isPaused: promptQueue.isPaused(meta.id),
                isOpen: $isQueueOpen
            )
            IconButton(
                systemName: zoomIcon,
                label: zoomLabel,
                size: .caption,
                action: onZoom
            )
            IconButton(
                systemName: "minus",
                label: "Minimize \(meta.displayTitle)",
                size: .caption,
                action: onMinimize
            )
            IconButton(
                systemName: "xmark",
                label: "Close \(meta.displayTitle)",
                size: .caption,
                role: .destructive,
                action: onClose
            )
        }
        .padding(.leading, style.leadingPadding)
        .padding(.trailing, style.trailingPadding)
        .padding(.vertical, style.verticalPadding)
        .background(Theme.bgElevated)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: Theme.Stroke.hairline)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        // Başlığa çift tık zoom'u çevirir (grid → maximize, maximize → grid)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onZoom))
    }
}

/// Kim koşuyor (karar 45; Orca `TerminalTabLeadingIcon`): durum noktasının
/// yanında ajan logosu (Claude / Codex) ya da düz shell için terminal glifi.
/// İki ayrı glif — biri "ne durumda", diğeri "kim" — tek süslü ikona
/// kaynaştırılmaz ki paralel kartlar taranabilir kalsın.
struct TerminalIdentityIcon: View {
    let provider: AgentProvider?
    var size: Theme.Typography.Size = .label

    var body: some View {
        Group {
            if let provider {
                ProviderIcon(provider: provider, size: size)
            } else {
                Image(systemName: "terminal")
                    .font(Theme.Typography.ui(size))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(width: size.points, height: size.points)
        .accessibilityLabel(provider.map { $0.rawValue.capitalized } ?? "Shell")
    }
}

/// Durum noktası: working / waiting-unseen pulse'lı, gerisi sabit.
struct StatusDot: View {
    let status: TerminalStatus

    @State private var isPulsing = false

    private static let diameter: CGFloat = 7

    private var shouldPulse: Bool {
        status == .working || status == .waitingUnseen
    }

    var body: some View {
        let color = Theme.statusColor(for: status)
        Circle()
            .fill(color)
            .frame(width: Self.diameter, height: Self.diameter)
            .shadow(color: shouldPulse ? color.opacity(0.8) : .clear, radius: 3)
            .opacity(shouldPulse && isPulsing ? 0.4 : 1)
            .animation(shouldPulse ? Theme.Motion.statusPulse : .default, value: isPulsing)
            .onAppear { isPulsing = true }
            .onChange(of: shouldPulse) { _, pulse in
                isPulsing = pulse
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("TerminalCardHeader") {
    VStack(spacing: Theme.Spacing.xl) {
        StatusDot(status: .working)
        HStack(spacing: Theme.Spacing.sm) {
            TerminalIdentityIcon(provider: .claude)
            TerminalIdentityIcon(provider: .codex)
            TerminalIdentityIcon(provider: nil)
        }
        Badge(text: "stalled", color: Theme.warning)
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgElevated)
}
#endif
