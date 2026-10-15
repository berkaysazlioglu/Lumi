import Foundation

/// Terminaldeki bir link/path'e yapılan tıklamanın anlamı (karar 57). Üç jest dışındaki her tık terminale aittir (seçim, ctrl-tık
/// bağlam menüsü, option'lı blok seçimi) ve buraya hiç uğramaz.
public enum TerminalLinkGesture: String, Sendable, Equatable, CaseIterable {
    /// Düz sol tık → eylem popover'ı açılır.
    case actions
    /// ⌘ + tık → birincil eylem doğrudan çalışır.
    case primary
    /// ⇧⌘ + tık → alternatif eylem doğrudan çalışır.
    case alternate

    /// Tık anındaki modifier durumu (NSEvent'ten bağımsız, saf girdi).
    public struct Modifiers: Sendable, Equatable {
        public var command: Bool
        public var shift: Bool
        public var option: Bool
        public var control: Bool

        public init(command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
            self.command = command
            self.shift = shift
            self.option = option
            self.control = control
        }
    }

    /// `nil` → jest terminale aittir, link yolu hiç işletilmez.
    ///
    /// Shift TEK başına seçim genişletmedir (SwiftTerm `shiftExtend`), ctrl-tık
    /// bağlam menüsüdür, option blok seçimidir; çift tık kelime seçimidir.
    public static func resolve(
        isLeftButton: Bool,
        clickCount: Int,
        modifiers: Modifiers
    ) -> TerminalLinkGesture? {
        guard isLeftButton, clickCount == 1, !modifiers.option, !modifiers.control else { return nil }
        if modifiers.command { return modifiers.shift ? .alternate : .primary }
        return modifiers.shift ? nil : .actions
    }
}

/// Terminalden yukarı akan link tıklaması: ham link metni + jest + tık noktası.
/// Hedefin ne olduğu (URL / workspace / dizin / dosya) burada ÇÖZÜLMEZ — o
/// karar repo ve workspace kayıtlarını gören state katmanına aittir.
public struct TerminalLinkActivation: Sendable, Equatable {
    public let terminalID: TerminalID
    /// Emülatörün eşlediği ham metin (OSC 8 payload'ı ya da örtük eşleşme).
    public let link: String
    public let gesture: TerminalLinkGesture
    /// Kabuk (SwiftUI) koordinat uzayında, pencerenin SOL-ÜSTÜNE göre tık noktası.
    public let anchor: CGPoint

    public init(terminalID: TerminalID, link: String, gesture: TerminalLinkGesture, anchor: CGPoint) {
        self.terminalID = terminalID
        self.link = link
        self.gesture = gesture
        self.anchor = anchor
    }
}

/// AppKit pencere koordinatı (sol-ALT orijin) → kabuk koordinatı (sol-üst).
/// Lumi'de pencere içeriği tam boy `contentView`'dır (36px top bar dahil kabuk
/// SwiftUI'da çizilir), yani içerik yüksekliği kabuk yüksekliğiyle aynıdır.
public enum TerminalLinkAnchor {
    public static func shellPoint(windowPoint: CGPoint, contentHeight: CGFloat) -> CGPoint {
        CGPoint(x: windowPoint.x, y: contentHeight - windowPoint.y)
    }
}

/// xterm fare raporu tanıyıcısı: düz tıkta rapor PTY'ye GİTMEDEN bekletilir;
/// tık bir eylem popover'ına dönüşürse düşürülür, dönüşmezse olduğu gibi akar
/// Yalnız fare
/// raporları bekletilir — klavye girdisi asla gecikmez.
public enum TerminalMouseReport {
    private static let escape: UInt8 = 0x1B
    private static let bracket: UInt8 = 0x5B // [

    /// Dört kodlama da tanınır — tanınmayan bir kodlama bekletilmeyip PTY'ye
    /// akardı ve tık hem popover'ı açıp hem TUI'ye ulaşırdı (çift etki):
    /// X10/UTF-8 (`ESC [ M` + 3…12 bayt), SGR (`ESC [ < a;b;c M|m`),
    /// urxvt (`ESC [ a;b;c M`).
    public static func isReport(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes[0] == escape, bytes[1] == bracket else { return false }
        if bytes[2] == UInt8(ascii: "M"), bytes.count > 3 {
            // X10 üç bayt; UTF-8 (1005) kipinde her koordinat 2 bayta kadar çıkar.
            return bytes.count >= 6 && bytes.count <= 12
        }
        let hasSGRPrefix = bytes[2] == UInt8(ascii: "<")
        let bodyStart = hasSGRPrefix ? 3 : 2
        guard bytes.count >= bodyStart + 4 else { return false }
        let last = bytes[bytes.count - 1]
        // urxvt (1015) yalnız `M` ile biter; SGR (1006) basma/bırakmayı M/m ayırır.
        guard last == UInt8(ascii: "M") || (hasSGRPrefix && last == UInt8(ascii: "m")) else {
            return false
        }
        return hasThreeNumericGroups(bytes[bodyStart ..< (bytes.count - 1)])
    }

    private static func hasThreeNumericGroups(_ body: ArraySlice<UInt8>) -> Bool {
        var digitsInGroup = 0
        var groups = 1
        for byte in body {
            if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                digitsInGroup += 1
            } else if byte == UInt8(ascii: ";") {
                guard digitsInGroup > 0 else { return false }
                digitsInGroup = 0
                groups += 1
            } else {
                return false
            }
        }
        return groups == 3 && digitsInGroup > 0
    }
}

/// Tek tıkla ÇALIŞTIRILABİLECEK dosya türleri (karar 57 sertleştirmesi).
///
/// `NSWorkspace.open` bir `.command`/`.scpt`/`.pkg` dosyasını açmaz — ÇALIŞTIRIR.
/// Terminale basılan metin güvenilmez bir kaynaktır (kötü niyetli bir repo'nun
/// build çıktısı da olabilir), bu yüzden bu türlerde "varsayılan uygulamada aç"
/// hiç önerilmez; kullanıcı Finder'da görür ve kendi karar verir.
public enum TerminalLinkSafety {
    public static let executableExtensions: Set<String> = [
        "app", "action", "applescript", "bash", "command", "dmg", "fish", "jar",
        "mpkg", "pkg", "scpt", "scptd", "sh", "shortcut", "terminal", "workflow", "zsh",
    ]

    public static func isExecutable(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return !ext.isEmpty && executableExtensions.contains(ext)
    }
}
