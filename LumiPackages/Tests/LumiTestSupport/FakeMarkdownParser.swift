import LumiKit

/// Gerçek ayrıştırıcı (cmark-gfm) LumiServices'te; kabuk testleri yalnız
/// modelin akışını doğrular — her satır bir paragraf olur.
public struct FakeMarkdownParser: MarkdownParsing {
    public init() {}

    public func parse(_ text: String) -> MarkdownDocument {
        MarkdownDocument(blocks: text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { .paragraph([.text(String($0))]) })
    }
}
