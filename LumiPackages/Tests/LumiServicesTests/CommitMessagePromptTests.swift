import XCTest
import LumiKit
@testable import LumiServices

final class CommitMessagePromptTests: XCTestCase {
    func testBodyListsChangesWithMarkersAndAppendsDiff() {
        let request = CommitMessageRequest(
            vcsName: "Git",
            changes: [.init(path: "a.swift", status: .modified), .init(path: "b.swift", status: .untracked), .init(path: "c", status: .deleted)],
            diff: "\n--- a\n+++ b\n+line\n"
        )
        let body = CommitMessagePrompt.body(for: request)
        XCTAssertEqual(body, "Changed files:\nM a.swift\n? b.swift\nD c\n\nDiff:\n--- a\n+++ b\n+line\n")
    }

    func testBodyOmitsDiffSectionWhenDiffIsBlank() {
        let body = CommitMessagePrompt.body(for: CommitMessageRequest(vcsName: "Plastic SCM", changes: [.init(path: "x", status: .added)], diff: "  \n"))
        XCTAssertEqual(body, "Changed files:\nA x\n")
    }

    func testBodyTruncatesHugeDiffWithMarker() {
        let diff = String(repeating: "x", count: CommitMessagePrompt.maxDiffCharacters + 10)
        let body = CommitMessagePrompt.body(for: CommitMessageRequest(vcsName: "Git", changes: [.init(path: "x", status: .modified)], diff: diff))
        XCTAssertTrue(body.contains("[… diff truncated …]"))
        XCTAssertFalse(body.contains(diff), "diff'in tamamı değil, ilk maxDiffCharacters karakteri gider")
        XCTAssertTrue(body.contains(String(repeating: "x", count: CommitMessagePrompt.maxDiffCharacters)))
    }

    func testInstructionMentionsVCSAndSingleLineRule() {
        let instruction = CommitMessagePrompt.instruction(vcsName: "Plastic SCM")
        XCTAssertTrue(instruction.contains("Plastic SCM"))
        XCTAssertTrue(instruction.contains("ONE line"))
        XCTAssertTrue(instruction.contains("in English"), "kullanıcının dil ayarı yanıta sızmasın")
        XCTAssertTrue(instruction.contains("never which files were"), "dosya adı sayan mesaj istenmez")
    }

    func testCleanReplyStripsQuotesTrailingPeriodAndExtraLines() {
        XCTAssertEqual(CommitMessagePrompt.cleanReply("\n\"Add jump buffering.\"\n\nSecond line"), "Add jump buffering")
        XCTAssertEqual(CommitMessagePrompt.cleanReply("`Fix typo`"), "Fix typo")
        XCTAssertEqual(CommitMessagePrompt.cleanReply("  Plain message  "), "Plain message")
        XCTAssertNil(CommitMessagePrompt.cleanReply("\n  \n"))
        XCTAssertNil(CommitMessagePrompt.cleanReply("\"\""))
    }
}
