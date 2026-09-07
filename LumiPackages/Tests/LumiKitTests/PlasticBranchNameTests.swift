import XCTest
@testable import LumiKit

final class PlasticBranchNameTests: XCTestCase {
    func testKeepsShortBranchesVerbatim() {
        XCTAssertEqual(PlasticBranchName.display("/main"), "/main")
        XCTAssertEqual(PlasticBranchName.display("/main/release"), "/main/release")
        XCTAssertEqual(PlasticBranchName.display("main"), "main")
    }

    func testShowsParentAndCurrentWithEllipsisForDeepBranches() {
        XCTAssertEqual(PlasticBranchName.display("/main/release/hotfix-ads"), "…/release/hotfix-ads")
        XCTAssertEqual(PlasticBranchName.display("/main/a/b/c/d"), "…/c/d")
    }

    func testIgnoresEmptyComponents() {
        XCTAssertEqual(PlasticBranchName.display("/main//release/"), "/main//release/")
        XCTAssertEqual(PlasticBranchName.display(""), "")
    }
}
