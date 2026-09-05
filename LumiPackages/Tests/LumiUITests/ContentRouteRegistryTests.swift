import Foundation
import LumiKit
import SwiftUI
import XCTest
@testable import LumiUI

/// Orta alan router'ının **saf** çözümlemesi (Faz 6.3) + route geçişinin
/// terminal view köprüsü sözleşmesi.
@MainActor
final class ContentRouteRegistryTests: XCTestCase {
    /// Kabuğun terminals dışında bir route'u da taşıyabildiğinin kanıtı
    /// (ileride "Tasks" bunun yerine geçecek).
    private static let placeholder = ContentRouteID("placeholder")

    private func descriptor(_ id: ContentRouteID) -> ContentRouteDescriptor {
        ContentRouteDescriptor(
            id: id,
            title: id.rawValue,
            icon: "square",
            makeView: { _ in AnyView(EmptyView()) }
        )
    }

    private func registry(_ ids: [ContentRouteID]) -> ContentRouteRegistry {
        var registry = ContentRouteRegistry()
        for id in ids { registry.register(descriptor(id)) }
        return registry
    }

    // MARK: - Çözümleme

    func testRoutesKeepRegistrationOrder() {
        let registry = registry([.terminals, Self.placeholder])
        XCTAssertEqual(registry.routes().map(\.id), [.terminals, Self.placeholder])
    }

    func testResolveReturnsRegisteredRoute() {
        XCTAssertEqual(registry([.terminals, Self.placeholder]).resolve(Self.placeholder)?.id, Self.placeholder)
    }

    func testUnknownRouteFallsBackToTerminals() {
        let resolved = registry([.terminals]).resolve(ContentRouteID("ghost"))
        XCTAssertEqual(resolved?.id, .terminals, "ui-state'te kalmış eski id kabuğu boş bırakmaz")
    }

    func testResolveReturnsNilWhenNothingIsRegistered() {
        XCTAssertNil(ContentRouteRegistry().resolve(.terminals))
    }

    func testRegisteringSameRouteTwiceReplacesWithoutDuplicating() {
        var registry = ContentRouteRegistry()
        registry.register(descriptor(.terminals))
        registry.register(ContentRouteDescriptor(
            id: .terminals,
            title: "Terminals v2",
            icon: "terminal",
            makeView: { _ in AnyView(EmptyView()) }
        ))
        XCTAssertEqual(registry.routes().count, 1)
        XCTAssertEqual(registry.routes().first?.title, "Terminals v2")
    }

    // MARK: - Route geçiş sözleşmesi (Faz 6.3)

    /// "terminals → X → terminals" turu: çıkışta `detachAll`, dönüşte
    /// `refreshAttachedViews`. PTY'ye dokunulmaz, view'lar yok edilmez.
    func testTerminalsToPlaceholderAndBackDetachesThenRefreshes() async {
        let fixture = await ShellContextFixture.make()
        let navigation = fixture.context.navigation
        navigation.openTab("/r/alpha")

        XCTAssertEqual(fixture.viewProvider.detachAllCount, 0)
        XCTAssertEqual(fixture.viewProvider.refreshCallCount, 0)

        navigation.setRoute(.content(Self.placeholder))
        XCTAssertEqual(fixture.viewProvider.detachAllCount, 1, "route'tan çıkışta tek açık kapanış")
        XCTAssertEqual(fixture.viewProvider.refreshCallCount, 0)

        navigation.setRoute(.repo("/r/alpha"))
        XCTAssertEqual(fixture.viewProvider.detachAllCount, 1)
        XCTAssertEqual(fixture.viewProvider.refreshCallCount, 1, "dönüşte canlı view'lar yeniden oturur")
        fixture.stop()
    }

    func testRepoToRepoSwitchDoesNotTouchTheViewBridge() async {
        let fixture = await ShellContextFixture.make()
        let navigation = fixture.context.navigation
        navigation.openTab("/r/alpha")
        navigation.openTab("/r/beta")

        XCTAssertEqual(fixture.viewProvider.detachAllCount, 0, "host'lar yerinde — detach gerekmez")
        XCTAssertEqual(fixture.viewProvider.refreshCallCount, 0)
        fixture.stop()
    }

    func testSwitchingBetweenNonRepoRoutesIsSilent() async {
        let fixture = await ShellContextFixture.make()
        let navigation = fixture.context.navigation
        navigation.openTab("/r/alpha")
        navigation.setRoute(.content(Self.placeholder))
        navigation.setRoute(.content(ContentRouteID("other")))

        XCTAssertEqual(fixture.viewProvider.detachAllCount, 1, "ikinci geçişte tekrar detach edilmez")
        XCTAssertEqual(fixture.viewProvider.refreshCallCount, 0)
        fixture.stop()
    }
}
