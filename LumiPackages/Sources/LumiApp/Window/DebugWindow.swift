import AppKit

/// GEÇİCİ tanı: event akışı + AppKit hit zinciri.
final class DebugWindow: NSWindow {
    private func dbg(_ m: String) {
        let line = "[win] \(m)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/lumi-overlay.log") { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { try? line.write(toFile: "/tmp/lumi-overlay.log", atomically: true, encoding: .utf8) }
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseDragged || event.type == .leftMouseUp {
            var chain: [String] = []
            var v = contentView?.superview?.hitTest(event.locationInWindow)
            while let cur = v { chain.append("\(type(of: cur))"); v = cur.superview }
            dbg("\(event.type.rawValue) loc=\(event.locationInWindow) origin=\(frame.origin) movable=\(isMovable) bg=\(isMovableByWindowBackground) hit=\(chain.joined(separator: "<"))")
        }
        super.sendEvent(event)
    }
}
