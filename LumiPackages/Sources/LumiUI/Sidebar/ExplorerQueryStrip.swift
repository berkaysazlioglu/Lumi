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
        case .contents: return "Search in files…"
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

/// Tek arama şeridi: solda büyüteç + tek alan, sağ ucunda kip anahtarı.
///
/// Önce toolbar'ın altında segmented bir `Picker` ve HER kipin kendi ayrı
/// `TextField`'ı vardı; kullanıcı "başlık bir değil, karışık" diyordu — hangi
/// alanın hangi kipe ait olduğu görünmüyor, kip değişince yazılan sorgu
/// kayboluyordu. Artık tek alan var, kip yalnız onun ne aradığını söylüyor.
struct ExplorerQueryStrip: View {
    @Binding var query: String
    @Binding var mode: ExplorerSearchMode

    var body: some View {
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
            modeSwitch
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Spacing.xxxl)
        .background(Theme.bgDeep)
    }

    private var modeSwitch: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(ExplorerSearchMode.allCases, id: \.self) { candidate in
                modeButton(candidate)
            }
        }
        .padding(Theme.Spacing.xxs)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Explorer search mode")
    }

    private func modeButton(_ candidate: ExplorerSearchMode) -> some View {
        let isActive = mode == candidate
        return Button { mode = candidate } label: {
            Text(candidate.title)
                .font(Theme.Typography.ui(.label, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(isActive ? Theme.bgElevated : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(candidate.help)
        .accessibilityLabel(candidate.help)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview("ExplorerQueryStrip") {
    VStack(spacing: Theme.Spacing.md) {
        ExplorerQueryStrip(query: .constant(""), mode: .constant(.names))
        ExplorerQueryStrip(query: .constant("theme"), mode: .constant(.contents))
    }
    .frame(width: 300)
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
