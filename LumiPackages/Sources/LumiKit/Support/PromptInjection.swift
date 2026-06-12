/// Prompt'u bir terminale "yapıştırılmış girdi" olarak güvenle enjekte etmek için
/// bracketed-paste kodlayıcı (DECSET 2004). Çok satırlı prompt'ta aradaki
/// newline'lar erken submit'e yol açmasın diye metin paste sınırları içine
/// alınır; submit yalnız sondaki tek CR ile yapılır.
///
/// Claude Code bracketed-paste'i etkinleştirdiğinden, PTY'ye doğrudan yazarken
/// emülatörün paste-sarmalamasını biz taklit ederiz.
public enum PromptInjection {
    public static let pasteStart = "\u{1B}[200~"
    public static let pasteEnd = "\u{1B}[201~"
    public static let submit = "\r"

    public static func encode(_ prompt: String) -> String {
        // Sondaki newline'ları kırp: submit'i tek CR yönetir, çift-submit olmaz.
        var text = prompt
        while text.hasSuffix("\n") || text.hasSuffix("\r") {
            text.removeLast()
        }
        return pasteStart + text + pasteEnd + submit
    }
}
