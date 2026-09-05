import Foundation
import LumiKit
import SwiftUI
import XCTest
@testable import LumiUI

/// `PanelItemRegistry.resolved(slot:layout:context:)` — **saf çözümleme**
/// (Faz 6.2). Hiçbir view render edilmez; yalnız sıra, filtre ve dayanıklılık
/// kuralları doğrulanır.
@MainActor
final class PanelItemRegistryTests: XCTestCase {
    private var fixture: ShellContextFixture!

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    override func setUp() async throws {
        fixture = await ShellContextFixture.make()
    }

    private func descriptor(
        _ id: PanelItemID,
        slot: PanelSlot = .left,
        isAvailable: @escaping @MainActor (ShellContext) -> Bool = { _ in true }
    ) -> PanelItemDescriptor {
        PanelItemDescriptor(
            id: id,
            title: id.rawValue,
            icon: "square",
            defaultSlot: slot,
            isAvailable: isAvailable,
            makeView: { AnyView(EmptyView()) }
        )
    }

    private func registry(_ descriptors: [PanelItemDescriptor]) -> PanelItemRegistry {
        var registry = PanelItemRegistry()
        for descriptor in descriptors { registry.register(descriptor) }
        return registry
    }

    private func ids(
        _ registry: PanelItemRegistry,
        _ slot: PanelSlot,
        _ layout: PanelLayout
    ) -> [PanelItemID] {
        registry.resolved(slot: slot, layout: layout, context: fixture.context).map(\.id)
    }

    // MARK: - Sıra

    func testOrderComesFromLayoutNotRegistrationOrder() {
        let registry = registry([descriptor(.sessions), descriptor(.fileTree)])
        let layout = PanelLayout.defaults.moving(.fileTree, to: .left, index: 0)
        XCTAssertEqual(ids(registry, .left, layout), [.fileTree, .sessions])
    }

    func testItemsResolvePerSlot() {
        let registry = registry([
            descriptor(.sessions),
            descriptor(.fileTree),
            descriptor(.gitCommits, slot: .right),
            descriptor(.gitChanges, slot: .right),
        ])
        let legacyLayout = PanelLayout(slots: [.left: [.sessions, .fileTree], .right: [.gitCommits, .gitChanges]], visibleSlots: [.left, .right], widths: [:])
        XCTAssertEqual(ids(registry, .left, legacyLayout), [.sessions, .fileTree])
        XCTAssertEqual(ids(registry, .right, legacyLayout), [.gitCommits, .gitChanges])
        XCTAssertEqual(ids(registry, .bottom, .defaults), [])
    }

    /// **Ana hedef:** taşınan öğe yalnız hedef yuvada çizilir; kayıt tarafı
    /// hiç değişmez.
    func testMovedItemLeavesSourceSlot() {
        let registry = registry([
            descriptor(.sessions),
            descriptor(.fileTree),
            descriptor(.gitCommits, slot: .right),
            descriptor(.gitChanges, slot: .right),
        ])
        let layout = PanelLayout.defaults.moving(.fileTree, to: .right, index: 0)
        XCTAssertEqual(ids(registry, .left, layout), [.sessions])
        XCTAssertEqual(ids(registry, .right, layout), [.fileTree, .gitCommits, .gitChanges])
    }

    // MARK: - Dayanıklılık

    func testUnknownLayoutIDsAreSkipped() {
        let registry = registry([descriptor(.sessions)])
        let layout = PanelLayout(
            slots: [.left: [PanelItemID("ghostFeature"), .sessions]],
            visibleSlots: [.left],
            widths: [:]
        )
        XCTAssertEqual(
            ids(registry, .left, layout),
            [.sessions],
            "ui-state'te kalmış bilinmeyen id kabuğu bozmaz"
        )
    }

    func testLegacyLayoutFallsBackToProjectToolsRegistration() {
        let registry = registry([
            descriptor(.sessions),
            descriptor(.projectTools, slot: .right)
        ])
        let legacy = PanelLayout(
            slots: [.left: [.sessions], .right: [.fileTree, .gitCommits, .gitChanges]],
            visibleSlots: [.left, .right], widths: [:]
        )
        XCTAssertEqual(ids(registry, .right, legacy), [.projectTools])
    }

    func testDuplicateLayoutEntriesAreCollapsed() {
        let registry = registry([descriptor(.sessions)])
        let layout = PanelLayout(
            slots: [.left: [.sessions, .sessions]],
            visibleSlots: [.left],
            widths: [:]
        )
        XCTAssertEqual(ids(registry, .left, layout), [.sessions])
    }

    /// Yerleşimde HİÇ adı geçmeyen yeni bir öğe `defaultSlot`'una düşer —
    /// yeni feature ui-state migration'ı beklemez.
    func testUnplacedItemFallsBackToDefaultSlot() {
        let registry = registry([descriptor(.sessions), descriptor(PanelItemID("tasks"), slot: .right)])
        XCTAssertEqual(ids(registry, .right, .defaults).last, PanelItemID("tasks"))
        XCTAssertFalse(ids(registry, .left, .defaults).contains(PanelItemID("tasks")))
    }

    func testPlacedItemDoesNotAlsoAppearInItsDefaultSlot() {
        let registry = registry([descriptor(.fileTree, slot: .left)])
        let layout = PanelLayout.defaults.moving(.fileTree, to: .right, index: 0)
        XCTAssertEqual(ids(registry, .left, layout), [])
        XCTAssertEqual(ids(registry, .right, layout), [.fileTree])
    }

    func testRegisteringSameIDTwiceReplacesWithoutDuplicating() {
        var registry = PanelItemRegistry()
        registry.register(descriptor(.sessions))
        registry.register(PanelItemDescriptor(
            id: .sessions,
            title: "Sessions v2",
            icon: "square",
            defaultSlot: .left,
            makeView: { AnyView(EmptyView()) }
        ))
        XCTAssertEqual(registry.all.count, 1)
        XCTAssertEqual(registry.descriptor(for: .sessions)?.title, "Sessions v2")
    }

    // MARK: - isAvailable filtresi

    func testUnavailableItemsAreFilteredOut() {
        let registry = registry([
            descriptor(.sessions, isAvailable: { $0.activeRepoPath != nil }),
            descriptor(.fileTree),
        ])
        XCTAssertEqual(ids(registry, .left, .defaults), [.fileTree], "repo yokken sessions çizilmez")

        fixture.openRepo()
        XCTAssertEqual(ids(registry, .left, .defaults), [.sessions, .fileTree])
    }

    func testAvailabilityIsEvaluatedAgainstTheLiveContext() async throws {
        let registry = registry([descriptor(.sessions, isAvailable: { !$0.terminals.terminals.isEmpty })])
        XCTAssertEqual(ids(registry, .left, .defaults), [])
        try await fixture.spawnTerminal()
        XCTAssertEqual(ids(registry, .left, .defaults), [.sessions])
    }
}
