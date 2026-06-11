import AppKit
import Foundation
import LumiKit

/// Tipli UnifiedDiff → renklendirilmiş NSAttributedString (karar 4: tek kolonlu
/// unified diff; gutter satır numaraları + ekleme/silme satır arka planları).
enum DiffAttributedTextBuilder {
    static func build(_ diff: UnifiedDiff, fontSize: CGFloat) -> NSAttributedString {
        let font = LumiFonts.mono(size: fontSize)

        if diff.isBinary {
            return NSAttributedString(string: "(binary file)", attributes: [
                .font: font, .foregroundColor: Theme.NS.textMuted,
            ])
        }
        if diff.hunks.isEmpty {
            return NSAttributedString(string: "(no changes)", attributes: [
                .font: font, .foregroundColor: Theme.NS.textMuted,
            ])
        }

        let output = NSMutableAttributedString()
        for (index, hunk) in diff.hunks.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: "\n"))
            }
            output.append(NSAttributedString(string: hunk.header + "\n", attributes: [
                .font: font,
                .foregroundColor: Theme.NS.cyan,
                .backgroundColor: Theme.NS.bgElevated,
            ]))
            for line in hunk.lines {
                output.append(render(line, font: font))
            }
        }
        return output
    }

    private static func render(_ line: DiffLine, font: NSFont) -> NSAttributedString {
        let gutter = pad(line.oldLineNumber) + " " + pad(line.newLineNumber) + " "

        let marker: String
        let textColor: NSColor
        let background: NSColor?
        switch line.kind {
        case .context:
            marker = "  "
            textColor = Theme.NS.textPrimary
            background = nil
        case .addition:
            marker = "+ "
            textColor = Theme.NS.success
            background = Theme.NS.additionBackground
        case .deletion:
            marker = "- "
            textColor = Theme.NS.error
            background = Theme.NS.deletionBackground
        }

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: gutter, attributes: [
            .font: font, .foregroundColor: Theme.NS.textMuted,
        ]))
        var bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: textColor,
        ]
        if let background {
            bodyAttributes[.backgroundColor] = background
        }
        result.append(NSAttributedString(string: marker + line.text + "\n", attributes: bodyAttributes))
        return result
    }

    private static func pad(_ number: Int?) -> String {
        let text = number.map(String.init) ?? ""
        return String(repeating: " ", count: max(0, 4 - text.count)) + text
    }
}
