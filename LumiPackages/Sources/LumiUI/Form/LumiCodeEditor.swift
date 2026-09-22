import AppKit
import SwiftUI

/// Düzenlenebilir, monospace kod alanı (karar 92 — hızlı komut script'i).
///
/// SwiftUI `TextEditor` macOS'ta sistemin metin ikamelerini uygular: `"`
/// akıllı tırnağa, `--` uzun tireye döner ve shell script'i sessizce bozulur.
/// Bu yüzden ikameleri ve otomatik düzeltmeleri kapalı bir `NSTextView`
/// sarılır. Zemin/kenarlık `LumiTextInput` ile aynı dili konuşur.
struct LumiCodeEditor: View {
    @Binding var text: String
    var isEditable = true

    var body: some View {
        CodeTextView(text: $text, isEditable: isEditable)
            .background(Theme.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
            )
    }
}

private struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textColor = Theme.NS.textPrimary
        textView.insertionPointColor = Theme.NS.textPrimary
        textView.textContainerInset = NSSize(width: Theme.Spacing.md, height: Theme.Spacing.md)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Binding taslak seçimine bağlıdır; eskisini tutmak yazımı yanlış
        // taslağa yönlendirirdi.
        context.coordinator.text = $text
        textView.isEditable = isEditable
        textView.font = Self.font
        // Dışarıdan gelen değişiklik (Claude yanıtı, başka taslağa geçiş);
        // kullanıcının kendi yazdığı metni geri basmak imleci sıfırlardı.
        if textView.string != text {
            textView.string = text
        }
    }

    private static var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: Theme.Typography.Size.body.scaledPoints, weight: .regular)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

#if DEBUG
#Preview("LumiCodeEditor") {
    LumiCodeEditor(text: .constant("cd \"{path}\"\nmake build\n"))
        .frame(width: 420, height: 160)
        .padding(Theme.Spacing.xxl)
        .background(Theme.bgSurface)
}
#endif
