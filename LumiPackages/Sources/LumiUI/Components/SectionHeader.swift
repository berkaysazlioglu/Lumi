import SwiftUI

/// Panel bölümü başlığı (Faz 7.2).
///
/// Üç kopyası vardı — Sessions (accent ikon + sayaç), git panelleri (sol
/// chevron + sayaç) ve Project Context (ikon + sağ chevron + arama). Hepsi
/// aynı tipografiye (11pt semibold, uppercase, 0.6 tracking) sahipti; ayrım
/// yalnız chevron'un yeri ve sayacın rengiydi.
struct SectionHeader<Trailing: View>: View {
    /// Aç/kapa okunun yeri.
    enum Disclosure {
        case none
        case leading
        case trailing
    }

    /// Başlığın yanındaki sayaç rozeti.
    struct Count {
        let value: Int
        var color: Color = Theme.textMuted
        var style: Badge.Style = .neutral
        var shape: Badge.Shape = .rounded
        var size: Theme.Typography.Size = .label
        var weight: Font.Weight = .regular

        /// Nötr sayaç (Sessions).
        static func neutral(_ value: Int) -> Count { Count(value: value) }

        /// Dikkat çeken sayaç (git CHANGES).
        static func warning(_ value: Int) -> Count {
            Count(
                value: value,
                color: Theme.warning,
                style: .tinted,
                shape: .capsule,
                size: .caption,
                weight: .bold
            )
        }
    }

    let title: String
    var icon: String?
    var count: Count?
    var disclosure: Disclosure = .none
    var isExpanded = true
    var contentPadding: CGFloat = 0
    /// Başlığa tıklama eylemi (genelde aç/kapa). `nil` ise başlık pasiftir.
    var onToggle: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        icon: String? = nil,
        count: Count? = nil,
        disclosure: Disclosure = .none,
        isExpanded: Bool = true,
        contentPadding: CGFloat = 0,
        onToggle: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.disclosure = disclosure
        self.isExpanded = isExpanded
        self.contentPadding = contentPadding
        self.onToggle = onToggle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let onToggle {
                Button(action: onToggle) { titleRow.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(title), \(isExpanded ? "collapse" : "expand") section"
                    )
            } else {
                titleRow
            }
            Spacer(minLength: 0)
            trailing()
            if disclosure == .trailing { chevron }
        }
        .padding(contentPadding)
    }

    private var titleRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            if disclosure == .leading { chevron }
            if let icon {
                Image(systemName: icon)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.accentPrimary)
                    .accessibilityHidden(true)
            }
            Text(title.uppercased())
                .font(Theme.Typography.mono(.label, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            if let count {
                Badge(
                    text: "\(count.value)",
                    color: count.color,
                    size: count.size,
                    weight: count.weight,
                    style: count.style,
                    shape: count.shape
                )
            }
        }
    }

    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(Theme.Typography.ui(.caption, weight: .bold))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
        SectionHeader(title: "Sessions", icon: "square.stack.3d.up", count: .neutral(3))
        SectionHeader(
            title: "Changes",
            count: .warning(7),
            disclosure: .leading,
            isExpanded: true,
            contentPadding: Theme.Spacing.lg,
            onToggle: {}
        )
        SectionHeader(
            title: "Project Context",
            icon: "list.bullet.indent",
            disclosure: .trailing,
            isExpanded: false,
            onToggle: {}
        ) {
            IconButton(systemName: "magnifyingglass", label: "Filter files", weight: .semibold) {}
        }
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
