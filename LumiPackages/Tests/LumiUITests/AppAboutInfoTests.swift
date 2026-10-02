import XCTest
@testable import LumiUI

final class AppAboutInfoTests: XCTestCase {
    func testPackagedBuildShowsVersionAndCommit() {
        let info = AppAboutInfo(
            info: ["CFBundleShortVersionString": "0.8.0", "LumiGitCommit": "0b373a1"],
            system: "macOS 15.0.0 · arm64"
        )
        XCTAssertEqual(info.versionLine, "0.8.0 (0b373a1)")
        XCTAssertEqual(info.system, "macOS 15.0.0 · arm64")
    }

    func testDevBuildWithoutPlistFallsBackToDev() {
        let info = AppAboutInfo(info: nil, system: "")
        XCTAssertEqual(info.versionLine, AppAboutInfo.devVersion)
        XCTAssertNil(info.commit)
    }

    func testUnknownOrEmptyCommitIsHidden() {
        for commit in ["unknown", "", "  "] {
            let info = AppAboutInfo(
                info: ["CFBundleShortVersionString": "0.8.0", "LumiGitCommit": commit],
                system: ""
            )
            XCTAssertEqual(info.versionLine, "0.8.0", "commit=\(commit)")
        }
    }

    func testLinksPointToTheRepository() {
        XCTAssertEqual(AppAboutInfo.repositoryURL.absoluteString, "https://github.com/berkaysazlioglu/Lumi")
        XCTAssertEqual(AppAboutInfo.releasesURL.absoluteString, "https://github.com/berkaysazlioglu/Lumi/releases")
    }
}
