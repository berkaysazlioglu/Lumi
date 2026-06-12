import AppKit
import CoreText
import Foundation

/// JetBrains Mono kaydı (karar 13; OFL lisansı bundle'da).
/// Kayıt başarısızsa sistem monospace'ine sessizce düşülür.
public enum LumiFonts {
    public static let regularName = "JetBrainsMono-Regular"
    public static let boldName = "JetBrainsMono-Bold"

    public static func registerBundledFonts() {
        guard let fontsDirectory = Bundle.module.url(forResource: "Fonts", withExtension: nil) else {
            return
        }
        let fonts = (try? FileManager.default.contentsOfDirectory(
            at: fontsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for font in fonts where font.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
    }

    public static func mono(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name = weight == .bold ? boldName : regularName
        return NSFont(name: name, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Aileye göre terminal fontu çözer. Boş aile → bundle'daki JetBrains Mono
    /// (`mono(size:weight:)`). Dolu aile NSFontManager üzerinden çözülmeye çalışılır;
    /// çözülemezse JetBrains Mono fallback'ine düşer (asla sistem default'una değil —
    /// monospace garantisi için).
    public static func mono(
        family: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSFont {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return mono(size: size, weight: weight)
        }
        let traits: NSFontTraitMask = weight == .bold ? .boldFontMask : []
        if let resolved = NSFontManager.shared.font(
            withFamily: trimmed,
            traits: traits,
            weight: Self.fontManagerNormalWeight,
            size: size
        ) {
            return resolved
        }
        // Bilinmeyen aile → JetBrains Mono (monospace garantisini korur)
        return mono(size: size, weight: weight)
    }

    /// NSFontManager'ın 0–15 ağırlık ölçeğinde "normal" (regular) değeri.
    private static let fontManagerNormalWeight = 5

    /// Settings font ailesi picker'ı için sistemdeki sabit-genişlikli (monospace)
    /// aileler. Bir kere hesaplanır (availableFontFamilies + fixed-pitch süzgeci).
    public static let availableMonospaceFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let descriptors = NSFontManager.shared
                .availableMembers(ofFontFamily: family), !descriptors.isEmpty else {
                return false
            }
            guard let font = NSFont(name: family, size: 12)
                ?? (descriptors.first?.first as? String).flatMap({ NSFont(name: $0, size: 12) })
            else {
                return false
            }
            return font.isFixedPitch
        }.sorted()
    }()
}

/// Bundle'lı görseller (header logosu vb.). UI'dan (MainActor) erişilir.
@MainActor
public enum LumiAssets {
    /// Header app logosu (v1 mascot app-icon paritesi). Kayıt başarısızsa nil.
    public static let logo: NSImage? = {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}
