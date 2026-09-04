/// OSC 0/2 title payload'ının ajandan bağımsız yorumu (Electron paritesi).
/// Semantik implementasyonları bu saf yardımcıyı paylaşır (DRY).
enum OSCTitleInterpreter {
    /// Title taşıyan OSC kodları.
    static let titleCodes: Set<Int> = [0, 2]

    /// ✳ (U+2733) = Claude idle işareti.
    static let idleMarkScalar: Unicode.Scalar = "\u{2733}"

    static func hasIdleMark(_ raw: String) -> Bool {
        raw.unicodeScalars.first == idleMarkScalar
    }

    /// ✳ prefix → false (idle); boş title → nil (karar yok); aksi → true.
    static func isWorking(_ raw: String) -> Bool? {
        if hasIdleMark(raw) { return false }
        return raw.isEmpty ? nil : true
    }

    /// `/^.\s*/` paritesi: ilk karakter körlemesine atılır (✳/spinner ikonu
    /// hedeflenir, ikonsuz title'ın ilk harfi de gider — bilinen trade-off).
    static func stripLeadingIconAndWhitespace(_ string: String) -> String {
        guard !string.isEmpty else { return "" }
        var rest = string.dropFirst()
        while let first = rest.first, first.isWhitespace {
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    static func event(raw: String, hint: AgentHint?) -> OSCTitleEvent {
        let display = stripLeadingIconAndWhitespace(raw)
        return OSCTitleEvent(
            rawTitle: raw,
            displayTitle: display.isEmpty ? nil : display,
            isWorking: isWorking(raw),
            providerHint: hint
        )
    }
}
