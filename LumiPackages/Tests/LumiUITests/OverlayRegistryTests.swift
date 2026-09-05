import Foundation
import LumiKit
import LumiState
import SwiftUI
import XCTest
@testable import LumiUI

/// `OverlayRegistry.presented(in:)` — Faz 6.5. Elle `||` listesi yerine
/// descriptor'ların `isPresented` predikatları.
@MainActor
final class OverlayRegistryTests: XCTestCase {
    private var fixture: ShellContextFixture!
    private var shell: ShellContext { fixture.context }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    override func setUp() async throws {
        fixture = await ShellContextFixture.make()
    }

    private func descriptor(
        _ id: OverlayID,
        isPresented: @escaping @MainActor (ShellContext) -> Bool
    ) -> OverlayDescriptor {
        OverlayDescriptor(id: id, isPresented: isPresented, makeView: { AnyView(EmptyView()) })
    }

    /// Üretim kaydının aynısı (`ShellComposition.registerShellOverlays`).
    private func productionRegistry() -> OverlayRegistry {
        var registry = OverlayRegistry()
        registry.register(descriptor(.focusModeBar) { $0.layout.isFocusMode && $0.activeRepoPath != nil })
        registry.register(descriptor(.fileViewer) { $0.fileViewer.isPresented })
        registry.register(descriptor(.settings) { $0.dialogs.isSettingsOpen })
        registry.register(descriptor(.toasts) { !$0.toasts.toasts.isEmpty })
        registry.register(descriptor(.closeTabDialog) { $0.dialogs.closeTabDialog != nil })
        registry.register(descriptor(.quitDialog) { $0.dialogs.quitDialogTerminalCount != nil })
        return registry
    }

    private func presentedIDs() -> [OverlayID] {
        productionRegistry().presented(in: shell).map(\.id)
    }

    func testNothingIsPresentedOnAQuietShell() {
        XCTAssertEqual(presentedIDs(), [])
    }

    func testSettingsDialogPresentsItsOverlay() {
        shell.dialogs.isSettingsOpen = true
        XCTAssertEqual(presentedIDs(), [.settings])
    }

    func testQuitDialogPresentsItsOverlay() {
        shell.dialogs.presentQuitDialog(terminalCount: 2)
        XCTAssertEqual(presentedIDs(), [.quitDialog])
    }

    func testCloseTabDialogPresentsItsOverlay() async throws {
        shell.navigation.openTab("/r/alpha")
        let meta = try await fixture.spawnTerminal()
        shell.terminals.minimize(meta.id)
        shell.requestCloseTab("/r/alpha", repoName: "alpha")
        XCTAssertEqual(presentedIDs(), [.closeTabDialog])
    }

    func testFocusModeBarNeedsAnActiveRepo() {
        shell.layout.toggleFocusMode()
        XCTAssertEqual(presentedIDs(), [], "repo yokken hover bar çizilmez")
        shell.navigation.openTab("/r/alpha")
        XCTAssertEqual(presentedIDs(), [.focusModeBar])
    }

    func testToastsPresentOnlyWhenTheStackIsNonEmpty() {
        XCTAssertFalse(presentedIDs().contains(.toasts))
        shell.toasts.show(error: .underlying(domain: "test", message: "boom"))
        XCTAssertTrue(presentedIDs().contains(.toasts))
    }

    func testOverlaysStackInRegistrationOrder() {
        shell.navigation.openTab("/r/alpha")
        shell.layout.toggleFocusMode()
        shell.toasts.show(error: .underlying(domain: "test", message: "boom"))
        XCTAssertEqual(presentedIDs(), [.focusModeBar, .toasts], "kayıt sırası = z-sırası")
    }

    func testRegisteringSameOverlayTwiceReplacesWithoutDuplicating() {
        var registry = OverlayRegistry()
        registry.register(descriptor(.settings) { _ in true })
        registry.register(descriptor(.settings) { _ in false })
        XCTAssertEqual(registry.all.count, 1)
        XCTAssertEqual(registry.presented(in: shell).count, 0)
    }
}
