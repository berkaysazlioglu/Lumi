import AppKit
import XCTest
import LumiKit
@testable import LumiAppCore

/// `MenuActionDispatcher` (refactor 3.6): 12 `@objc` aksiyon yerine tek
/// selector + `CommandID → closure` sözlüğü.
@MainActor
final class MenuActionDispatcherTests: XCTestCase {
    private func menuItem(for id: CommandID, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem()
        item.representedObject = id.rawValue
        item.tag = tag
        return item
    }

    func testPerformCommandRoutesToRegisteredHandler() {
        let dispatcher = MenuActionDispatcher()
        var fired = 0
        dispatcher.register(.newTerminal) { fired += 1 }

        dispatcher.performCommand(menuItem(for: .newTerminal))

        XCTAssertEqual(fired, 1)
    }

    /// İndeksli komutlarda `tag` handler'a indeks olarak geçer (⌘1…⌘9).
    func testIndexedCommandForwardsTheMenuItemTag() {
        let dispatcher = MenuActionDispatcher()
        var received: [Int?] = []
        dispatcher.register(.focusTerminalAtIndex) { received.append($0) }

        dispatcher.performCommand(menuItem(for: .focusTerminalAtIndex, tag: 7))

        XCTAssertEqual(received, [7])
    }

    /// Tag'siz item indeks TAŞIMAZ (0, "indeks yok" demektir).
    func testUnindexedCommandForwardsNilIndex() {
        let dispatcher = MenuActionDispatcher()
        var received: [Int?] = []
        dispatcher.register(.toggleLeftSidebar) { received.append($0) }

        dispatcher.performCommand(menuItem(for: .toggleLeftSidebar))

        XCTAssertEqual(received.count, 1)
        XCTAssertNil(received[0])
    }

    func testUnknownCommandIsIgnored() {
        let dispatcher = MenuActionDispatcher()
        var fired = 0
        dispatcher.register(.newTerminal) { fired += 1 }

        dispatcher.performCommand(menuItem(for: .closeTerminal))
        dispatcher.performCommand(nil)

        XCTAssertEqual(fired, 0)
    }

    func testRegisteredIDsReflectRegistrations() {
        let dispatcher = MenuActionDispatcher()
        dispatcher.register(.newTerminal) {}
        dispatcher.register(.openSettings) {}

        XCTAssertEqual(dispatcher.registeredIDs, [.newTerminal, .openSettings])
    }
}
