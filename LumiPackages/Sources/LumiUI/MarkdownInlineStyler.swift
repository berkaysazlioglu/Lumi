import Foundation
import SwiftUI

/// Satır-içi markdown'ın görsel stillendirmesi (karar 21). Ayrı tutulur çünkü
/// `MarkdownDiffBuilder` blok ayrıştırmadan sorumlu, burası tema/font kararları.
///
/// Gerekli: taban prose fontu proportional olduğu için, backtick'leri kaybolan
/// kod parçaları ve link'ler run bazında ayrıştırılmadan düz metne benziyor.
enum MarkdownInlineStyler {
    static func styled(_ text: String, fontSize: CGFloat) -> AttributedString {
        var attributed = MarkdownDiffBuilder.inlineAttributed(text)
        // Range'ler önce toplanır: koleksiyonu gezerken mutasyon yapılmaz.
        let codeRanges = attributed.runs
            .filter { $0.inlinePresentationIntent?.contains(.code) == true }
            .map(\.range)
        for range in codeRanges {
            attributed[range].font = .system(size: fontSize - 1, design: .monospaced)
            attributed[range].foregroundColor = Theme.accentCyan
        }
        let linkRanges = attributed.runs
            .filter { $0.link != nil }
            .map(\.range)
        for range in linkRanges {
            attributed[range].foregroundColor = Theme.accentPrimary
            attributed[range].underlineStyle = .single
        }
        return attributed
    }
}
