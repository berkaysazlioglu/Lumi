import AppKit
import LumiKit
import SwiftUI

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
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    public func updateNSView(_ container: NSView, context: Context) {
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
