import AppKit
import LumiKit
import SwiftTerm

/// SwiftTerm tabanlı uzak terminal aynası (docs/design/08, `RemoteTerminalMirroring`).
///
/// Hub'ın ızgarası otoriterdir (snapshot frame'inin `cols`/`rows`'u). Aynanın emülatörü
/// YALNIZ snapshot'ta, boşken o ızgaraya getirilir; yerleşim değişimi emülatöre hiç
/// dokunmaz. SwiftTerm macOS'ta font ve frame değişiminde ızgarayı frame'den yeniden
/// hesaplayıp reflow eder (font yolunda ayrıca `softReset`) — bu, hub'ın ekranıyla
/// ayrışmanın kaynağıydı (eski satırlar yukarıda kalıyor, alt bilgi kayboluyordu).
/// Yazı boyutu ızgara alana sığacak şekilde ayrı bir ölçüm view'ında seçilir; font
/// değişirken view'ın frame'i sıfırdır (SwiftTerm sıfır frame'de ızgarayı hesaplamaz),
/// ardından tam ızgara boyutundaki frame verilir.
@MainActor
public final class RemoteTerminalMirror: NSView, RemoteTerminalMirroring, @preconcurrency TerminalViewDelegate {
    static let baseFontSize: CGFloat = 13
    static let fontSizeRange: ClosedRange<CGFloat> = 7...20
    static let fontSizeStep: CGFloat = 0.5

    public var view: NSView { self }
    public var onInput: ((Data) -> Void)?
    public var onPasteImage: ((Data) -> Void)? {
        get { terminalView.onPasteImage }
        set { terminalView.onPasteImage = newValue }
    }

    private let terminalView: RemoteMirrorTerminalView
    /// Hücre ölçümü için: canlı emülatörü etkilemeden font boyutunun ızgara alanını verir.
    private let probe = TerminalView(frame: .zero)
    private var baseFont = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
    private var appliedFont: NSFont?
    private var grid: (cols: Int, rows: Int)?

    public override init(frame: NSRect) {
        terminalView = RemoteMirrorTerminalView(frame: frame)
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
            let terminal = terminalView.getTerminal()
            terminal.resetToInitialState()
            if let cols = chunk.cols, let rows = chunk.rows, cols > 0, rows > 0 {
                grid = (cols, rows)
                // Boş emülatör: ızgara değişimi reflow'suzdur. View'dan bağımsız yapılır —
                // pane henüz yerleşmemişken gelen snapshot da doğru boyutta kurulur.
                if terminal.cols != cols || terminal.rows != rows {
                    terminal.resize(cols: cols, rows: rows)
                }
            }
            fitGrid()
        }
        terminalView.feed(byteArray: [UInt8](chunk.data)[...])
        if chunk.isSnapshot { repaint() }
    }

    /// Testler: aynanın emülatörü.
    var terminalForTesting: Terminal { terminalView.getTerminal() }

    public func focus() {
        window?.makeFirstResponder(terminalView)
    }

    public func setFont(_ font: NSFont) {
        baseFont = font
        appliedFont = nil
        fitGrid()
    }

    public override func layout() {
        super.layout()
        fitGrid()
    }

    /// Yazı boyutunu ızgara alana sığacak şekilde seçer ve terminal view'ını ortalar.
    private func fitGrid() {
        guard let grid, bounds.width > 0, bounds.height > 0 else { return }
        let font = baseFont.withSize(fittedFontSize(for: grid))
        let natural = naturalSize(of: font, grid: grid)
        if appliedFont != font {
            terminalView.frame = .zero
            terminalView.font = font
            appliedFont = font
        }
        // Yarım piksel pay: SwiftTerm cols'u genişlik / hücre genişliğinin tabanından hesaplar.
        let frameSize = NSSize(width: ceil(natural.width) + 0.5, height: ceil(natural.height) + 0.5)
        terminalView.frame = NSRect(
            x: max(0, (bounds.width - frameSize.width) / 2),
            y: max(0, (bounds.height - frameSize.height) / 2),
            width: frameSize.width, height: frameSize.height)
        let terminal = terminalView.getTerminal()
        if terminal.cols != grid.cols || terminal.rows != grid.rows {
            terminal.resize(cols: grid.cols, rows: grid.rows)
        }
        repaint()
    }

    /// Alana sığan en büyük boyut (yarım punto adımlı, aralıkta).
    private func fittedFontSize(for grid: (cols: Int, rows: Int)) -> CGFloat {
        let base = naturalSize(of: baseFont.withSize(Self.baseFontSize), grid: grid)
        guard base.width > 0, base.height > 0 else { return Self.baseFontSize }
        let scale = min(bounds.width / base.width, bounds.height / base.height)
        let range = Self.fontSizeRange
        var size = min(max(floor(Self.baseFontSize * scale / Self.fontSizeStep) * Self.fontSizeStep,
                           range.lowerBound), range.upperBound)
        // Hücre ölçüleri yuvarlandığı için doğrusal tahmin taşabilir — sığana dek küçült.
        while size > range.lowerBound {
            let natural = naturalSize(of: baseFont.withSize(size), grid: grid)
            if natural.width <= bounds.width, natural.height <= bounds.height { break }
            size -= Self.fontSizeStep
        }
        return size
    }

    private func naturalSize(of font: NSFont, grid: (cols: Int, rows: Int)) -> NSSize {
        probe.font = font
        let terminal = probe.getTerminal()
        if terminal.cols != grid.cols || terminal.rows != grid.rows {
            terminal.resize(cols: grid.cols, rows: grid.rows)
        }
        return probe.getOptimalFrameSize().size
    }

    /// Tüm hücreleri kirli işaretleyip baştan çizer — `needsDisplay` tek başına bazı
    /// satırları (ör. Claude'un blok karakterli logosu) seçilene dek çizmiyordu.
    private func repaint() {
        terminalView.getTerminal().updateFullScreen()
        terminalView.setNeedsDisplay(terminalView.bounds)
    }

    // MARK: - TerminalViewDelegate

    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Data(data))
    }

    /// Hub'ın PTY'si yeniden boyutlandırılmaz; yerel ızgara yalnız snapshot'ta değişir.
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
