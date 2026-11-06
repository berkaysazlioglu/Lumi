import AppKit
import Foundation
import LumiKit
import SwiftTerm
import Testing
@testable import LumiTerminal

// Karar 143 ek: controller aynasının hub ekranıyla birebir kalması.

@MainActor
@Suite struct RemoteMirrorFeedTests {
    private func collect(_ stream: AsyncStream<TerminalMirrorEvent>, count: Int) async -> [TerminalMirrorEvent] {
        var events: [TerminalMirrorEvent] = []
        for await event in stream {
            events.append(event)
            if events.count == count { break }
        }
        return events
    }

    @Test func subscriberGetsTheSnapshotFirstThenOutputInOrder() async {
        var snapshots = 0
        let feed = RemoteMirrorFeed {
            snapshots += 1
            return .snapshot(data: Data("s\(snapshots)".utf8), cols: 80, rows: 24)
        }
        feed.output(Data("before".utf8)) // aboneden önceki bayt snapshot'ın içindedir
        let stream = feed.subscribe()
        feed.output(Data("a".utf8))
        feed.output(Data("b".utf8))
        let events = await collect(stream, count: 3)
        #expect(events == [
            .snapshot(data: Data("s1".utf8), cols: 80, rows: 24),
            .output(Data("a".utf8)),
            .output(Data("b".utf8)),
        ])
    }

    @Test func resizeHoldsBytesUntilOneSnapshotAtTheSettledSize() async {
        var cols = 80
        let feed = RemoteMirrorFeed { .snapshot(data: Data(), cols: cols, rows: 24) }
        let stream = feed.subscribe()
        feed.output(Data("a".utf8))
        // Sürüklenen pencere: üç boyut değişimi, araya yeni boyut için yazılmış baytlar.
        for width in [90, 100, 120] {
            cols = width
            feed.sizeChanged()
            feed.output(Data("redraw\(width)".utf8))
        }
        #expect(feed.isResyncing)
        try? await Task.sleep(for: RemoteMirrorFeed.resyncDelay * 3)
        feed.output(Data("after".utf8))
        let events = await collect(stream, count: 4)
        #expect(events == [
            .snapshot(data: Data(), cols: 80, rows: 24),
            .output(Data("a".utf8)),
            .snapshot(data: Data(), cols: 120, rows: 24),
            .output(Data("after".utf8)),
        ])
    }

    @Test func resizeWithoutSubscribersIsFree() {
        var snapshots = 0
        let feed = RemoteMirrorFeed {
            snapshots += 1
            return .snapshot(data: Data(), cols: 1, rows: 1)
        }
        feed.sizeChanged()
        #expect(!feed.isResyncing)
        #expect(snapshots == 0)
    }
}

@MainActor
@Suite struct RemoteTerminalMirrorTests {
    private func screen(_ mirror: RemoteTerminalMirror) -> [String] {
        let terminal = mirror.terminalForTesting
        return (0..<terminal.rows).map { terminal.getLine(row: $0)?.translateToString(trimRight: true) ?? "" }
    }

    @Test func layoutChangesNeverReflowTheMirroredScreen() {
        let mirror = RemoteTerminalMirror(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        // Claude benzeri: tam genişlik çizgiler + alt bilgi; imleç girdi satırında.
        let rule = String(repeating: "─", count: 100)
        let screenBytes = "\u{1B}[2J\u{1B}[H" + "logo\r\n\(rule)\r\n> input\r\n\(rule)\r\n  footer\u{1B}[3;8H"
        mirror.apply(RemoteTerminalChunk(data: Data(screenBytes.utf8), cols: 100, rows: 12, isSnapshot: true))
        let before = screen(mirror)
        #expect(before[1] == rule)
        #expect(before[4] == "  footer")

        for size in [NSSize(width: 400, height: 300), NSSize(width: 1600, height: 900), NSSize(width: 650, height: 210)] {
            mirror.frame.size = size
            mirror.layout()
            mirror.setFont(NSFont.monospacedSystemFont(ofSize: 12, weight: .regular))
            #expect(mirror.terminalForTesting.cols == 100)
            #expect(mirror.terminalForTesting.rows == 12)
            #expect(screen(mirror) == before)
        }
        let cursor = mirror.terminalForTesting.getCursorLocation()
        #expect(cursor.x == 7 && cursor.y == 2)
    }

    @Test func snapshotBeforeLayoutIsBuiltAtTheHubGrid() {
        let mirror = RemoteTerminalMirror(frame: .zero)
        let line = String(repeating: "x", count: 150)
        mirror.apply(RemoteTerminalChunk(data: Data(line.utf8), cols: 150, rows: 10, isSnapshot: true))
        #expect(mirror.terminalForTesting.cols == 150)
        #expect(screen(mirror)[0] == line)
        #expect(screen(mirror)[1] == "")
    }
}
