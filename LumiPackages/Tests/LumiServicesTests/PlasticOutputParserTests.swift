import XCTest
import LumiKit
@testable import LumiServices

/// `cm` çıktılarının saf parse'ı — örnekler gerçek `cm 11.0` çıktısından.
final class PlasticOutputParserTests: XCTestCase {
    private let root = "/Users/me/wkspaces/Unity/sand_out"

    // MARK: Header / selector

    func testParseHeaderReadsChangesetRepositoryAndServer() {
        let parsed = PlasticOutputParser.parseHeader("STATUS|2105|sand_out|uncosoft@cloud\n")
        XCTAssertEqual(parsed?.changesetID, 2105)
        XCTAssertEqual(parsed?.repository, "sand_out")
        XCTAssertEqual(parsed?.server, "uncosoft@cloud")
    }

    func testParseHeaderRejectsNonWorkspaceOutput() {
        XCTAssertNil(PlasticOutputParser.parseHeader("/private/tmp is not in a workspace.\n"))
        XCTAssertNil(PlasticOutputParser.parseHeader(""))
    }

    func testParseSelectorBranchPrefersQuotedBranchName() {
        let selector = """
        Selector for workspace sand_out:
        rep "sand_out@uncosoft@cloud"
          path "/"
            smartbranch "/main/release" changeset "2105"
        """
        XCTAssertEqual(PlasticOutputParser.parseSelectorBranch(selector), "/main/release")
        XCTAssertEqual(PlasticOutputParser.parseSelectorBranch("  branch \"/main\""), "/main")
        XCTAssertNil(PlasticOutputParser.parseSelectorBranch("  changeset \"12\""))
    }

    // MARK: Status

    func testParseStatusMapsCodesAndRelativizesPaths() {
        let stdout = """
        CH|\(root)/ProjectSettings/ProjectSettings.asset|False|NO_MERGES
        AD|\(root)/Assets/New.cs|False|NO_MERGES
        DE|\(root)/Assets/Old.cs|False|NO_MERGES
        MV|\(root)/Assets/A.cs|\(root)/Assets/B.cs|NO_MERGES
        PR|\(root)/.lumi-probe.txt|False|NO_MERGES
        CO+CH|\(root)/Assets/Locked.cs|True|NO_MERGES
        IG|\(root)/Library/x.bin|False|NO_MERGES
        """
        let changes = PlasticOutputParser.parseStatus(stdout, workspacePath: root + "/")
        XCTAssertEqual(changes, [
            PlasticFileChange(path: "ProjectSettings/ProjectSettings.asset", status: .modified),
            PlasticFileChange(path: "Assets/New.cs", status: .added),
            PlasticFileChange(path: "Assets/Old.cs", status: .deleted),
            PlasticFileChange(path: "Assets/B.cs", status: .renamed),
            PlasticFileChange(path: ".lumi-probe.txt", status: .untracked),
            PlasticFileChange(path: "Assets/Locked.cs", status: .modified),
        ])
    }

    func testCompoundCodesPreferMoveDeleteAddOverCheckout() {
        // Gerçek word-puzzle çalışma alanı çıktısı: CO+MV, CO+RP, CO+CH, CO
        XCTAssertEqual(PlasticOutputParser.status(forCode: "CO+MV"), .renamed)
        XCTAssertEqual(PlasticOutputParser.status(forCode: "CO+RP"), .modified)
        XCTAssertEqual(PlasticOutputParser.status(forCode: "RP"), .modified)
        XCTAssertEqual(PlasticOutputParser.status(forCode: "CO+CH"), .modified)
        XCTAssertEqual(PlasticOutputParser.status(forCode: "CO"), .modified)
        XCTAssertEqual(PlasticOutputParser.status(forCode: "CO+DE"), .deleted)
        XCTAssertNil(PlasticOutputParser.status(forCode: "IG"))
        XCTAssertNil(PlasticOutputParser.status(forCode: "XX+YY"))
    }

    func testParseStatusAcceptsLinesWithoutMergeField() {
        let stdout = "CO+RP|\(root)/Assets/Include.cginc|False\n"
        XCTAssertEqual(PlasticOutputParser.parseStatus(stdout, workspacePath: root), [PlasticFileChange(path: "Assets/Include.cginc", status: .modified)])
    }

    func testParseStatusSkipsPathsOutsideWorkspaceAndMalformedLines() {
        let stdout = "CH|/elsewhere/file.cs|False|NO_MERGES\nCH\n\n"
        XCTAssertEqual(PlasticOutputParser.parseStatus(stdout, workspacePath: root), [])
    }

    // MARK: Changesets

    func testParseChangesetsReadsFieldsAndISODate() {
        let stdout = "2197\u{1F}/main\u{1F}balkan@zynga.com\u{1F}2026-07-07T11:24:09+03:00\u{1F}2191\u{1F}non consumable fix\n"
        let changesets = PlasticOutputParser.parseChangesets(stdout)
        XCTAssertEqual(changesets.count, 1)
        let changeset = changesets[0]
        XCTAssertEqual(changeset.changesetID, 2197)
        XCTAssertEqual(changeset.branch, "/main")
        XCTAssertEqual(changeset.owner, "balkan@zynga.com")
        XCTAssertEqual(changeset.parentID, 2191)
        XCTAssertEqual(changeset.comment, "non consumable fix")
        XCTAssertEqual(changeset.date, ISO8601DateFormatter().date(from: "2026-07-07T08:24:09Z"))
    }

    func testParseChangesetsKeepsTabsAndPipesInCommentAndJoinsMultilineComments() {
        let stdout = """
        2§/main§owner§2026-07-07T11:24:09+03:00§1§first\tline | still comment
        second line
        1§/main§owner§2026-07-06T11:24:09+03:00§§root
        """.replacingOccurrences(of: "§", with: "\u{1F}")
        let changesets = PlasticOutputParser.parseChangesets(stdout)
        XCTAssertEqual(changesets.map(\.changesetID), [2, 1])
        XCTAssertEqual(changesets[0].comment, "first\tline | still comment\nsecond line")
        XCTAssertNil(changesets[1].parentID)
        XCTAssertEqual(changesets[1].comment, "root")
    }

    func testParseChangesetsSkipsRecordsWithUnparsableDate() {
        let stdout = "5\u{1F}/main\u{1F}owner\u{1F}18.06.2026 11:54:58\u{1F}4\u{1F}locale date\n"
        XCTAssertEqual(PlasticOutputParser.parseChangesets(stdout), [])
    }
}
