import AppKit
import LumiState
import SwiftUI

/// Uzak chat'in mesaj kutusu (karar 143 ek).
///
/// SwiftUI'nin dikey `TextField`'ı yerine sarılmış bir `NSTextView`: ↩ gönderir, ⇧↩ / ⌥↩
/// alt satıra iner, ⌘A tümünü seçer, yapıştırma düz metindir ve çok satırlı yapıştırma
/// anında yerleşir (dikey `TextField` her satırda yeniden ölçüldüğü için birkaç satırlık
/// yapıştırmada saniyelerce donuyordu). Taslak oturumda durur
/// (`RemoteChatSession.composerDraft`) — terminaller arasında gidip gelince kaybolmaz —
/// ve yalnız bu görünüm okur: tuş vuruşu mesaj listesini yeniden çizdirmez.
struct RemoteChatComposer: View {
    let chat: RemoteChatSession
    let style: RemoteChatStyle
    /// Gönderimden sonra (liste dibe dönsün diye).
    var onSend: () -> Void = {}

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
            ZStack(alignment: .topLeading) {
                ComposerTextView(
                    text: Binding(get: { chat.composerDraft }, set: { chat.composerDraft = $0 }),
                    font: style.nsFont(),
                    maxLines: Self.maxLines,
                    onSubmit: submit,
                    onEscape: interrupt)
                    .fixedSize(horizontal: false, vertical: true)
                if chat.composerDraft.isEmpty {
                    Text("Message Claude…  (⇧↩ new line, Esc to interrupt)")
                        .font(style.font())
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            IconButton(systemName: "arrow.up", label: "Send", size: .body, side: Theme.Row.control) { submit() }
                .disabled(!canSend)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.bgSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
        }
    }

    private var canSend: Bool {
        !chat.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSend else { return }
        chat.send(chat.composerDraft)
        chat.composerDraft = ""
        onSend()
    }

    /// Esc yalnız koşan turn'ü keser; boştayken tuş sisteme kalır.
    private func interrupt() -> Bool {
        guard chat.status.working else { return false }
        chat.interrupt()
        return true
    }

    private static let maxLines = 8
}

// MARK: - NSTextView sarmalayıcı

/// Kendi yüksekliğini (1…`maxLines` satır) bildiren, odağı görünür olunca alan metin kutusu.
private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let maxLines: Int
    let onSubmit: () -> Void
    let onEscape: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> ComposerScrollView {
        let scrollView = ComposerScrollView(maxLines: maxLines)
        let textView = scrollView.textView
        textView.delegate = context.coordinator
        textView.font = font
        textView.string = text
        scrollView.focusWhenShown = true
        return scrollView
    }

    func updateNSView(_ scrollView: ComposerScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = scrollView.textView
        if textView.font != font {
            textView.font = font
            scrollView.invalidateIntrinsicContentSize()
        }
        // Gönderim taslağı boşaltır; yazım sırasında metin zaten aynıdır.
        guard textView.string != text, !textView.hasMarkedText() else { return }
        textView.string = text
        scrollView.invalidateIntrinsicContentSize()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            (textView.enclosingScrollView as? ComposerScrollView)?.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // ⇧↩ alt satır; düz ↩ gönderir (⌥↩ zaten `insertNewlineIgnoringFieldEditor`).
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onEscape()
            default:
                return false
            }
        }
    }
}

/// `NSTextView`'ı taşıyan kaydırma kabı. Yüksekliği içeriğe göre büyür, `maxLines`'tan
/// sonra kayar; SwiftUI `fixedSize(vertical:)` ile `intrinsicContentSize`'ı okur.
private final class ComposerScrollView: NSScrollView {
    let textView: NSTextView
    let maxLines: Int
    /// Pencereye ilk girişte odağı al (chat açılınca doğrudan yazılabilsin).
    var focusWhenShown = false
    private var lastHeight: CGFloat = 0

    init(maxLines: Int) {
        self.maxLines = maxLines
        // TextKit 1: `layoutManager` ölçümü TextKit 2'yi sessizce geri düşürürdü.
        textView = NSTextView(usingTextLayoutManager: false)
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        configureTextView()
        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureTextView() {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textColor = Theme.NS.textPrimary
        textView.insertionPointColor = Theme.NS.textPrimary
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fittingTextHeight)
    }

    /// Metnin bu genişlikteki yüksekliği, 1…`maxLines` satıra kırpılmış.
    private var fittingTextHeight: CGFloat {
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: NSFont.systemFontSize))
            ?? NSFont.systemFontSize
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return lineHeight
        }
        layoutManager.ensureLayout(for: container)
        let used = ceil(layoutManager.usedRect(for: container).height)
        return min(max(used, lineHeight), lineHeight * CGFloat(maxLines))
    }

    override func layout() {
        super.layout()
        // Genişlik değişince satır kırılımı ve dolayısıyla yükseklik değişir.
        let height = fittingTextHeight
        if height != lastHeight {
            lastHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusWhenShown, window != nil else { return }
        focusWhenShown = false
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.textView)
        }
    }
}
