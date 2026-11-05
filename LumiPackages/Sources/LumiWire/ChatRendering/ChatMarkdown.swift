import Foundation

/// Chat text split into prose and fenced code blocks (``` … ```).
public enum ChatMarkdownSegment: Sendable, Equatable {
    case prose(String)
    case code(language: String?, body: String)
}

/// Splits on lines starting with ```. An unterminated fence (streaming) is
/// still a code block. Empty prose between blocks is dropped.
public func chatMarkdownSegments(_ text: String) -> [ChatMarkdownSegment] {
    var result: [ChatMarkdownSegment] = []
    var prose: [Substring] = []
    var code: [Substring]? = nil
    var language: String? = nil

    func flushProse() {
        let joined = prose.joined(separator: "\n")
        if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.prose(joined)) }
        prose.removeAll()
    }

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.drop(while: { $0 == " " })
        if trimmed.hasPrefix("```") {
            if let body = code {
                result.append(.code(language: language, body: body.joined(separator: "\n")))
                code = nil; language = nil
            } else {
                flushProse()
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                language = lang.isEmpty ? nil : lang
                code = []
            }
        } else if code != nil {
            code!.append(line)
        } else {
            prose.append(line)
        }
    }
    if let body = code { result.append(.code(language: language, body: body.joined(separator: "\n"))) }
    flushProse()
    return result
}

/// Inline markdown (bold/italic/`code`/links) with whitespace preserved. Inline
/// code runs keep `.code` in `inlinePresentationIntent` for the view to tint.
public func chatInlineAttributed(_ prose: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: prose, options: options)) ?? AttributedString(prose)
}
