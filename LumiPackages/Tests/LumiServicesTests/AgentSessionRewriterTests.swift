@testable import LumiServices
import XCTest

final class AgentSessionRewriterTests: XCTestCase {
    func testPathRootIsReplacedOnlyAtBoundaries() {
        let rewriter = AgentSessionRewriter(replacements: [
            .init(from: "/Users/a/Lumi", to: "/home/b/Lumi", requiresPathBoundary: true),
        ])
        XCTAssertEqual(rewriter.rewrite("cd /Users/a/Lumi/LumiPackages && ls /Users/a/Lumi"), "cd /home/b/Lumi/LumiPackages && ls /home/b/Lumi")
        XCTAssertEqual(rewriter.rewrite("/Users/a/Lumi2/x"), "/Users/a/Lumi2/x")
        XCTAssertEqual(rewriter.rewrite("\"/Users/a/Lumi\""), "\"/home/b/Lumi\"")
    }

    func testRewritesNestedStringsAndSessionIDs() {
        let rewriter = AgentSessionRewriter(replacements: [
            .init(from: "/Users/a/Lumi", to: "/home/b/Lumi", requiresPathBoundary: true),
            .init(from: "old-id", to: "new-id", requiresPathBoundary: false),
        ])
        let records: [[String: Any]] = [[
            "sessionId": "old-id", "cwd": "/Users/a/Lumi", "count": 3,
            "message": ["content": [["type": "tool_use", "input": ["command": "cat /Users/a/Lumi/README.md"]]]],
        ]]
        let result = rewriter.rewrite(records)
        XCTAssertEqual(result[0]["sessionId"] as? String, "new-id")
        XCTAssertEqual(result[0]["cwd"] as? String, "/home/b/Lumi")
        XCTAssertEqual(result[0]["count"] as? Int, 3)
        let input = (((result[0]["message"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["input"] as? [String: Any])
        XCTAssertEqual(input?["command"] as? String, "cat /home/b/Lumi/README.md")
    }

    func testEmptyReplacementsReturnInput() {
        let records: [[String: Any]] = [["a": "/x"]]
        XCTAssertEqual(AgentSessionRewriter(replacements: []).rewrite(records).count, 1)
        XCTAssertNil(AgentSessionRewriter(replacements: []).rewrite(nil))
    }
}
