import Foundation
import LumiKit
import SwiftUI
import XCTest
@testable import LumiUI

/// `ToolbarRegistry.items(in:context:)` — **saf çözümleme** (Faz 6.4).
/// Hiçbir view render edilmez; yalnız bölge filtresi, `order` sıralaması,
/// `isVisible` filtresi ve override kuralı doğrulanır.
@MainActor
final class ToolbarRegistryTests: XCTestCase {
    private var fixture: ShellContextFixture!

    override func setUp() async throws {
        fixture = await ShellContextFixture.make()
    }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    private func descriptor(
        _ id: ToolbarItemID,
        region: ToolbarRegion = .trailing,
        order: Int = 0,
        isVisible: @escaping @MainActor (ShellContext) -> Bool = { _ in true }
    ) -> ToolbarItemDescriptor {
        ToolbarItemDescriptor(
            id: id,
            region: region,
            order: order,
            isVisible: isVisible,
            makeView: { AnyView(EmptyView()) }
        )
    }

    private func registry(_ descriptors: [ToolbarItemDescriptor]) -> ToolbarRegistry {
        var registry = ToolbarRegistry()
        registry.register(contentsOf: descriptors)
        return registry
    }

    private func ids(_ registry: ToolbarRegistry, _ region: ToolbarRegion) -> [ToolbarItemID] {
        registry.items(in: region, context: fixture.context).map(\.id)
    }

    // MARK: - Bölge

    func testItemsAreResolvedPerRegion() {
        let registry = registry([
            descriptor(.logo, region: .leading, order: 10),
            descriptor(.repoTabs, region: .leading, order: 20),
            descriptor(.gridSettings, region: .center),
            descriptor(.settings, region: .trailing),
        ])
        XCTAssertEqual(ids(registry, .leading), [.logo, .repoTabs])
        XCTAssertEqual(ids(registry, .center), [.gridSettings])
        XCTAssertEqual(ids(registry, .trailing), [.settings])
    }

    func testRegionWithoutItemsResolvesToEmpty() {
        let registry = registry([descriptor(.settings, region: .trailing)])
        XCTAssertEqual(ids(registry, .center), [])
    }

    // MARK: - Sıra

    func testOrderWinsOverRegistrationOrder() {
        let registry = registry([
            descriptor(.settings, order: 120),
            descriptor(.focusMode, order: 100),
            descriptor(.usageIndicator(.claude), order: 0),
        ])
        XCTAssertEqual(ids(registry, .trailing), [.usageIndicator(.claude), .focusMode, .settings])
    }

    /// `sorted` kararsızdır: eşit `order` değerlerinde tie-break kayıt
    /// sırasıdır, yoksa bar'ın dizilişi derleyici keyfine kalırdı.
    func testEqualOrdersKeepRegistrationOrder() {
        let registry = registry([
            descriptor(.usageIndicator(.codex), order: 5),
            descriptor(.usageIndicator(.claude), order: 5),
            descriptor(.focusMode, order: 5),
        ])
        XCTAssertEqual(
            ids(registry, .trailing),
            [.usageIndicator(.codex), .usageIndicator(.claude), .focusMode]
        )
    }

    // MARK: - Görünürlük

    func testInvisibleItemsAreFilteredOut() {
        let registry = registry([
            descriptor(.gridSettings, region: .center, order: 0, isVisible: { $0.activeRepoPath != nil }),
            descriptor(.newTerminal, region: .center, order: 10),
        ])
        XCTAssertEqual(ids(registry, .center), [.newTerminal], "repo yokken grid ayarı çizilmez")

        fixture.openRepo()
        XCTAssertEqual(ids(registry, .center), [.gridSettings, .newTerminal])
    }

    func testVisibilityIsEvaluatedAgainstTheLiveContext() {
        let registry = registry([
            descriptor(.settings, isVisible: { $0.dialogs.isSettingsOpen }),
        ])
        XCTAssertEqual(ids(registry, .trailing), [])
        fixture.context.dialogs.isSettingsOpen = true
        XCTAssertEqual(ids(registry, .trailing), [.settings])
    }

    // MARK: - Override

    /// Aynı id ikinci kez kaydedilirse öncekini EZER (panel/overlay
    /// registry'leriyle aynı kural): bar'da iki kopya belirmez, kompozisyon
    /// sırası sonucu değiştirmez.
    func testRegisteringSameIDTwiceReplacesWithoutDuplicating() {
        var registry = ToolbarRegistry()
        registry.register(descriptor(.settings, region: .trailing, order: 120))
        registry.register(ToolbarItemDescriptor(
            id: .settings,
            region: .leading,
            order: 1,
            makeView: { AnyView(EmptyView()) }
        ))
        XCTAssertEqual(registry.all.count, 1)
        XCTAssertEqual(registry.descriptor(for: .settings)?.region, .leading)
        XCTAssertEqual(ids(registry, .trailing), [])
        XCTAssertEqual(ids(registry, .leading), [.settings])
    }

