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
