import Foundation

/// PTY'ye giden yolda protokol-bilinçli girdi filtresi (spec/00 §4.2-9, spec/10 §7).
///
/// Focus event'leri (`ESC[I` / `ESC[O`) KOŞULSUZ ayıklanır: agent CLI'leri mode 1004
/// açtığında focus-out spinner/title güncellemesini durdurur; focus'u StatusStateMachine
/// yönettiği için CLI daima "focused" bilmelidir.
///
/// Tarama chunk içidir: her yazım kaynağı (klavye event'i, SwiftTerm oto-yanıtı,
/// ActionEngine step'i) tam sequence yazar; ESC'i sonraki chunk'ı bekletmek gerçek
/// ESC tuşunu geciktirirdi (design/01 §4).
struct PTYInputFilter {
    /// Defense-in-depth kapısı (spec/00 §4.2-9): canlı-olmayan feed senaryoları için;
    /// normal akışta hiç açılmaz. Açıkken CPR/DA/DECRPM/mouse-report biçimli
    /// emülatör yanıtları da düşürülür.
    var suppressResponses = false

    func filter(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x1B, index + 2 < bytes.count, bytes[index + 1] == 0x5B {
                let third = bytes[index + 2]
                if third == UInt8(ascii: "I") || third == UInt8(ascii: "O") {
                    index += 3
                    continue
                }
                if suppressResponses, let length = Self.responseLength(bytes, at: index) {
                    index += length
                    continue
                }
            }
            out.append(bytes[index])
            index += 1
        }
        return Data(out)
    }

    /// `start`'taki ESC[ ile başlayan dizi bir emülatör yanıtıysa (CPR `R`, DA `c`,
    /// DECRPM `$y`, SGR mouse `<...M/m`, legacy mouse `M`) toplam uzunluğunu döner.
    static func responseLength(_ bytes: [UInt8], at start: Int) -> Int? {
        var index = start + 2
        guard index < bytes.count else { return nil }

        if bytes[index] == UInt8(ascii: "M") {
            // Legacy mouse raporu: ESC [ M cb cx cy
            return index + 3 < bytes.count ? 6 : nil
        }

        let paramStart = index
        var sawDollar = false
        while index < bytes.count, (0x30...0x3F).contains(bytes[index]) {
            index += 1
        }
        while index < bytes.count, (0x20...0x2F).contains(bytes[index]) {
            if bytes[index] == UInt8(ascii: "$") { sawDollar = true }
            index += 1
        }
        guard index < bytes.count, (0x40...0x7E).contains(bytes[index]) else { return nil }

        let final = bytes[index]
        let length = index - start + 1
        switch final {
        case UInt8(ascii: "R"), UInt8(ascii: "c"):
            return length
        case UInt8(ascii: "y"):
            return sawDollar ? length : nil
        case UInt8(ascii: "M"), UInt8(ascii: "m"):
            return paramStart < bytes.count && bytes[paramStart] == UInt8(ascii: "<") ? length : nil
        default:
            return nil
        }
    }
}
