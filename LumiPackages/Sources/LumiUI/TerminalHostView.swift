import AppKit
import LumiKit
import SwiftUI

/// Host container'ı: registry'nin taktığı terminal view'ını **deterministik**
/// olarak kendi bounds'una sabitler. autoresizingMask yerine `setFrameSize`/
/// `layout` override'ı kullanılır çünkü bunlar AppKit tarafından her boyut
/// değişiminden — fullscreen geçişi, maximize↔grid round-trip, pencere resize —
/// SONRA, layout yerleştiğinde kesin çağrılır. SwiftUI'nin `updateNSView`
/// zamanlamasına (bayat container.bounds yarışı) bağlı kalmaz; frame değişince
/// SwiftTerm cols/rows'u yeniden hesaplar → sizeChanged → PTY resize → SIGWINCH.
final class TerminalHostContainer: NSView {
    /// Hangi terminale ait olduğu — kendi view'ını geri çekebilmek için (reassert).
    var terminalID: TerminalID?
    weak var provider: (any TerminalViewProviding)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reassertAttachment()
        pinTerminalView()
    }

    override func layout() {
        super.layout()
        reassertAttachment()
        pinTerminalView()
    }

    /// Reparenting yarışına karşı kendini onarır: maximize↔grid round-trip'inde
    /// ölmekte olan host paylaşılan view'ı öksüz bırakabiliyor. Hayatta kalan
    /// (layout olan) container, her layout'ta terminalini yeniden claim eder —
    /// attachView zaten bağlıysa no-op, öksüz/başka container'daysa geri çeker.
    private func reassertAttachment() {
        guard let terminalID, let provider else { return }
        MainActor.assumeIsolated {
            provider.attachView(for: terminalID, into: self)
        }
    }

    /// Tek subview (terminal emülatörü) bounds'a oturtulur; gerçek delta varsa
    /// redraw da işaretlenir (geçiş sonrası bayat/boş kart onarımı).
    private func pinTerminalView() {
        guard !bounds.isEmpty else { return } // layout öncesi 0×0'a pinleme
        guard let terminalView = subviews.first else { return }
        guard !terminalView.frame.equalTo(bounds) else { return }
        terminalView.frame = bounds
        terminalView.needsDisplay = true
    }
}

/// Canlı terminal NSView'ını SwiftUI'a köprüleyen host (design/03 §3 — yük taşıyan desen).
/// View'ın sahibi registry'dir; burada yalnız reparent edilir. SwiftUI bu container'ı
/// yıksa bile emülatör view'ı ve state'i registry'de yaşamaya devam eder.
public struct TerminalHostView: NSViewRepresentable {
    private let terminalID: TerminalID
    private let provider: any TerminalViewProviding

    public init(terminalID: TerminalID, provider: any TerminalViewProviding) {
        self.terminalID = terminalID
        self.provider = provider
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(terminalID: terminalID, provider: provider)
    }

    public func makeNSView(context: Context) -> NSView {
        let container = TerminalHostContainer()
        container.wantsLayer = true
        return container
    }

    public func updateNSView(_ container: NSView, context: Context) {
        // Container'ın kendini onarabilmesi için sahipliğini bildir (reassert).
        if let host = container as? TerminalHostContainer {
            host.terminalID = terminalID
            host.provider = provider
        }
        context.coordinator.attach(into: container)
    }

    public static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.detach(from: container)
    }

    @MainActor
    public final class Coordinator {
        private let terminalID: TerminalID
        private let provider: any TerminalViewProviding

        init(terminalID: TerminalID, provider: any TerminalViewProviding) {
            self.terminalID = terminalID
            self.provider = provider
        }

        func attach(into container: NSView) {
            provider.attachView(for: terminalID, into: container)
        }

        func detach(from container: NSView) {
            provider.detachView(for: terminalID, from: container)
        }
    }
}
