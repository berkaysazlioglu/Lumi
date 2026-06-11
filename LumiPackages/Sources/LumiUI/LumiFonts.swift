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
}
