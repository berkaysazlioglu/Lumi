import XCTest
@testable import LumiTerminal

final class PTYSmokeTesterTests: XCTestCase {
    func testSmokeTestSucceedsOnHealthySystem() async throws {
        let tester = PTYSmokeTester()
        try await tester.runSmokeTest()
    }
}
