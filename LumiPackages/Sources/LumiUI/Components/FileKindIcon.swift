import LumiKit
import SwiftUI

/// Dosya türü ikonu — Explorer satırı, içerik arama başlığı ve dosya listeleri
/// aynı glyph + renk çiftini buradan alır.
///
/// Unity'nin dört asset türü bundle PNG'siyle çizilir (SF Symbol karşılığı
/// yok); geri kalan her tür bir SF Symbol + `Theme.fileColor` tonudur. PNG
/// yüklenemezse SF Symbol fallback'i devreye girer, satır hiçbir durumda
/// ikonsuz kalmaz.
///
/// Dekoratiftir: satırın adı hemen yanında olduğu için VoiceOver'dan gizlenir.
struct FileKindIcon: View {
    let kind: FileKind
    var size: Theme.Typography.Size = .body

    var body: some View {
        icon
            .frame(width: Theme.Row.iconColumn)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let glyph = FileKindIcon.textGlyph(for: kind) {
            // JetBrains tarzı harf ikonu (Rider'ın "C#" / "M↓" glyph'leri).
            Text(glyph)
                .font(Theme.Typography.ui(.caption, weight: .bold))
                .foregroundStyle(Theme.fileColor(for: kind))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Theme.Row.iconColumn)
        } else if let unityName = FileKindIcon.unityIconName(for: kind),
           let image = LumiAssets.unityIcon(unityName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size.points, height: size.points)
        } else {
            Image(systemName: FileKindIcon.symbolName(for: kind))
                .font(Theme.Typography.ui(size))
                .foregroundStyle(Theme.fileColor(for: kind))
        }
    }

    /// Metin glyph'iyle çizilen türler (JetBrains Rider ikon dili); diğerleri için nil.
    static func textGlyph(for kind: FileKind) -> String? {
        switch kind {
        case .csharp: return "C#"
        case .markdown: return "M↓"
        default: return nil
        }
    }

    /// Bundle PNG'siyle çizilen türler; diğerleri için nil.
    static func unityIconName(for kind: FileKind) -> LumiAssets.UnityIconName? {
        switch kind {
        case .unityScene: return .sceneAsset
        case .unityPrefab: return .prefab
        case .unityScriptableObject: return .scriptableObject
        case .unityMaterial: return .material
        default: return nil
        }
    }

    /// Tür → SF Symbol adı (Unity türlerinde fallback glyph'i).
    static func symbolName(for kind: FileKind) -> String {
        switch kind {
        case .folder: return "folder"
        case .folderOpen: return "folder.fill"
        case .swift: return "swift"
        case .csharp, .typescript, .javascript: return "curlybraces"
        case .json: return "curlybraces.square"
        case .yaml: return "list.bullet.indent"
        case .markdown: return "doc.richtext"
        case .text: return "doc.text"
        case .shell: return "terminal"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .shader: return "sparkles"
        case .unityScene, .unityPrefab, .unityScriptableObject, .unityMaterial: return "cube"
        case .unityMeta: return "doc.plaintext"
        case .config: return "gearshape"
        case .lock: return "lock"
        case .git: return "arrow.triangle.branch"
        case .archive: return "archivebox"
        case .font: return "textformat"
        case .audio: return "waveform"
        case .video: return "film"
        case .generic: return "doc"
        }
    }
}

#if DEBUG
#Preview("FileKindIcon") {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), alignment: .leading), count: 4)) {
        ForEach(FileKind.allCases, id: \.self) { kind in
            HStack(spacing: Theme.Spacing.sm) {
                FileKindIcon(kind: kind)
                Text(String(describing: kind))
                    .font(Theme.Typography.ui(.body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(height: Theme.Row.compact)
        }
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
