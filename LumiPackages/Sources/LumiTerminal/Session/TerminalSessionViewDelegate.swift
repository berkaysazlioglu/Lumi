import AppKit
import Foundation
import SwiftTerm

/// SwiftTerm ↔ oturum köprüsü (design/01 §4). Delegate çağrıları AppKit'ten
/// (main) gelir; protokol isolasyonsuz olduğundan `@preconcurrency`
/// conformance runtime'da MainActor'ı doğrular.
extension TerminalSession: @preconcurrency TerminalViewDelegate {
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        requestResize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        // Bilinçli no-op: title semantiğini Lumi'nin kendi OSC parser'ı sürer (design/01 §6)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // Klavye + emülatör oto-yanıtları (mode 1004 focus event'leri dahil) —
        // hepsi filtreli yazma hunisinden geçer
        write(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // http/https whitelist paritesi (Electron paritesi)
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    func bell(source: TerminalView) {
        guard !isTerminated else { return }
        delegate?.sessionDidBell(self)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        // OSC 52: Electron sürümünde yoktu; bilinçli no-op (parite)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
