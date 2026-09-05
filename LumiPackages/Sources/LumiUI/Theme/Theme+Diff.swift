import AppKit
import LumiKit
import SwiftUI

/// Diff renk eşlemesinin TEK kaynağı (refactor 7.9).
///
/// Eşleme eskiden üç yerde kopyalıydı (`SideBySideDiffView`, `MarkdownDiffView`,
/// `Theme.NS`) — 0.13 zemin opaklığı dahil. Palet tutarlılığı bağlayıcı bir
/// karardır (karar 11), bu yüzden hem SwiftUI hem AppKit tarafı buradan türer.
///
/// Ayrı dosyada durmasının nedeni Theme token'larının (Typography/Radius/
/// Spacing/Motion) `Theme.swift`'te büyümesi: diff paleti kendi dosyasında.
extension Theme {
    public enum Diff {
        /// Ekleme/silme satırının zemin opaklığı (v1 paritesi).
        public static let backgroundOpacity: Double = 0.13
    }

    /// Diff satırının metin rengi.
    public static func diffForeground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .context: return textPrimary
        case .addition: return success
        case .deletion: return error
        }
    }

    /// Diff satırının zemin rengi; context satırı zeminsizdir.
    public static func diffBackground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .context: return .clear
        case .addition: return success.opacity(Diff.backgroundOpacity)
        case .deletion: return error.opacity(Diff.backgroundOpacity)
        }
    }
}

extension Theme.NS {
    /// `NSAttributedString` tabanlı görünümlerin diff zemini — SwiftUI
    /// varyantıyla aynı sabitten türer.
    public static func diffBackground(for kind: DiffLine.Kind) -> NSColor {
        switch kind {
        case .context: return .clear
        case .addition: return success.withAlphaComponent(Theme.Diff.backgroundOpacity)
        case .deletion: return error.withAlphaComponent(Theme.Diff.backgroundOpacity)
        }
    }
}
