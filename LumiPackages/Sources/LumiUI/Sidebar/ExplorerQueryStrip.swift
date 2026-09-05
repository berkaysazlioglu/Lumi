import LumiKit
import SwiftUI

/// Explorer aramasının iki kipi. Sorgu metni kipler arasında KORUNUR: aynı
/// kelimeyi önce ada, sonra içeriğe sormak tek tıklık bir iştir.
enum ExplorerSearchMode: String, CaseIterable, Sendable {
    case names
    case contents

    var title: String {
        switch self {
        case .names: return "Names"
        case .contents: return "Contents"
        }
    }

    var placeholder: String {
        switch self {
        case .names: return "Filter files…"
        case .contents: return "Search"
        }
    }

    /// Erişilebilirlik etiketi / ipucu — başlık tek başına ne yaptığını söylemez.
    var help: String {
        switch self {
        case .names: return "Filter files by name"
        case .contents: return "Search file contents"
        }
    }
}

/// Arama şeridi (Orca `FileExplorerQueryStrip` düzeni):
///
/// 1. çerçeveli arama kutusu — büyüteç + alan + (Contents kipinde) `Aa` /
///    `ab` / `.*` seçenek düğmeleri;
/// 2. tam genişlik Names | Contents anahtarı;
/// 3. yalnız Contents kipinde FILES TO INCLUDE / FILES TO EXCLUDE alanları.
///
/// Sorgu metni tek `query`de yaşar; içerik seçenekleri `contentQuery`de.
struct ExplorerQueryStrip: View {
    @Binding var query: String
    @Binding var mode: ExplorerSearchMode
    @Binding var contentQuery: ExplorerContentQuery

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            searchBox
            SegmentedModeSwitch(
                options: ExplorerSearchMode.allCases,
                selection: $mode,
                title: \.title,
                help: \.help,
                accessibilityLabel: "Explorer search mode"
            )
            if mode == .contents {
                filterField("Files to include", placeholder: "files to include (e.g. *.swift, Sources/**)",
                            text: $contentQuery.includePatterns)
                filterField("Files to exclude", placeholder: "files to exclude (e.g. *.meta, dist/**)",
                            text: $contentQuery.excludePatterns)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.bgSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
        }
    }

    // MARK: - Arama kutusu

    private var searchBox: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            TextField(mode.placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel(mode.help)
                .onKeyPress(.escape) { query = ""; return .handled }
            if !query.isEmpty {
                IconButton(systemName: "xmark", label: "Clear search", size: .caption) { query = "" }
            }
            if mode == .contents { matchOptions }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Spacing.xxxl - Theme.Spacing.xs)
        .background(Theme.bgDeep)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
    }

    /// `Aa` büyük/küçük harf, `ab` tam kelime, `.*` regex — VS Code'un üç
    /// klasik anahtarı; metin glyph'leri ikonlardan daha tanıdık.
    private var matchOptions: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            optionToggle("Aa", help: "Match case", isOn: $contentQuery.isCaseSensitive)
            optionToggle("ab", help: "Match whole word", isOn: $contentQuery.isWholeWord, underlined: true)
            optionToggle(".*", help: "Use regular expression", isOn: $contentQuery.isRegex)
        }
    }

    private func optionToggle(_ glyph: String, help: String, isOn: Binding<Bool>, underlined: Bool = false) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(glyph)
                .font(Theme.Typography.mono(.label, weight: .semibold))
                .underline(underlined)
                .foregroundStyle(isOn.wrappedValue ? Theme.accentPrimary : Theme.textMuted)
                .frame(width: Theme.Spacing.xxl - Theme.Spacing.xxs, height: Theme.Spacing.xxl - Theme.Spacing.xs)
                .background(isOn.wrappedValue ? Theme.accentPrimary.opacity(Self.activeOptionOpacity) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Dosya filtreleri

    private func filterField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label.uppercased())
                .font(Theme.Typography.ui(.caption, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.textMuted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.ui(.label))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Spacing.xxl)
                .background(Theme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
                )
                .accessibilityLabel(label)
        }
    }

    private static let activeOptionOpacity = 0.18
}

#if DEBUG
#Preview("ExplorerQueryStrip") {
    VStack(spacing: Theme.Spacing.md) {
        ExplorerQueryStrip(query: .constant(""), mode: .constant(.names), contentQuery: .constant(ExplorerContentQuery(text: "")))
        ExplorerQueryStrip(
            query: .constant("theme"), mode: .constant(.contents),
            contentQuery: .constant(ExplorerContentQuery(text: "theme", isCaseSensitive: true))
        )
    }
    .frame(width: 320)
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
