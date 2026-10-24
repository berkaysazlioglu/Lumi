import Foundation
import LumiTestSupport
import XCTest

@testable import LumiKit

/// Tasks planı, Faz 1: saf model kuralları — kolonlama, filtre, atama
/// seçicisinin sırası, beyan maskesi, adres doğrulaması.
final class TaskModelTests: XCTestCase {
    private let source = TaskSourceID("s1")
    private let me = TaskUser(id: "me", name: "Me")

    private func entry(_ item: TaskItem, source: TaskSourceID? = nil) -> TaskEntry {
        TaskEntry(source: source ?? self.source, item: item)
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    // MARK: - Board

    func testColumnsFollowFixedStatusOrder() {
        let columns = TaskBoard.columns([], filter: TaskFilter(), me: { _ in nil })
        XCTAssertEqual(columns.map(\.status), [.todo, .inProgress, .inReview, .done])
    }

    func testOpenColumnsSortAttentionThenPriorityThenRecency() {
        let entries = [
            entry(.fake(id: "old-high", updatedAt: at(1), priority: .high)),
            entry(.fake(id: "new-low", updatedAt: at(9), priority: .low)),
            entry(.fake(id: "new-high", updatedAt: at(5), priority: .high)),
            entry(.fake(id: "broken", updatedAt: at(0), needsAttention: true)),
        ]
        let todo = TaskBoard.columns(entries, filter: TaskFilter(), me: { _ in nil })[0]
        XCTAssertEqual(todo.entries.map(\.item.id), ["broken", "new-high", "old-high", "new-low"])
    }

    func testDoneColumnIsCappedUnlessShowingAll() {
        let done = (0..<25).map { entry(.fake(id: "d\($0)", status: .done, updatedAt: at(Double($0)))) }
        let capped = TaskBoard.columns(done, filter: TaskFilter(), me: { _ in nil })[3]
        XCTAssertEqual(capped.entries.count, TaskBoard.doneLimit)
        XCTAssertEqual(capped.hiddenCount, 5)
        XCTAssertEqual(capped.entries.first?.item.id, "d24", "en yeni üstte")

        let all = TaskBoard.columns(done, filter: TaskFilter(), me: { _ in nil }, showAllDone: true)[3]
        XCTAssertEqual(all.entries.count, 25)
        XCTAssertEqual(all.hiddenCount, 0)
    }

    func testFilterByQueryProjectAndAssignee() {
        let ada = TaskUser(id: "ada", name: "Ada")
        let entries = [
            entry(.fake(id: "1", title: "Fix login", assignee: me, project: TaskProjectRef(key: "api"))),
            entry(.fake(id: "2", title: "Login copy", assignee: ada, project: TaskProjectRef(key: "web"))),
            entry(.fake(id: "3", title: "Unrelated")),
        ]
        func ids(_ filter: TaskFilter) -> [String] {
            TaskBoard.rows(entries, filter: filter, me: { _ in self.me }).map(\.item.id).sorted()
        }
        XCTAssertEqual(ids(TaskFilter(query: "login")), ["1", "2"])
        XCTAssertEqual(ids(TaskFilter(projectKey: "web")), ["2"])
        XCTAssertEqual(ids(TaskFilter(assignee: .me)), ["1"])
        XCTAssertEqual(ids(TaskFilter(assignee: .unassigned)), ["3"])
        XCTAssertEqual(ids(TaskFilter(assignee: .user(id: "ada"))), ["2"])
        XCTAssertEqual(ids(TaskFilter(source: TaskSourceID("other"))), [])
    }

    func testMeFilterMatchesNothingWithoutMe() {
        let entries = [entry(.fake(id: "1", assignee: me))]
        XCTAssertTrue(TaskBoard.rows(entries, filter: TaskFilter(assignee: .me), me: { _ in nil }).isEmpty)
    }

    // MARK: - Atama seçicisi

    func testYouComesFirstAndIsNotDuplicated() {
        let users = [TaskUser(id: "z", name: "Zed"), me, TaskUser(id: "a", name: "amy")]
        let options = TaskUserOrdering.options(users: users, me: me)
        XCTAssertEqual(options.map(\.user.id), ["me", "a", "z"])
        XCTAssertTrue(options[0].isMe)
        XCTAssertEqual(options[0].title, "You (Me)")
    }

    func testOptionsWithoutMeAreSortedByName() {
        let options = TaskUserOrdering.options(users: [TaskUser(id: "b", name: "Bo"), TaskUser(id: "a", name: "Al")], me: nil)
        XCTAssertEqual(options.map(\.user.id), ["a", "b"])
        XCTAssertFalse(options.contains(where: \.isMe))
    }

    // MARK: - Beyan

    func testCanAssignNeedsWritableFieldAndACandidate() {
        XCTAssertTrue(TaskSourceInfo(capabilities: [.users], fields: [.assignee: .readWrite]).canAssign)
        XCTAssertTrue(TaskSourceInfo(fields: [.assignee: .readWrite], me: me).canAssign, "users yoksa yalnız You")
        XCTAssertFalse(TaskSourceInfo(fields: [.assignee: .readWrite]).canAssign, "aday yok")
        XCTAssertFalse(TaskSourceInfo(capabilities: [.users], fields: [.assignee: .read], me: me).canAssign)
    }

    func testMaskOnlyRemovesDeclarations() {
        let info = TaskSourceInfo.fakeFull()
        let masked = info.masked(capabilities: [.create], fields: [.priority])
        XCTAssertFalse(masked.supports(.create))
        XCTAssertTrue(masked.supports(.delete))
        XCTAssertFalse(masked.canRead(.priority))
        XCTAssertTrue(masked.canWrite(.assignee))
    }

    func testNewerMajorVersionIsUnsupported() {
        XCTAssertTrue(TaskSourceInfo(version: 1).isVersionSupported)
        XCTAssertFalse(TaskSourceInfo(version: 2).isVersionSupported)
    }

    // MARK: - Yama ve kimlik

    func testPatchAppliesOnlyGivenFieldsAndClearsAttention() {
        let original = TaskItem.fake(id: "1", status: .todo, priority: .low, assignee: me, needsAttention: true)
        let moved = TaskPatch(status: .done).applied(to: original, now: at(50))
        XCTAssertEqual(moved.status, .done)
        XCTAssertFalse(moved.needsAttention)
        XCTAssertEqual(moved.priority, .low)
        XCTAssertEqual(moved.assignee, me)
        XCTAssertEqual(moved.updatedAt, at(50))
        XCTAssertNil(TaskPatch(assignee: .unassign).applied(to: original, now: at(1)).assignee)
    }

    func testTaskKeyTransferRoundTripKeepsSeparatorsInID() {
        let key = TaskKey(source: TaskSourceID("A-B"), id: "repo|42")
        XCTAssertEqual(TaskKey(transferValue: key.transferValue), key)
        XCTAssertNil(TaskKey(transferValue: "no-separator"))
        XCTAssertNil(TaskKey(transferValue: "|id"))
    }

    func testInitialsUseTwoWordsOrTwoLetters() {
        XCTAssertEqual(TaskUser(id: "1", name: "Grace Hopper").initials, "GH")
        XCTAssertEqual(TaskUser(id: "2", name: "linus").initials, "LI")
    }

    // MARK: - Adres

    func testEndpointRequiresHTTPSExceptLoopback() {
        XCTAssertEqual(try TaskEndpoint.normalize(" my-app.herokuapp.com/ ").get().absoluteString, "https://my-app.herokuapp.com")
        XCTAssertEqual(try TaskEndpoint.normalize("http://localhost:3000").get().absoluteString, "http://localhost:3000")
        XCTAssertEqual(try TaskEndpoint.normalize("http://127.0.0.1:8080/").get().absoluteString, "http://127.0.0.1:8080")
        XCTAssertEqual(TaskEndpoint.normalize("http://example.com"), .failure(.insecure))
        XCTAssertEqual(TaskEndpoint.normalize("   "), .failure(.empty))
        XCTAssertEqual(TaskEndpoint.normalize("ftp://example.com"), .failure(.invalid))
    }
}

/// Birleşik yazım, hata kaydı ve ajan yardımcıları.
final class TaskSupportTests: XCTestCase {
    func testPatchMergingLaterFieldsWin() {
        let merged = TaskPatch(status: .inProgress, priority: .low)
            .merging(TaskPatch(status: .done, assignee: .unassign))
        XCTAssertEqual(merged, TaskPatch(status: .done, priority: .low, assignee: .unassign))
        XCTAssertTrue(TaskPatch().isEmpty)
        XCTAssertFalse(merged.isEmpty)
    }

