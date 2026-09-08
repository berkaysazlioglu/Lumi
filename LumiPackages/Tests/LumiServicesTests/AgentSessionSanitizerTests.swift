@testable import LumiServices
import XCTest

final class AgentSessionSanitizerTests: XCTestCase {
    func testDropsPersonalRecordsAndKeepsConversation() {
        let records: [[String: Any]] = [
            ["type": "user", "uuid": "u1", "parentUuid": NSNull(), "message": ["role": "user", "content": "hi"]],
            ["type": "attachment", "uuid": "a1", "parentUuid": "u1",
             "attachment": ["type": "session_context", "context": ["userEmail": "me@example.com"]]],
            ["type": "attachment", "uuid": "a2", "parentUuid": "a1", "attachment": ["type": "instructions", "files": []]],
            ["type": "attachment", "uuid": "a3", "parentUuid": "a2", "attachment": ["type": "file", "filename": "x.swift"]],
            ["type": "assistant", "uuid": "s1", "parentUuid": "a3", "message": ["role": "assistant", "content": []]],
            ["type": "cost-state", "totalCostUSD": 1.5],
            ["type": "file-history-snapshot", "snapshot": [:]],
            ["type": "system", "subtype": "stop_hook_summary", "uuid": "h1", "parentUuid": "s1", "hookInfos": []],
            ["type": "system", "subtype": "local_command", "uuid": "c1", "parentUuid": "h1", "content": "/model"],
            ["type": "last-prompt", "leafUuid": "h1", "lastPrompt": "hi"],
        ]

        let result = AgentSessionSanitizer.sanitize(records)

        XCTAssertEqual(result.map { $0["type"] as? String }, ["user", "attachment", "assistant", "system", "last-prompt"])
        XCTAssertFalse(String(describing: result).contains("me@example.com"))
        XCTAssertEqual(result[1]["parentUuid"] as? String, "u1", "düşen a1/a2 üstünden atlanır")
        XCTAssertEqual(result[2]["parentUuid"] as? String, "a3")
        XCTAssertEqual(result[3]["parentUuid"] as? String, "s1", "düşen hook özeti üstünden atlanır")
        XCTAssertEqual(result[4]["leafUuid"] as? String, "s1")
    }

    func testChainRootedAtDroppedRecordBecomesNull() {
        let records: [[String: Any]] = [
            ["type": "attachment", "uuid": "a1", "parentUuid": NSNull(), "attachment": ["type": "environment"]],
            ["type": "user", "uuid": "u1", "parentUuid": "a1", "message": ["role": "user", "content": "hi"]],
        ]
        let result = AgentSessionSanitizer.sanitize(records)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0]["parentUuid"] is NSNull)
    }

    func testUnknownAttachmentTypesAreDroppedByDefault() {
        XCTAssertTrue(AgentSessionSanitizer.shouldDrop(["type": "attachment", "attachment": ["type": "brand_new_kind"]]))
        XCTAssertFalse(AgentSessionSanitizer.shouldDrop(["type": "attachment", "attachment": ["type": "queued_command"]]))
        XCTAssertFalse(AgentSessionSanitizer.shouldDrop(["type": "queue-operation"]))
        XCTAssertFalse(AgentSessionSanitizer.shouldDrop(["type": "system", "subtype": "turn_duration"]))
    }
}
