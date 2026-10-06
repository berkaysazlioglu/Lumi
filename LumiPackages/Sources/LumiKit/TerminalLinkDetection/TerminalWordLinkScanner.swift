import Foundation

/// Ayırıcısız dosya adları (`README.md`, `Package.swift:12`, `Makefile`) —
/// Orca `terminal-bare-file-link-detection` (VSCode `terminalWordLinkDetector`)
/// paritesi. Düzyazıyı stat'a gitmeden eler; kalan aday ancak terminalin
/// dizininde GERÇEKTEN varsa link olur.
enum TerminalBareFilenameScanner {
    private static let token = TerminalLinkText.regex(#"[^\s()\[\]{}'",;<>|`]+"#)
    private static let filename = TerminalLinkText.regex(#"^[A-Za-z0-9_][A-Za-z0-9._+-]*$"#)
    private static let digitsOnly = TerminalLinkText.regex(#"^\d+$"#)
    private static let dotsOnly = TerminalLinkText.regex(#"^\.+$"#)
    /// Tek parça dev bir blob hover'ı yavaşlatmasın.
    private static let maxTokenLength = 120
    private static let extensionlessNames: Set<String> = [
        "Makefile", "Dockerfile", "Rakefile", "Gemfile", "Procfile", "LICENSE",
        "README", "CHANGELOG", "AUTHORS", "NOTICE", "CONTRIBUTING",
    ]

    /// `claimed`: daha uzun bir linkin (yol, `file://`) zaten kapladığı aralıklar.
    static func links(in line: NSString, excluding claimed: [TerminalLinkTextRange]) -> [TerminalLinkTextRange] {
        TerminalLinkText.matches(token, in: line).compactMap { raw -> TerminalLinkTextRange? in
            guard raw.length <= maxTokenLength,
                  let range = TerminalLinkText.trimBoundaryPunctuation(raw),
                  !claimed.contains(where: range.overlaps),
                  let parsed = TerminalLinkText.parseLocation(range.text),
                  looksLikeFilename(parsed.path) else { return nil }
            return range
        }
    }

    private static func looksLikeFilename(_ name: String) -> Bool {
        let length = (name as NSString).length
        guard (2 ... 100).contains(length), TerminalLinkText.isMatch(filename, name) else { return false }
        guard !TerminalLinkText.isMatch(digitsOnly, name) else { return false }
        if name.contains(".") { return !TerminalLinkText.isMatch(dotsOnly, name) }
        return extensionlessNames.contains(name)
    }
}

/// Düz metindeki `file://` URI'leri (Orca `terminal-file-uri-link` paritesi).
/// Yalnız yerel (host'suz ya da `localhost`) URI'ler aday olur; yol çözümü
/// `TerminalLinkResolver`'dadır (OSC 8 `file:` payload'ı da aynı yoldan geçer).
enum TerminalFileURIScanner {
    private static let maxLength = 2048
    private static let fileURI = TerminalLinkText.regex(#"\bfile://[^\s"`<>|]{1,2049}"#, options: [.caseInsensitive])
    private static let trailingProse: Set<unichar> = Set(".,;:!?>\"'`".utf16)

    static func links(in line: NSString) -> [TerminalLinkTextRange] {
        TerminalLinkText.matches(fileURI, in: line).compactMap { match -> TerminalLinkTextRange? in
            guard match.length <= maxLength else { return nil }
            let trimmed = trimTrailingProse(match.text)
            guard !trimmed.isEmpty, TerminalLinkResolver.localFilePath(fromURI: trimmed) != nil else { return nil }
            return TerminalLinkTextRange(start: match.start, end: match.start + (trimmed as NSString).length, text: trimmed)
        }
    }

    /// Standart file URI'leri parantezi kodlamaz: kapanış ayracı yalnız
    /// DENGESİZSE (çevreleyen düzyazıdansa) kırpılır.
    private static func trimTrailingProse(_ uri: String) -> String {
        let text = uri as NSString
        var open: [unichar: Int] = [:]
        let pairs: [unichar: unichar] = [41: 40, 93: 91, 125: 123] // ) ( ] [ } {
        for index in 0 ..< text.length {
            let unit = text.character(at: index)
            if let opener = pairs[unit] { open[opener, default: 0] -= 1 }
            if pairs.values.contains(unit) { open[unit, default: 0] += 1 }
        }
        var end = text.length
        while end > 0 {
            let unit = text.character(at: end - 1)
            if trailingProse.contains(unit) {
                end -= 1
            } else if let opener = pairs[unit], open[opener, default: 0] < 0 {
                open[opener, default: 0] += 1
                end -= 1
            } else {
                break
            }
        }
        return text.substring(to: end)
    }
}
