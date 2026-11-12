import XCTest
import LumiKit
@testable import LumiState

/// Karar 151: sol üst bölümün (All Terminals / view'lar / Tasks / Remote) sırası.
final class SidebarNavigationOrderTests: XCTestCase {
    private let first = CustomViewID(rawValue: "a")
    private let second = CustomViewID(rawValue: "b")
    private let third = CustomViewID(rawValue: "c")

    func testKeysRoundTrip() {
        let items: [SidebarNavigationItem] = [.allTerminals, .customView(first), .section(.tasks), .section(.remote)]
        XCTAssertEqual(items.map(\.key), ["allTerminals", "view:a", "tasks", "remote"])
        XCTAssertEqual(items.map(\.key).compactMap(SidebarNavigationItem.init(key:)), items)
        XCTAssertNil(SidebarNavigationItem(key: "view:"))
        XCTAssertNil(SidebarNavigationItem(key: "some dragged text"))
    }

    func testUnsortedSectionUsesDefaultLayout() {
        XCTAssertEqual(
            SidebarNavigationOrder.resolve(saved: [], views: [first, second]),
            [.allTerminals, .customView(first), .customView(second), .section(.tasks), .section(.remote)]
        )
    }

    /// Silinen view ve bozuk/tekrarlı anahtarlar düşer.
    func testStaleAndInvalidKeysAreDropped() {
        XCTAssertEqual(
            SidebarNavigationOrder.resolve(
                saved: ["remote", "view:gone", "junk", "remote", "allTerminals", "tasks"],
                views: []
            ),
            [.section(.remote), .allTerminals, .section(.tasks)]
        )
    }

    /// Yeni doğan view varsayılan düzendeki öncülünün (son view) arkasına girer.
    func testNewViewLandsNextToItsPredecessor() {
        let saved = ["tasks", "view:a", "remote", "view:b", "allTerminals"]
        XCTAssertEqual(
            SidebarNavigationOrder.resolve(saved: saved, views: [first, second, third]),
            [.section(.tasks), .customView(first), .section(.remote), .customView(second), .customView(third), .allTerminals]
        )
    }

    /// Öncülü kayıtta olmayan satır başa girer.
    func testItemWithoutPlacedPredecessorGoesFirst() {
        XCTAssertEqual(
            SidebarNavigationOrder.resolve(saved: ["remote", "tasks"], views: [first]),
            [.allTerminals, .customView(first), .section(.remote), .section(.tasks)]
        )
    }

    func testMovingDownLandsAfterTargetAndUpBeforeIt() {
        let items: [SidebarNavigationItem] = [.allTerminals, .customView(first), .section(.tasks), .section(.remote)]
        XCTAssertEqual(
            SidebarNavigationOrder.moving(.allTerminals, onto: .section(.tasks), in: items),
            [.customView(first), .section(.tasks), .allTerminals, .section(.remote)]
        )
        XCTAssertEqual(
            SidebarNavigationOrder.moving(.section(.remote), onto: .customView(first), in: items),
            [.allTerminals, .section(.remote), .customView(first), .section(.tasks)]
        )
    }

    func testNoOpMovesReturnNil() {
        let items: [SidebarNavigationItem] = [.allTerminals, .section(.tasks)]
        XCTAssertNil(SidebarNavigationOrder.moving(.allTerminals, onto: .allTerminals, in: items))
        XCTAssertNil(SidebarNavigationOrder.moving(.customView(first), onto: .allTerminals, in: items))
    }
}
