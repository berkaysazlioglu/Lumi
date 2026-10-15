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

    /// Karar 118: kurulum zip'i mimariye, checksum dosyası sürüme göre seçilir.
    func testParsesAssetsAndSelectsPackageForArchitecture() throws {
        let json = """
        {"tag_name":"v0.9.0","html_url":"https://github.com/o/r/releases/tag/v0.9.0","assets":[
          {"name":"Lumi-0.9.0-arm64-mac.dmg","browser_download_url":"https://x/a.dmg"},
          {"name":"Lumi-0.9.0-arm64-mac.zip","browser_download_url":"https://x/arm.zip"},
          {"name":"Lumi-0.9.0-x86_64-mac.zip","browser_download_url":"https://x/intel.zip"},
          {"name":"SHA256SUMS-0.9.0.txt","browser_download_url":"https://x/sums.txt"},
          {"name":"broken"}
        ]}
        """
        let release = try XCTUnwrap(GitHubReleaseParser.parse(Data(json.utf8)))
        XCTAssertEqual(release.assets.count, 4, "bozuk kayıt diğerlerini düşürmez")
        XCTAssertEqual(release.packageAsset(architecture: "arm64")?.downloadURL.absoluteString, "https://x/arm.zip")
        XCTAssertEqual(release.packageAsset(architecture: "x86_64")?.downloadURL.absoluteString, "https://x/intel.zip")
        XCTAssertEqual(release.checksumsAsset?.name, "SHA256SUMS-0.9.0.txt")
    }

    /// Ekli tag'de (`v0.9.0-rc1`) sürüm eki atar ama asset adları eki taşır.
    func testAssetNamesFollowTheTagIncludingSuffix() throws {
        let json = """
        {"tag_name":"v0.9.0-rc1","html_url":"https://github.com/o/r/releases/tag/v0.9.0-rc1","assets":[
          {"name":"Lumi-0.9.0-rc1-arm64-mac.zip","browser_download_url":"https://x/arm.zip"},
          {"name":"SHA256SUMS-0.9.0-rc1.txt","browser_download_url":"https://x/sums.txt"}
        ]}
        """
        let release = try XCTUnwrap(GitHubReleaseParser.parse(Data(json.utf8)))
        XCTAssertEqual(release.version.description, "0.9.0")
        XCTAssertNotNil(release.packageAsset(architecture: "arm64"))
        XCTAssertNotNil(release.checksumsAsset)
    }

    func testRateLimitStatusIsExplained() {
        XCTAssertTrue(GitHubReleaseService.detail(forStatus: 403).contains("rate limit"))
        XCTAssertTrue(GitHubReleaseService.detail(forStatus: 404).contains("no published release"))
    }
}