    /// Override öğenin KAYIT SIRASINDAKİ yerini korur — eşit `order`
    /// komşularının dizilişi bir override yüzünden kaymaz.
    func testOverrideKeepsRegistrationPosition() {
        var registry = ToolbarRegistry()
        registry.register(descriptor(.usageIndicator(.claude), order: 0))
        registry.register(descriptor(.focusMode, order: 0))
        registry.register(descriptor(.usageIndicator(.claude), order: 0))
        XCTAssertEqual(ids(registry, .trailing), [.usageIndicator(.claude), .focusMode])
    }

    // MARK: - Panel toggle'ları (PanelSlot.allCases'ten türer)

    private func panelRegistry(_ slots: [PanelItemID: PanelSlot]) -> PanelItemRegistry {
        var panels = PanelItemRegistry()
        for (id, slot) in slots.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            panels.register(PanelItemDescriptor(
                id: id,
                title: id.rawValue,
                icon: "square",
                defaultSlot: slot,
                makeView: { AnyView(EmptyView()) }
            ))
        }
        return panels
    }

    func testPanelTogglesAreDerivedFromAllCases() {
        let toggles = ShellToolbarItems.panelToggles(panels: PanelItemRegistry())
        XCTAssertEqual(
            Set(toggles.map(\.id)),
            Set(PanelSlot.allCases.map(ToolbarItemID.panelToggle)),
            "her yuva için tam bir toggle; yeni yuva eklenince kendiliğinden gelir"
        )
    }

    func testPanelToggleRegionsMatchTodaysHeader() {
        var registry = ToolbarRegistry()
        registry.register(contentsOf: ShellToolbarItems.panelToggles(
            panels: panelRegistry([.sessions: .left, .gitCommits: .right])
        ))
        XCTAssertEqual(ids(registry, .leading), [.panelToggle(.left)], "hamburger solda")
        XCTAssertEqual(ids(registry, .trailing), [.panelToggle(.right)], "git ikonu sağda")
    }

    /// `.bottom` bugün kayıtlı öğesi olmayan yuvadır → toggle'ı gizli.
    func testSlotWithoutRegisteredItemsHidesItsToggle() {
        var registry = ToolbarRegistry()
        registry.register(contentsOf: ShellToolbarItems.panelToggles(
            panels: panelRegistry([.sessions: .left])
        ))
        XCTAssertEqual(ids(registry, .trailing), [], "bottom ve right için öğe yok → toggle yok")
    }

    /// İlk `.bottom` öğesi kaydedildiği gün toggle kendiliğinden görünür.
    func testRegisteringABottomItemRevealsItsToggle() {
        var registry = ToolbarRegistry()
        registry.register(contentsOf: ShellToolbarItems.panelToggles(
            panels: panelRegistry([PanelItemID("tasks"): .bottom])
        ))
        XCTAssertEqual(ids(registry, .trailing), [.panelToggle(.bottom)])
    }

    /// Öğe taşınırsa toggle da taşındığı yuvaya taşınır (yerleşim otoritedir).
    func testMovingTheOnlyItemMovesItsToggle() {
        var registry = ToolbarRegistry()
        registry.register(contentsOf: ShellToolbarItems.panelToggles(
            panels: panelRegistry([.sessions: .left])
        ))
        XCTAssertEqual(ids(registry, .leading), [.panelToggle(.left)])

        fixture.context.layout.move(item: .sessions, to: .bottom)
        XCTAssertEqual(ids(registry, .leading), [])
        XCTAssertEqual(ids(registry, .trailing), [.panelToggle(.bottom)])
    }

    /// Hamburger repo açık DEĞİLKEN de durur: toggle kayıtlı öğelere bakar,
    /// onların `isAvailable` durumuna değil (bugünkü davranış).
    func testToggleStaysVisibleWhenItemsAreUnavailable() {
        var panels = PanelItemRegistry()
        panels.register(PanelItemDescriptor(
            id: .sessions,
            title: "Sessions",
            icon: "square",
            defaultSlot: .left,
            isAvailable: { $0.activeRepoPath != nil },
            makeView: { AnyView(EmptyView()) }
        ))
        var registry = ToolbarRegistry()
        registry.register(contentsOf: ShellToolbarItems.panelToggles(panels: panels))
        XCTAssertEqual(ids(registry, .leading), [.panelToggle(.left)])
    }
}
