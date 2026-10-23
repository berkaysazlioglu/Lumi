import LumiKit
import LumiState
import SwiftUI

/// Terminal kartının ORTAK çerçevesi (refactor 6.7).
///
/// Grid kartı (`TerminalCardView`) ile maximize görünümü (`MaximizedTerminalView`)
/// aynı kabuğu kullanır. Faz 7.2'de zemin/köşe/kenarlık/gölge yığını ortak
/// `Panel` bileşenine devredildi; ölçüler DEĞİŞMEDİ (bgSurface, 8pt köşe,
/// aktifken accent kenarlık + mor glow). Karar 120: renk atanmış projede
/// aktif kenarlık ve hale proje rengindedir.
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

    /// Karar 120: projenin kimlik rengi kenarlığa ve haleye iner.
    @Environment(\.terminalProjectColors) private var projectColors

    var body: some View {
        Panel(
            variant: .card,
            borderColor: Theme.terminalBorderColor(isAttention ? restingEmphasis : emphasis),
            glow: Theme.terminalGlowColor(emphasis).map { .accent($0) }
        ) {
            VStack(spacing: 0) {
                // Karar 126: orchestrator ışığı ekrandaki kartın header'ına iner.
                header().flightAnchor(.terminalHeader(terminalID))
                content()
            }
        }
        .overlay { attentionBorder }
        .promptQueueOverlay(isOpen: $isQueueOpen, terminalID: terminalID, store: promptQueue)
    }

    /// Öncelik: seçili (proje rengi | accent) > dikkat (karar 77) > proje
    /// rengi soluk (karar 120) > border.
    private var emphasis: TerminalBorderEmphasis {
        TerminalBorderEmphasis.resolve(
            isActive: isActive,
            needsAttention: needsAttention,
            projectColor: projectColors[terminalID]
        )
    }

    private var isAttention: Bool { emphasis == .attention }

    /// Dikkat nabzı açıldığında altta görünen dinlenme kenarlığı.
    private var restingEmphasis: TerminalBorderEmphasis {
        TerminalBorderEmphasis.resolve(isActive: false, needsAttention: false, projectColor: projectColors[terminalID])
    }

    /// Karar 77 eki: dikkat sarısı ayrı bir katmanda nefes alır ki nabız
    /// kartın içeriğini (terminal view'ı) her karede yeniden çizdirmesin.
    @ViewBuilder
    private var attentionBorder: some View {
        if isAttention {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.terminalBorderColor(.attention), lineWidth: Theme.Stroke.graph)
                .shadow(color: Theme.warning.opacity(AttentionPulse.glowOpacity), radius: AttentionPulse.glowRadius)
                .attentionPulse(true)
                .allowsHitTesting(false)
        }
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

    /// Karar 103: All Terminals'ta başlığın yanında checkout adı.
    @Environment(\.terminalCheckoutLabels) private var checkoutLabels
    /// Karar 120: projenin kimlik rengi — header zemini, başlık, ikon
    /// butonları, alt çizgi ve checkout etiketi o renkte.
    @Environment(\.terminalProjectColors) private var projectColors

    private var projectColor: ProjectColor? { projectColors[meta.id] }
    private var projectTint: Color? { projectColor.map(Theme.projectColor) }

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
                .attentionPulse(needsAttention)
                .lineLimit(1)
                .accessibilityLabel(
                    needsAttention ? "\(meta.displayTitle), needs attention" : meta.displayTitle
                )
            if let checkout = checkoutLabels[meta.repoPath] {
                Text(checkout)
                    .font(Theme.Typography.mono(style.titleSize))
                    .foregroundStyle(projectTint ?? Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
                    .accessibilityLabel("in \(checkout)")
            }
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
        .environment(\.iconButtonTint, projectColor.map(IconButtonTint.project))
        .background {
            ZStack {
                Theme.bgElevated
                projectTint?.opacity(Theme.ProjectTint.headerOpacity)
            }
        }
        .overlay(alignment: .bottom) {
            (projectTint?.opacity(Theme.ProjectTint.hairlineOpacity) ?? Theme.border)
                .frame(height: Theme.Stroke.hairline)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isArranging { onTap?() } }
        // Başlığa çift tık zoom'u çevirir (grid → maximize, maximize → grid)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !isArranging { onZoom() } })
    }

    private var titleColor: Color {
        if needsAttention { return Theme.warning }
        if let projectColor { return Theme.ProjectTint.titleColor(projectColor, isActive: isActive) }
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
