import XCTest
@testable import LumiMobileKit

final class AddableGroupsTests: XCTestCase {
    private let locations = [LooseLocation(path: "/Users/me", label: "~"),
                             LooseLocation(path: "/Users/me/wkspaces", label: "~/wkspaces")]
    private let repos = [
        Repo(name: "Lumi", path: "/Users/me/wkspaces/Swift/Lumi"),
        Repo(name: "orca", path: "/Users/me/wkspaces/Github/orca"),
        Repo(name: "Collectioner", path: "/Users/me/wkspaces/Swift/Collectioner"),
        Repo(name: "scratch", path: "/tmp/scratch"),
    ]

    func testGroupsByParentFolderSortedAndHomeAbbreviated() {
        let groups = addableGroups(repos, locations: locations)
        XCTAssertEqual(groups.map(\.title), ["/tmp", "~/wkspaces/Github", "~/wkspaces/Swift"])
        XCTAssertEqual(groups[2].repos.map(\.name), ["Collectioner", "Lumi"])
    }

    func testQueryMatchesNameOrPathAndDropsEmptyGroups() {
        XCTAssertEqual(addableGroups(repos, locations: locations, query: "lUm").map(\.title), ["~/wkspaces/Swift"])
        XCTAssertEqual(addableGroups(repos, locations: locations, query: "github").flatMap(\.repos).map(\.name), ["orca"])
        XCTAssertEqual(addableGroups(repos, locations: locations, query: "nope"), [])
    }

    func testWithoutHomeLocationPathsStayAbsolute() {
        XCTAssertEqual(addableGroups([repos[0]], locations: []).map(\.title), ["/Users/me/wkspaces/Swift"])
    }
}
