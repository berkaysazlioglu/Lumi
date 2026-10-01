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
    /// Karar 77: dikkat isteyen kart sarı kenarlık alır. Glow VERİLMEZ —
    /// hale "aktif kart" dilidir, iki hâl karışmasın.
    var needsAttention = false
    let terminalID: TerminalID
    let promptQueue: PromptQueueStore
    @Binding var isQueueOpen: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        Panel(
            variant: .card,
            borderColor: borderColor,
            glow: isActive ? .accent() : nil
        ) {
            VStack(spacing: 0) {
                header()
                content()
            }
        }
        .promptQueueOverlay(isOpen: $isQueueOpen, terminalID: terminalID, store: promptQueue)
    }

    private var borderColor: Color {
        if isActive { return Theme.accentPrimary }
        return needsAttention ? Theme.warning : Theme.border
    }
}

/// Terminal kartının ORTAK header'ı (refactor 6.7): ajan etkinlik glifi + stalled
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
    /// Hook kararı beklerken Projects paneliyle aynı zil glifini gösterir.
    var isAwaitingDecision = false
    /// Karar 77: seçili değilken turn'ü kapanmış ya da karar bekleyen terminal —
    /// başlık sarıya döner ki göz taramada yakalasın.
    var needsAttention = false
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
    /// Karar 97 Edit modu: yalnız minimize kalır (gizliler de düzenlenebilsin);
    /// kuyruk/zoom/kapat ve tık jestleri sürüklemeyle yarışmasın diye çekilir.
    var isArranging = false

    var body: some View {
        HStack(spacing: style.spacing) {
            AgentActivityIcon(
                state: AgentActivityState(
                    status: meta.status,
                    isAwaitingDecision: isAwaitingDecision
                ),
                size: style.titleSize
            )
            TerminalIdentityIcon(provider: meta.provider, size: style.titleSize)
            if isStalled {
                Badge(text: "stalled", color: Theme.warning)
                    .accessibilityLabel("Terminal stalled")
            }
            Text(meta.displayTitle)
                .font(Theme.Typography.mono(style.titleSize))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .accessibilityLabel(
                    needsAttention ? "\(meta.displayTitle), needs attention" : meta.displayTitle
                )
            Spacer()
            if !isArranging {
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
            }
            IconButton(
                systemName: "minus",
                label: "Minimize \(meta.displayTitle)",
                size: .caption,
                action: onMinimize
            )
            if !isArranging {
                IconButton(
                    systemName: "xmark",
                    label: "Close \(meta.displayTitle)",
                    size: .caption,
                    role: .destructive,
                    action: onClose
                )
            }
        }
        .padding(.leading, style.leadingPadding)
        .padding(.trailing, style.trailingPadding)
        .padding(.vertical, style.verticalPadding)
        .background(Theme.bgElevated)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: Theme.Stroke.hairline)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isArranging { onTap?() } }
        // Başlığa çift tık zoom'u çevirir (grid → maximize, maximize → grid)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !isArranging { onZoom() } })
    }

    private var titleColor: Color {
        if needsAttention { return Theme.warning }
        return isActive ? Theme.textPrimary : Theme.textSecondary
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
        .frame(width: size.scaledPoints, height: size.scaledPoints)
        .accessibilityLabel(provider.map { $0.rawValue.capitalized } ?? "Shell")
    }
}

#if DEBUG
#Preview("TerminalCardHeader") {
    VStack(spacing: Theme.Spacing.xl) {
        AgentActivityIcon(state: .running)
        AgentActivityIcon(state: .awaitingDecision)
        AgentActivityIcon(state: .done)
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