    func testFailureSummaryAndAgentReportCarryDetails() {
        let failure = TaskRequestFailure(
            kind: .invalidResponse("validation"), operation: .update, request: "PATCH /lumi/v1/tasks/7",
            httpStatus: 422, serverCode: "validation_failed", serverMessage: "bad status",
            responseExcerpt: String(repeating: "x", count: 2000), taskID: "7"
        )
        XCTAssertEqual(failure.summary, "HTTP 422 · validation_failed — bad status")
        XCTAssertEqual(failure.responseExcerpt?.count, TaskRequestFailure.excerptLimit)
        let report = failure.agentReport
        XCTAssertTrue(report.contains("PATCH /lumi/v1/tasks/7"))
        XCTAssertTrue(report.contains("Server error code: validation_failed"))
        XCTAssertTrue(report.contains("Expected:"))
    }

    func testFromWrapsPlainErrorsAndKeepsRichOnes() {
        let wrapped = TaskRequestFailure.from(TaskProviderError.unauthorized, operation: .listTasks)
        XCTAssertEqual(wrapped.kind, .unauthorized)
        XCTAssertEqual(wrapped.operation, .listTasks)
        let rich = TaskRequestFailure(kind: .conflict, operation: .update, httpStatus: 409)
        XCTAssertEqual(TaskRequestFailure.from(rich, operation: .delete).id, rich.id)
    }

