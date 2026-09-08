import XCTest
import LumiKit
@testable import LumiState

final class PlasticChangeGroupTests: XCTestCase {
    private let changes = [
        PlasticFileChange(path: "Assets/A.cs", status: .modified),
        PlasticFileChange(path: "Assets/B.cs", status: .modified),
        PlasticFileChange(path: "Assets/Moved.cs", status: .renamed),
        PlasticFileChange(path: "Assets/New.cs", status: .added),
        PlasticFileChange(path: "notes.txt", status: .untracked),
        PlasticFileChange(path: "Assets/Old.cs", status: .deleted),
    ]

    func testGroupsByKindInFixedOrderWithSelectionCounts() {
        let groups = PlasticChangeGroup.group(changes, selected: ["Assets/A.cs", "Assets/New.cs", "notes.txt"])

        XCTAssertEqual(groups.map(\.kind), [.changed, .moved, .addedAndPrivate, .deleted])
        XCTAssertEqual(groups[0].selectedCount, 1)
        XCTAssertTrue(groups[0].isPartiallySelected)
        XCTAssertEqual(groups[1].selectedCount, 0)
        XCTAssertFalse(groups[1].isPartiallySelected)
        XCTAssertTrue(groups[2].isFullySelected, "added + private tek gruptur")
        XCTAssertEqual(groups[2].paths, ["Assets/New.cs", "notes.txt"])
    }

    func testEmptyGroupsAreOmitted() {
        let groups = PlasticChangeGroup.group([PlasticFileChange(path: "x", status: .deleted)], selected: [])
        XCTAssertEqual(groups.map(\.kind), [.deleted])
    }

    func testQueryMatchesNameOrPathCaseInsensitively() {
        XCTAssertEqual(
            PlasticChangeGroup.group(changes, selected: [], query: "assets/").flatMap(\.paths).count, 5,
            "yol eşleşmesi: notes.txt hariç hepsi"
        )
        XCTAssertEqual(PlasticChangeGroup.group(changes, selected: [], query: "NEW").flatMap(\.paths), ["Assets/New.cs"])
        XCTAssertTrue(PlasticChangeGroup.group(changes, selected: [], query: "zzz").isEmpty)
        XCTAssertEqual(PlasticChangeGroup.group(changes, selected: [], query: "  ").flatMap(\.paths).count, 6, "boşluk = filtre yok")
    }

    func testKindMetadata() {
        XCTAssertEqual(PlasticChangeGroup.Kind.changed.badgeLetter, "C")
        XCTAssertEqual(PlasticChangeGroup.Kind.moved.title, "Moved items")
        XCTAssertEqual(PlasticChangeGroup.Kind.addedAndPrivate.representativeStatus, .added)
        XCTAssertEqual(PlasticChangeGroup.Kind.kind(for: .untracked), .addedAndPrivate)
    }
}
