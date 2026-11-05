import AppKit
import LumiKit
import SwiftTerm

/// SwiftTerm tabanlı uzak terminal aynası (docs/design/08, `RemoteTerminalMirroring`).
///
/// SwiftTerm macOS'ta `cols×rows`'u view çerçevesinden hesaplar. Hub'ın ızgarası
/// otoriter olduğu için (scrollback frame'inin `cols`/`rows`'u) yazı boyutu ızgara
/// alana sığacak şekilde seçilir ve terminal view'ı tam o ızgaranın boyutunda,
/// kök view'ın ortasına yerleştirilir.
@MainActor
public final class RemoteTerminalMirror: NSView, RemoteTerminalMirroring, @preconcurrency TerminalViewDelegate {
    static let baseFontSize: CGFloat = 13
    static let fontSizeRange: ClosedRange<CGFloat> = 7...20

    public var view: NSView { self }
    public var onInput: ((Data) -> Void)?

    private let terminalView: TerminalView
    private var baseFont = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
    private var grid: (cols: Int, rows: Int)?

    public override init(frame: NSRect) {
        terminalView = TerminalView(frame: frame)
        super.init(frame: frame)
        terminalView.terminalDelegate = self
        TerminalTheme.lumi.apply(to: terminalView)
        wantsLayer = true
        layer?.backgroundColor = TerminalTheme.lumi.backgroundColor.cgColor
        addSubview(terminalView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    public func apply(_ chunk: RemoteTerminalChunk) {
        if chunk.isSnapshot {
            terminalView.getTerminal().resetToInitialState()
            if let cols = chunk.cols, let rows = chunk.rows, cols > 0, rows > 0 {
                grid = (cols, rows)
            }
            fitGrid()
        }
        terminalView.feed(byteArray: [UInt8](chunk.data)[...])
    }

    public func focus() {
        window?.makeFirstResponder(terminalView)
    }

    public func setFont(_ font: NSFont) {
        baseFont = font
        fitGrid()
    }

    public override func layout() {
        super.layout()
        fitGrid()
    }

    /// Yazı boyutunu ızgara alana sığacak şekilde seçer ve terminal view'ını ortalar.
    private func fitGrid() {
        guard let grid, bounds.width > 0, bounds.height > 0 else {
            terminalView.frame = bounds
            return
        }
        let terminal = terminalView.getTerminal()
        terminalView.font = baseFont.withSize(Self.baseFontSize)
        terminal.resize(cols: grid.cols, rows: grid.rows)
        let natural = terminalView.getOptimalFrameSize().size
        guard natural.width > 0, natural.height > 0 else { return }
        let scale = min(bounds.width / natural.width, bounds.height / natural.height)
        let size = min(max(Self.baseFontSize * scale, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        terminalView.font = baseFont.withSize(floor(size * 2) / 2)
        terminal.resize(cols: grid.cols, rows: grid.rows)
        let fitted = terminalView.getOptimalFrameSize().size
        // Yarım piksel pay: SwiftTerm cols'u genişlik / hücre genişliğinin tabanından hesaplar.
        let frameSize = NSSize(width: ceil(fitted.width) + 0.5, height: ceil(fitted.height) + 0.5)
        terminalView.frame = NSRect(
            x: max(0, (bounds.width - frameSize.width) / 2),
            y: max(0, (bounds.height - frameSize.height) / 2),
            width: frameSize.width, height: frameSize.height)
        if terminal.cols != grid.cols || terminal.rows != grid.rows {
            terminal.resize(cols: grid.cols, rows: grid.rows)
        }
    }

    // MARK: - TerminalViewDelegate

    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Data(data))
    }

    /// Hub'ın PTY'si yeniden boyutlandırılmaz; yerel boyut değişimi yok sayılır.
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    public func setTerminalTitle(source: TerminalView, title: String) {}
    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    public func scrolled(source: TerminalView, position: Double) {}
    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // Uzak terminaldeki yerel yollar bu Mac'te anlamsızdır; yalnız web linkleri açılır.
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }

    public func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// `RemoteTerminalMirrorMaking`'in üretim implementasyonu.
@MainActor
public final class RemoteTerminalMirrorFactory: RemoteTerminalMirrorMaking {
    public init() {}

    public func makeMirror() -> any RemoteTerminalMirroring {
        RemoteTerminalMirror(frame: .zero)
    }
}
