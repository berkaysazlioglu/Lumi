import AppKit
import LumiKit
import SwiftTerm
import Testing
@testable import LumiTerminal

// "Yazan kazanır" (karar 143 ek): hub kartı uzak yazarın ızgarasını fontu ölçekleyerek
// gösterir, yerelde yazılınca kendi boyutuna döner.

private final class SizeRecorder: TerminalViewDelegate {
    var sizes: [TerminalGrid] = []
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        sizes.append(TerminalGrid(cols: newCols, rows: newRows))
    }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

@MainActor
@Suite struct TerminalGridOverrideTests {
    private let userFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private func hosted() -> (NSView, DropAwareTerminalView, SizeRecorder) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        let view = DropAwareTerminalView(frame: host.bounds, font: userFont)
        let recorder = SizeRecorder()
        view.terminalDelegate = recorder
        host.addSubview(view)
        TerminalGridFit.fit(view, in: host)
        return (host, view, recorder)
    }

    private func grid(_ view: DropAwareTerminalView) -> TerminalGrid {
        TerminalGrid(cols: view.getTerminal().cols, rows: view.getTerminal().rows)
    }

    @Test func remoteGridScalesTheFontAndStaysCentered() {
        let (host, view, recorder) = hosted()
        let local = grid(view)
        let remote = TerminalGrid(cols: local.cols * 2, rows: local.rows + 10)

        view.setGridOverride(remote)

        #expect(grid(view) == remote)
        #expect(view.font.pointSize < userFont.pointSize)
        #expect(host.bounds.contains(view.frame))
        #expect(recorder.sizes.last == remote)

        // Hub penceresi yeniden boyutlanınca ızgara aynı kalır, font yeniden sığdırılır.
        host.frame.size = NSSize(width: 900, height: 500)
        TerminalGridFit.fit(view, in: host)
        #expect(grid(view) == remote)
        #expect(host.bounds.contains(view.frame))
    }

    @Test func releasingRestoresTheUserFontAndLocalGrid() {
        let (host, view, recorder) = hosted()
        let local = grid(view)
        view.setGridOverride(TerminalGrid(cols: 60, rows: 12))
        #expect(grid(view) == TerminalGrid(cols: 60, rows: 12))

        view.releaseGridOverride()

        #expect(view.gridOverride == nil)
        #expect(view.font.pointSize == userFont.pointSize)
        #expect(grid(view) == local)
        #expect(recorder.sizes.last == local)
        #expect(host.bounds.contains(view.frame))
    }

    @Test func settingsFontDuringOverrideAppliesAfterRelease() {
        let (_, view, _) = hosted()
        view.setGridOverride(TerminalGrid(cols: 90, rows: 20))
        let bigger = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        #expect(view.adoptUserFont(bigger))
        #expect(grid(view) == TerminalGrid(cols: 90, rows: 20))
        view.releaseGridOverride()
        #expect(view.font.pointSize == 15)
        #expect(!view.adoptUserFont(userFont))
    }

    @Test func detachedViewTakesTheGridDirectly() {
        let view = DropAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), font: userFont)
        let recorder = SizeRecorder()
        view.terminalDelegate = recorder
        view.setGridOverride(TerminalGrid(cols: 150, rows: 45))
        #expect(grid(view) == TerminalGrid(cols: 150, rows: 45))
        #expect(recorder.sizes.last == TerminalGrid(cols: 150, rows: 45))
    }
}
