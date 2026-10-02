import XCTest
@testable import LumiServices

final class GitHubReleaseParserTests: XCTestCase {
    func testParsesTagPageAndDate() throws {
        let json = """
        {"tag_name":"v0.8.0","html_url":"https://github.com/berkaysazlioglu/Lumi/releases/tag/v0.8.0",
         "published_at":"2026-10-01T11:54:56Z","draft":false,"assets":[]}
        """
        let release = try XCTUnwrap(GitHubReleaseParser.parse(Data(json.utf8)))
        XCTAssertEqual(release.version.description, "0.8.0")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/berkaysazlioglu/Lumi/releases/tag/v0.8.0")
        XCTAssertNotNil(release.publishedAt)
    }

    func testRejectsNonVersionTagsAndGarbage() {
        let badTag = #"{"tag_name":"nightly","html_url":"https://example.com"}"#
        XCTAssertNil(GitHubReleaseParser.parse(Data(badTag.utf8)))
        XCTAssertNil(GitHubReleaseParser.parse(Data("not json".utf8)))
        XCTAssertNil(GitHubReleaseParser.parse(Data(#"{"tag_name":"v1.0.0"}"#.utf8)))
    }

    func testRateLimitStatusIsExplained() {
        XCTAssertTrue(GitHubReleaseService.detail(forStatus: 403).contains("rate limit"))
        XCTAssertTrue(GitHubReleaseService.detail(forStatus: 404).contains("no published release"))
    }
}
