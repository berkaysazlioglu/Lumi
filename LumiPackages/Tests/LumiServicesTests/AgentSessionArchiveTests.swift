import LumiKit
@testable import LumiServices
import XCTest

final class AgentSessionArchiveTests: XCTestCase {
    func testRoundTripPreservesRecordsAndSubagents() throws {
        let archive = AgentSessionArchive(
            provider: .claude, sessionID: "abc-123", cwd: "/repo", title: "Title", fileName: "abc-123.jsonl",
            records: [["type": "user", "message": ["content": "hi"]]],
            subagents: [.init(id: "a1", meta: ["agentType": "Explore"], records: [["type": "user"]])]
        )
        let decoded = try AgentSessionArchive.decode(try archive.encode())
        XCTAssertEqual(decoded.provider, .claude)
        XCTAssertEqual(decoded.sessionID, "abc-123")
        XCTAssertEqual(decoded.cwd, "/repo")
        XCTAssertEqual(decoded.fileName, "abc-123.jsonl")
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertEqual(decoded.subagents.first?.id, "a1")
        XCTAssertEqual(decoded.subagents.first?.meta?["agentType"] as? String, "Explore")
    }

    func testRejectsForeignAndMalformedDocuments() {
        XCTAssertThrowsError(try AgentSessionArchive.decode(Data("[]".utf8)))
        XCTAssertThrowsError(try AgentSessionArchive.decode(Data(#"{"format":"other","version":1}"#.utf8)))
        XCTAssertThrowsError(try AgentSessionArchive.decode(Data(
            #"{"format":"lumi-agent-session","version":1,"provider":"claude","sessionID":"../x","records":[{}]}"#.utf8
        )))
        XCTAssertThrowsError(try AgentSessionArchive.decode(Data(
            #"{"format":"lumi-agent-session","version":1,"provider":"claude","sessionID":"ok","records":[]}"#.utf8
        )))
        XCTAssertThrowsError(try AgentSessionArchive.decode(Data(
            #"{"format":"lumi-agent-session","version":99,"provider":"claude","sessionID":"ok","records":[{}]}"#.utf8
        )))
    }

    func testUnsafeFileNameFallsBackToSessionID() throws {
        let decoded = try AgentSessionArchive.decode(Data(
            #"{"format":"lumi-agent-session","version":1,"provider":"codex","sessionID":"ok","fileName":"../evil.jsonl","records":[{}]}"#.utf8
        ))
        XCTAssertEqual(decoded.fileName, "ok.jsonl")
    }
}
