import Foundation

/// PTY'den gelen ham byte chunk'larını, chunk sınırında bölünen çok-byte'lı
/// UTF-8 karakterleri taşıyarak String'e çevirir (spec/10 "byte vs string sınırı").
/// ✳ (U+2733) 3 byte'tır; bölünmesi OSC parser ve idle tespitini bozar.
struct UTF8StreamDecoder {
    private var carry: [UInt8] = []

    mutating func decode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        let bytes: [UInt8] = carry.isEmpty ? [UInt8](data) : carry + [UInt8](data)
        carry = []
        let cut = Self.completePrefixLength(of: bytes)
        if cut < bytes.count {
            carry = Array(bytes[cut...])
        }
        guard cut > 0 else { return "" }
        return String(decoding: bytes[..<cut], as: UTF8.self)
    }

    /// Sonu eksik bir çok-byte sequence ile bitiyorsa, o sequence'in başlangıcına
    /// kadar olan uzunluğu döner; aksi halde tüm buffer decode edilebilir.
    static func completePrefixLength(of bytes: [UInt8]) -> Int {
        let count = bytes.count
        guard count > 0 else { return 0 }
        var index = count - 1
        let lowerBound = max(0, count - 4)
        while index >= lowerBound {
            let byte = bytes[index]
            if byte < 0x80 { return count }
            if byte & 0xC0 == 0xC0 {
                let expected = expectedLength(lead: byte)
                if expected == 0 { return count }
                return (count - index) >= expected ? count : index
            }
            index -= 1
        }
        // 4+ ardışık continuation byte'ı: geçersiz dizi; decoder U+FFFD üretir.
        return count
    }

    static func expectedLength(lead: UInt8) -> Int {
        switch lead {
        case 0xC2...0xDF: return 2
        case 0xE0...0xEF: return 3
        case 0xF0...0xF4: return 4
        default: return 0
        }
    }
}
