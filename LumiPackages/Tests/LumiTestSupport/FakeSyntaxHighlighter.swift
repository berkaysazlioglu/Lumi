import AppKit
import Foundation
import LumiKit

/// Gerçek `HighlightrEngine`'i (JSCore) testlere sokmayan vurgulayıcı:
/// metni olduğu gibi, tek attribute run'ıyla döner.
@MainActor
public final class FakeSyntaxHighlighter: SyntaxHighlighting {
    public private(set) var requestedFileNames: [String] = []

    public init() {}

    public func highlight(
        code: String,
        fileName: String,
        fontSize: CGFloat
    ) async -> NSAttributedString {
        requestedFileNames.append(fileName)
        return NSAttributedString(string: code)
    }
}
