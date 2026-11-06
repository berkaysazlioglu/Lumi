import AppKit
import LumiKit
import SwiftTerm

/// "Yazan kazanır" (karar 143 ek, docs/design/08): bir controller bu terminale yazınca
/// emülatör ve PTY onun ızgarasına geçer; kart ızgarayı fontu ölçekleyerek ortada gösterir.
/// Yerelde tuşa basılınca (`TerminalEventMonitor`) ya da yazar ayrılınca yerel boyuta dönülür.
///
/// SwiftTerm font değişiminde ızgarayı o anki frame'den yeniden hesaplayıp reflow eder;
/// font bu yüzden frame sıfırken değiştirilir (SwiftTerm 0×0'da ızgaraya dokunmaz) ve
/// ızgarayı belirleyen tek adım host'un (`TerminalGridFit`) verdiği frame olur.
struct GridOverrideState {
    var grid: TerminalGrid?
    /// Override sırasında kullanıcının fontu (Settings değişikliği de buraya yazılır).
    var userFont: NSFont?
    /// Uzak ızgarada fontun inebileceği/çıkabileceği aralık.
    static let fontRange: ClosedRange<CGFloat> = 6...28
}

extension DropAwareTerminalView: TerminalGridOverriding {
    var gridOverride: TerminalGrid? { gridOverrideState.grid }

    func fitOverrideFont(in size: CGSize) -> CGSize {
        guard let grid = gridOverrideState.grid, let userFont = gridOverrideState.userFont else { return cellSize }
        let fitted = TerminalCellProbe.fittedFont(base: userFont, grid: grid, in: size,
                                                  range: GridOverrideState.fontRange)
        applyFontKeepingGrid(fitted)
        return cellSize
    }

    /// Uzak ızgarayı uygular. Host'a bağlıysa yerleşim fontu ve frame'i kurar; değilse
    /// emülatör doğrudan yeniden boyutlanır (kart görününce host oturtur).
    func setGridOverride(_ grid: TerminalGrid) {
        guard gridOverrideState.grid != grid else { return }
        if gridOverrideState.grid == nil { gridOverrideState.userFont = font }
        gridOverrideState.grid = grid
        refitInHost(fallback: grid)
    }

    /// Yerel boyuta döner (kullanıcı fontu geri gelir). Override yoksa no-op.
    func releaseGridOverride() {
        guard gridOverrideState.grid != nil else { return }
        let userFont = gridOverrideState.userFont
        gridOverrideState = GridOverrideState()
        if let userFont { applyFontKeepingGrid(userFont) }
        refitInHost(fallback: nil)
    }

    /// Settings'ten gelen font: override sürerken saklanır ve sığdırma ona göre yenilenir.
    /// `false` → override yok, çağıran fontu normal yoldan uygular.
    func adoptUserFont(_ font: NSFont) -> Bool {
        guard gridOverrideState.grid != nil else { return false }
        gridOverrideState.userFont = font
        refitInHost(fallback: nil)
        return true
    }

    private func refitInHost(fallback grid: TerminalGrid?) {
        if let host = superview, !host.bounds.isEmpty {
            TerminalGridFit.fit(self, in: host)
            if let grid = gridOverrideState.grid { ensureGrid(grid) }
            getTerminal().updateFullScreen()
            setNeedsDisplay(bounds)
        } else if let grid {
            ensureGrid(grid)
        }
    }

    /// Kayan nokta artığı ya da bağlı olmayan view: emülatörü ızgaraya zorlar ve
    /// SwiftTerm'in kendi yolundaki gibi delegate'e bildirir (PTY + ayna).
    private func ensureGrid(_ grid: TerminalGrid) {
        let terminal = getTerminal()
        guard terminal.cols != grid.cols || terminal.rows != grid.rows else { return }
        terminal.resize(cols: grid.cols, rows: grid.rows)
        terminalDelegate?.sizeChanged(source: self, newCols: grid.cols, newRows: grid.rows)
    }

    private func applyFontKeepingGrid(_ newFont: NSFont) {
        guard newFont != font else { return }
        let saved = frame
        setFrameSize(.zero)
        font = newFont
        // Host yeni frame'i verene dek eski boyut korunur (ızgara yeni hücreyle yeniden
        // hesaplanacağı için frame'i host verir; burada yalnız boş kalmasın).
        if superview == nil { setFrameSize(saved.size) }
    }
}