    func testBranchNameIsSlugged() {
        let task = TaskItem.fake(id: "DEMO-12", title: "Fix: login (OAuth) — redirect!!")
        XCTAssertEqual(TaskAgentPrompt.branchName(for: task), "task/demo-12-fix-login-oauth-redirect")
    }

    func testPromptMentionsSubmitToolAndOptionalBody() {
        var task = TaskItem.fake(id: "1", title: "Do it")
        task.body = "Details here"
        XCTAssertTrue(TaskAgentPrompt.make(task: task, includeBody: true).contains("Details here"))
        XCTAssertFalse(TaskAgentPrompt.make(task: task, includeBody: false).contains("Details here"))
        XCTAssertTrue(TaskAgentPrompt.make(task: task, includeBody: false).contains(TaskAgentPrompt.submitTool))
    }

    func testProjectMatcherNeedsSingleCandidate() {
        let paths = ["/w/api", "/w/web", "/other/API"]
        XCTAssertEqual(TaskProjectMatcher.match(TaskProjectRef(key: "web"), in: paths), "/w/web")
        XCTAssertNil(TaskProjectMatcher.match(TaskProjectRef(key: "api"), in: paths), "iki aday — kullanıcı seçer")
        XCTAssertNil(TaskProjectMatcher.match(TaskProjectRef(key: "nope"), in: paths))
        XCTAssertEqual(TaskProjectMatcher.match(TaskProjectRef(key: "x", name: "Web"), in: paths), "/w/web")
    }

    func testImageDisplayNameFallsBackToPath() {
        XCTAssertEqual(TaskImage(url: URL(string: "https://x.dev/a/shot.png")!).displayName, "shot.png")
        XCTAssertEqual(TaskImage(url: URL(string: "https://x.dev/a/shot.png")!, name: "Mockup").displayName, "Mockup")
    }
}

/// Kaynak başına prompt şablonu (karar 137 eki).
final class TaskPromptTemplateTests: XCTestCase {
    private var task: TaskItem {
        var item = TaskItem.fake(id: "7", title: "Fix login")
        item.body = "Details"
        return item
    }

    func testWrapSkipsEmptyPartsAndTrims() {
        XCTAssertEqual(TaskPromptTemplate().wrap("core"), "core")
        XCTAssertEqual(TaskPromptTemplate(prefix: "  pre \n", suffix: "").wrap("core"), "pre\n\ncore")
        XCTAssertEqual(TaskPromptTemplate(prefix: "pre", suffix: "post").wrap("core"), "pre\n\ncore\n\npost")
        XCTAssertTrue(TaskPromptTemplate(prefix: " \n", suffix: "").isEmpty)
    }

    func testAgentPromptKeepsSubmitInstructionLast() {
        let prompt = TaskAgentPrompt.make(task: task, includeBody: true, template: TaskPromptTemplate(prefix: "PRE", suffix: "POST"))
        XCTAssertTrue(prompt.hasPrefix("PRE\n\nWork on task 7: Fix login\n\nDetails\n\nPOST\n\n"))
        XCTAssertTrue(prompt.hasSuffix("Never mark it done yourself."))
    }

    func testCopyTextHasNoSubmitInstruction() {
        let text = TaskAgentPrompt.copyText(task: task, includeBody: false, template: TaskPromptTemplate(suffix: "POST"))
        XCTAssertEqual(text, "Work on task 7: Fix login\n\nPOST")
    }
}

/// Ajan prompt'una görsel listesi (2026-10-25).
final class TaskAttachmentPromptTests: XCTestCase {
    func testAttachmentsGoBeforeTheSubmitInstruction() {
        let prompt = TaskAgentPrompt.make(task: .fake(id: "1", title: "T"), includeBody: false)
        let result = TaskAgentPrompt.inserting(attachments: [URL(fileURLWithPath: "/a/1-x.png")], into: prompt)
        XCTAssertTrue(result.contains("Work on task 1: T\n\nImages attached to this task — open them with the Read tool:\n- /a/1-x.png\n\nWhen the work"))
        XCTAssertEqual(TaskAgentPrompt.inserting(attachments: [URL(fileURLWithPath: "/a/1-x.png")], into: "custom"), "custom\n\nImages attached to this task — open them with the Read tool:\n- /a/1-x.png")
        XCTAssertEqual(TaskAgentPrompt.inserting(attachments: [], into: "same"), "same")
    }
}
