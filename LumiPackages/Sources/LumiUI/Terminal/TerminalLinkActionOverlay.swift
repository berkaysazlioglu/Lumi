import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Popover'ın kabuk içindeki yerleşimi (karar 57) — saf hesap.
///
/// Varsayılan yer tık noktasının ÜSTÜDÜR: terminalde yeni
/// çıktı aşağıdan geldiği için tıklanan satırın altındaki bağlamı kapatmak
/// daha rahatsız ediciydi. Üste sığmazsa alta iner, sağa taşarsa sola çekilir.
enum TerminalLinkPopoverPlacement {
    static let gap = Theme.Spacing.md

    static func origin(anchor: CGPoint, popoverSize: CGSize, container: CGSize) -> CGPoint {
        let maxX = max(gap, container.width - popoverSize.width - gap)
        let x = min(max(gap, anchor.x), maxX)
        let above = anchor.y - gap - popoverSize.height
        let fitsAbove = above >= gap
        let y = fitsAbove ? above : anchor.y + gap
        let maxY = max(gap, container.height - popoverSize.height - gap)
        return CGPoint(x: x, y: min(max(gap, y), maxY))
    }
}

/// Açık link eylemi popover'ını tık noktasında çizen overlay (karar 57).
///
/// Popover **modal değildir**: dışarıdaki tık popover'ı kapatır ama YUTULMAZ,
/// hedefine de ulaşır (başka bir terminale geçmek tek tık; path üstünde çift
/// tıkla kelime seçimi bozulmaz). Esc de terminale sızmadan burada tüketilir.
/// Kapanışta klavye odağı terminale geri verilir.
public struct TerminalLinkActionOverlay: View {
    @Shell private var shell
    /// `nil` → henüz ölçülmedi; ilk kare tahmini boyutla yerleşir. Eskiden
    /// ölçüm gelene kadar `opacity 0` çiziliyordu — ölçüm bir sebeple gelmezse
    /// popover GÖRÜNMEZ ama tıklanabilir kalıyordu.
    @State private var popoverSize: CGSize?

    public init() {}

    private struct SizeKey: PreferenceKey {
        static let defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }

    public var body: some View {
        if let request = shell.terminalLinks.request {
            GeometryReader { geometry in
                let size = popoverSize ?? TerminalLinkActionPopover.estimatedSize(for: request)
                let origin = TerminalLinkPopoverPlacement.origin(
                    anchor: request.anchor,
                    popoverSize: size,
                    container: geometry.size
                )
                ZStack(alignment: .topLeading) {
                    TerminalLinkDismissCatcher(
                        popoverFrame: CGRect(origin: origin, size: size),
                        containerHeight: geometry.size.height,
                        onDismiss: { close(request) }
                    )
                    TerminalLinkActionPopover(
                        request: request,
                        onRun: { run($0, in: request) },
                        onCopy: { copy(request) },
                        onOpenSettings: {
                            close(request)
                            shell.dialogs.openSettings(tab: SettingsTab.terminal.rawValue)
                        }
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: SizeKey.self, value: proxy.size)
                        }
                    )
                    .offset(x: origin.x, y: origin.y)
                }
                .onPreferenceChange(SizeKey.self) { measured in
                    guard measured.height > 0 else { return }
                    Task { @MainActor in popoverSize = measured }
                }
            }
            .id(request.id)
        }
    }

    private func run(_ action: TerminalLinkAction, in request: TerminalLinkRequest) {
        shell.terminalLinks.perform(action)
        focusTerminal(request)
    }

    private func close(_ request: TerminalLinkRequest) {
        shell.terminalLinks.dismiss()
        focusTerminal(request)
    }

    /// Klavye odağı popover'a hiç gitmez ama kapanışta terminali açıkça
    /// odaklamak, kullanıcının yazmaya devam etmek için tekrar tıklamasını
    /// önler.
    private func focusTerminal(_ request: TerminalLinkRequest) {
        shell.terminals.focus(request.terminalID)
    }

    private func copy(_ request: TerminalLinkRequest) {
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(request.destination, forType: .string)
        close(request)
        if copied {
            shell.toasts.show(.info, title: "Copied", message: request.destination)
        } else {
            shell.toasts.show(.error, title: "Copy failed", message: request.destination)
        }
    }
}

/// Dışarı tık + Esc yakalayıcı.
///
/// SwiftUI'nin `onTapGesture`'ı tıkı YUTARDI; burada yalnız bir local event
/// monitor dinlenir ve olay olduğu gibi akmaya devam eder — terminal kendi
/// tıkını (caret, seçim, çift tık) görür. Esc ise tüketilir: aksi hâlde hem
/// popover açık kalır hem ajana `ESC` giderdi.
private struct TerminalLinkDismissCatcher: NSViewRepresentable {
    let popoverFrame: CGRect
    let containerHeight: CGFloat
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            popoverFrame: popoverFrame, containerHeight: containerHeight, onDismiss: onDismiss
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(popoverFrame: popoverFrame, containerHeight: containerHeight, onDismiss: onDismiss)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private var popoverFrame: CGRect
        private var containerHeight: CGFloat
        private var onDismiss: () -> Void
        private var monitor: Any?

        fileprivate static let escapeKeyCode: UInt16 = 53

        init(popoverFrame: CGRect, containerHeight: CGFloat, onDismiss: @escaping () -> Void) {
            self.popoverFrame = popoverFrame
            self.containerHeight = containerHeight
            self.onDismiss = onDismiss
        }

        func update(popoverFrame: CGRect, containerHeight: CGFloat, onDismiss: @escaping () -> Void) {
            self.popoverFrame = popoverFrame
            self.containerHeight = containerHeight
            self.onDismiss = onDismiss
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] event in
                guard Thread.isMainThread else { return event }
                // NSEvent Sendable değil: izolasyon sınırından yalnız Bool taşınır
                // (`TerminalEventMonitor` ile aynı desen).
                let isKeyDown = event.type == .keyDown
                // `keyCode` YALNIZ key event'lerinde geçerlidir; fare olayında
                // okumak ObjC istisnası fırlatıp event dağıtımını kilitliyordu
                // (uygulama hiçbir girdi almıyordu).
                let isEscape = isKeyDown && event.keyCode == Self.escapeKeyCode
                let insidePopover = MainActor.assumeIsolated {
                    self?.isInsidePopover(event) ?? true
                }
                let consumed = MainActor.assumeIsolated {
                    self?.handle(isKeyDown: isKeyDown, isEscape: isEscape, insidePopover: insidePopover)
                        ?? false
                }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// `true` → olay yutuldu. YALNIZ Esc yutulur; dışarıdaki tık popover'ı
        /// kapatır ama hedefine (terminale) ulaşmaya devam eder.
        fileprivate func handle(isKeyDown: Bool, isEscape: Bool, insidePopover: Bool) -> Bool {
            if isKeyDown {
                guard isEscape else { return false }
                onDismiss()
                return true
            }
            guard !insidePopover else { return false }
            onDismiss()
            return false
        }

        /// Popover'ın kendi butonlarına inen tık kapatma sayılmaz (buton zaten
        /// kendi eylemini çalıştırıp kapatır).
        fileprivate func isInsidePopover(_ event: NSEvent) -> Bool {
            guard let window = event.window else { return false }
            let point = event.locationInWindow
            let shellPoint = TerminalLinkAnchor.shellPoint(
                windowPoint: point,
                contentHeight: window.contentView?.bounds.height ?? containerHeight
            )
            return popoverFrame.contains(shellPoint)
        }
    }
}
