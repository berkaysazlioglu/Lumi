import Foundation
import XCTest
@testable import LumiKit

/// Karar 123: orchestrator talimatı canlı durumdan üretilir — araç kataloğu,
/// aktif projeler ve izlenen terminaller metne gömülür.
final class OrchestratorPromptTests: XCTestCase {
    func testEmbedsEveryToolWithItsSignature() {
        let prompt = OrchestratorPrompt.make(projects: "{}", watched: [])
        for spec in OrchestratorTools.specs {
            XCTAssertTrue(prompt.contains("`\(spec.name)`"), "katalogda yok: \(spec.name)")
        }
        XCTAssertTrue(prompt.contains("`send_to_terminal`(message, terminal_id)"))
        XCTAssertTrue(prompt.contains("`start_terminal`(path, prompt?)"))
        XCTAssertTrue(prompt.contains("`list_terminals`(query?)"))
        XCTAssertFalse(prompt.contains("ask_project"))
    }

    func testForbidsDoingTheWorkAndExplainsMonitoring() {
        let prompt = OrchestratorPrompt.make(projects: "{}", watched: [])
        XCTAssertTrue(prompt.contains("Use ONLY the tools listed above"))
        XCTAssertTrue(prompt.contains("Never do the work yourself"))
        XCTAssertTrue(prompt.contains("no approval step"))
        XCTAssertTrue(prompt.contains(OrchestratorPrompt.activityOpen))
        XCTAssertTrue(prompt.contains("Turkish"))
    }

    func testEmbedsProjectsAndWatchedTerminals() {
        let prompt = OrchestratorPrompt.make(
            projects: #"{"projects":[{"name":"api","path":"/p/api"}]}"#,
            watched: [#""login" (t-1, working)"#]
        )
        XCTAssertTrue(prompt.contains(#"{"projects":[{"name":"api","path":"/p/api"}]}"#))
        XCTAssertTrue(prompt.contains(#"- "login" (t-1, working)"#))
        XCTAssertTrue(OrchestratorPrompt.make(projects: "{}", watched: []).contains("(none yet)"))
    }

    func testHugeProjectTreeIsTruncated() {
        let huge = String(repeating: "x", count: OrchestratorPrompt.maxProjectsCharacters + 500)
        let prompt = OrchestratorPrompt.make(projects: huge, watched: [])
        XCTAssertTrue(prompt.contains("truncated — call list_projects"))
        XCTAssertFalse(prompt.contains(huge))
    }
}
