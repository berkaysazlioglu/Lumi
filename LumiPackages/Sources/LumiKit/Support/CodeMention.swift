import Foundation

/// FileViewer seçiminden ajan prompt'una giden referans (karar 100).
///
/// Claude Code'un IDE entegrasyonunun ürettiği biçim kullanılır:
/// `@<göreli yol>#L<başlangıç>-<bitiş>` (tek satırda `#L<n>`). Referans
/// terminale gönderilmeden YAPIŞTIRILIR — kullanıcı sorusunu yanına yazar.
public enum CodeMention {
    /// Seçimin kapsadığı 1 tabanlı satır aralığı; boş seçimde `nil`.
    ///
    /// Seçim bir satır sonunun hemen ardında bitiyorsa (satırı tam seçip
    /// aşağı sürüklemek) o boş satır aralığa katılmaz.
    public static func lineRange(in text: String, selection: NSRange) -> ClosedRange<Int>? {
        let utf16 = text as NSString
        guard selection.location != NSNotFound, selection.length > 0,
              NSMaxRange(selection) <= utf16.length else { return nil }
        let start = lineNumber(in: utf16, at: selection.location)
        var endLocation = NSMaxRange(selection)
        if endLocation > selection.location,
           isNewline(utf16.character(at: endLocation - 1)) {
            endLocation -= 1
        }
        let end = max(start, lineNumber(in: utf16, at: endLocation))
        return start...end
    }

    /// `@path#L5-9 ` — sondaki boşluk, kullanıcının yazmaya hemen devam
    /// edebilmesi içindir. Yol repo'ya göreli yazılır (ajanın cwd'si checkout).
    public static func reference(filePath: String, repoPath: String, lines: ClosedRange<Int>) -> String {
        let path = relativePath(filePath, in: repoPath)
        let suffix = lines.lowerBound == lines.upperBound
            ? "#L\(lines.lowerBound)"
            : "#L\(lines.lowerBound)-\(lines.upperBound)"
        return "@\(path)\(suffix) "
    }

    static func relativePath(_ filePath: String, in repoPath: String) -> String {
        let root = repoPath.hasSuffix("/") ? repoPath : repoPath + "/"
        guard filePath.hasPrefix(root) else { return filePath }
        return String(filePath.dropFirst(root.count))
    }

    /// Konumdan önceki satır sonu sayısı + 1. UTF-8 sayımı NSString'in
    /// karakter karakter erişiminden belirgin hızlıdır (seçim sürüklenirken
    /// her olayda koşar).
    private static func lineNumber(in text: NSString, at location: Int) -> Int {
        text.substring(to: location).utf8.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    private static let newline: unichar = 0x0A

    private static func isNewline(_ character: unichar) -> Bool {
        character == newline
    }
}
