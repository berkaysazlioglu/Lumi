import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiServices

/// Custom adapter'ın protokol sözleşmesi (Tasks planı, Faz 2): istek biçimi,
/// hoşgörülü okuma, sayfalama ve hataların ayrıntısı.
final class LumiTasksHTTPProviderTests: XCTestCase {
    private let base = URL(string: "https://tasks.example.com")!

    private func make(_ transport: FakeHTTPTransport, token: String? = "secret") -> LumiTasksHTTPProvider {
        LumiTasksHTTPProvider(baseURL: base, token: token, transport: transport)
    }

    private let discovery: [String: Any] = [
        "protocol": "lumi-tasks", "version": 1, "name": "Acme",
        "me": ["id": 7, "name": "Ada"],
        "capabilities": ["create", "users", "teleport"],
        "fields": ["body": "rw", "priority": "r", "unknown": "rw", "labels": "x"],
    ]

    // MARK: - Discovery

    func testDiscoveryParsesDeclarationsAndIgnoresUnknowns() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/v1", status: 200, json: discovery)
        let info = try await make(transport).discover()

        XCTAssertEqual(info.name, "Acme")
        XCTAssertEqual(info.capabilities, [.create, .users])
        XCTAssertEqual(info.fields, [.body: .readWrite, .priority: .read])
        XCTAssertEqual(info.me, TaskUser(id: "7", name: "Ada"))
        let request = transport.requests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.url?.absoluteString, "https://tasks.example.com/lumi/v1")
    }

    func testWrongProtocolExplainsWhatWasExpected() async {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/v1", status: 200, json: ["protocol": "todo-api", "version": 1])
        do {
            _ = try await make(transport).discover()
            XCTFail("accepted")
        } catch let failure as TaskRequestFailure {
            XCTAssertEqual(failure.operation, .discover)
            XCTAssertTrue(failure.serverMessage?.contains(#""protocol": "lumi-tasks""#) == true)
            XCTAssertTrue(failure.serverMessage?.contains("todo-api") == true)
        } catch { XCTFail("\(error)") }
    }

    // MARK: - Liste

    func testListFollowsCursorAndStopsOnRepeat() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/v1/tasks", status: 200, json: [
            "tasks": [["id": "1", "title": "A", "status": "todo", "updatedAt": "2026-10-24T10:00:00Z"]],
            "nextCursor": "c1",
        ])
        transport.respond("GET", "/lumi/v1/tasks", status: 200, json: [
            "tasks": [["id": 2, "title": "B", "status": "done", "updatedAt": "2026-10-24T10:00:00.123Z"]],
            "nextCursor": "c1",
        ])
        let tasks = try await make(transport).listTasks()

        XCTAssertEqual(tasks.map(\.id), ["1", "2"], "sayı kimlik string olur")
        let requests = transport.requests
        XCTAssertEqual(requests.count, 2, "aynı imleç tekrar edince durur")
        XCTAssertTrue(requests[1].url?.query?.contains("cursor=c1") == true)
        XCTAssertTrue(requests[0].url?.query?.contains("limit=200") == true)
    }

    func testSinceIsSentAndIDsMakeADelta() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/v1/tasks", status: 200, json: [
            "tasks": [["id": "2", "title": "B", "status": "done", "updatedAt": "2026-10-24T10:00:00Z"]],
            "ids": ["1", 2], "nextCursor": NSNull(), "syncToken": "t2",
        ])
        let listing = try await make(transport).listTasks(since: "t1")

        XCTAssertTrue(transport.requests[0].url?.query?.contains("since=t1") == true)
        XCTAssertEqual(listing.allIDs, ["1", "2"])
        XCTAssertEqual(listing.tasks.map(\.id), ["2"])
        XCTAssertEqual(listing.syncToken, "t2")
    }

    func testIDsWithoutSinceAreAFullList() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/v1/tasks", status: 200, json: [
            "tasks": [], "ids": ["1"], "syncToken": "t1",
        ])
        let listing = try await make(transport).listTasks(since: nil)

        XCTAssertFalse(transport.requests[0].url?.query?.contains("since") == true)
        XCTAssertFalse(listing.isDelta)
        XCTAssertEqual(listing.syncToken, "t1")
    }

    func testBrokenTasksAreFlaggedNotDropped() {
        let flagged = LumiTasksWire.task(["id": "1", "status": "blocked"])
        XCTAssertEqual(flagged?.status, .todo)
        XCTAssertEqual(flagged?.title, "(untitled)")
        XCTAssertEqual(flagged?.needsAttention, true)
        XCTAssertNil(LumiTasksWire.task(["title": "no id"]), "kimliksiz task gösterilemez")

        let full = LumiTasksWire.task([
            "id": "9", "title": "T", "status": "in_review", "updatedAt": "2026-10-24T10:00:00Z",
            "priority": "urgent", "assignee": NSNull(), "dueDate": "2026-11-01",
            "project": ["key": "api", "repo": "git@github.com:a/b.git"],
            "images": [["url": "https://cdn.x/a.png", "thumbnailUrl": "https://cdn.x/a_t.png", "width": 10], ["url": "not a url"]],
        ])
        XCTAssertEqual(full?.needsAttention, false)
        XCTAssertEqual(full?.priority, .urgent)
        XCTAssertNil(full?.assignee)
        XCTAssertEqual(full?.project?.repo, "git@github.com:a/b.git")
        XCTAssertEqual(full?.images.count, 1)
        XCTAssertEqual(full?.images.first?.width, 10)
        XCTAssertNotNil(full?.dueDate)
    }

    // MARK: - Yazım

    func testPatchSendsOnlyChangedFieldsAndNullToUnassign() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("PATCH", "/lumi/v1/tasks/a b", status: 200, json: [
            "id": "a b", "title": "T", "status": "done", "updatedAt": "2026-10-24T10:00:00Z",
        ])
        let task = try await make(transport).update(taskID: "a b", patch: TaskPatch(status: .done, assignee: .unassign))

        XCTAssertEqual(task.status, .done)
        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.absoluteString, "https://tasks.example.com/lumi/v1/tasks/a%20b")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["status"] as? String, "done")
        XCTAssertTrue(body["assigneeId"] is NSNull)
        XCTAssertEqual(body.count, 2)
    }

    func testDeleteAcceptsEmpty204() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("DELETE", "/lumi/v1/tasks/1", status: 204)
        try await make(transport).delete(taskID: "1")
    }

    // MARK: - Hatalar

    func testEnvelopeErrorCarriesAllDetails() async {
        let transport = FakeHTTPTransport()
        transport.respond("PATCH", "/lumi/v1/tasks/1", status: 422, json: [
            "error": ["code": "validation_failed", "message": "status must be one of …"],
        ])
        do {
            _ = try await make(transport).update(taskID: "1", patch: TaskPatch(status: .done))
            XCTFail("accepted")
        } catch let failure as TaskRequestFailure {
            XCTAssertEqual(failure.request, "PATCH /lumi/v1/tasks/1")
            XCTAssertEqual(failure.httpStatus, 422)
            XCTAssertEqual(failure.serverCode, "validation_failed")
            XCTAssertEqual(failure.serverMessage, "status must be one of …")
            XCTAssertEqual(failure.taskID, "1")
            XCTAssertFalse(failure.agentReport.contains("secret"), "token rapora girmez")
        } catch { XCTFail("\(error)") }
    }

    func testHTMLErrorPageKeepsExcerptAndExplainsMissingEnvelope() async {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/v1/tasks", status: 500, raw: "<html><h1>Application Error</h1></html>")
        do {
            _ = try await make(transport).listTasks()
            XCTFail("accepted")
        } catch let failure as TaskRequestFailure {
            XCTAssertEqual(failure.httpStatus, 500)
            XCTAssertTrue(failure.serverMessage?.contains("without the") == true)
            XCTAssertEqual(failure.responseExcerpt, "<html><h1>Application Error</h1></html>")
        } catch { XCTFail("\(error)") }
    }

    func testStatusCodesMapToKinds() async {
        for (status, kind) in [(401, TaskProviderError.unauthorized), (404, .notFound), (409, .conflict)] {
            let transport = FakeHTTPTransport()
            transport.respond("GET", "/lumi/v1/users", status: status, json: ["error": "nope"])
            do {
                _ = try await make(transport).listUsers()
                XCTFail("accepted \(status)")
            } catch let failure as TaskRequestFailure {
                XCTAssertEqual(failure.kind, kind)
                XCTAssertEqual(failure.serverMessage, "nope", "string zarf sapması da okunur")
            } catch { XCTFail("\(error)") }
        }
    }

    func testRateLimitMentionsRetryAfter() async {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/v1/tasks", status: 429, json: ["error": ["code": "rate_limited", "message": "slow down"]], headers: ["Retry-After": "30"])
        do {
            _ = try await make(transport).listTasks()
        } catch let failure as TaskRequestFailure {
            XCTAssertEqual(failure.serverMessage, "slow down (retry after 30s)")
        } catch { XCTFail("\(error)") }
    }

    func testNetworkFailureIsUnreachableWithFriendlyMessage() async {
        let transport = FakeHTTPTransport()
        transport.setNetworkError(URLError(.cannotConnectToHost))
        do {
            _ = try await make(transport).discover()
        } catch let failure as TaskRequestFailure {
            guard case .unreachable(let message) = failure.kind else { return XCTFail("\(failure.kind)") }
            XCTAssertTrue(message.contains("Nothing is listening"))
            XCTAssertEqual(failure.request, "GET /lumi/v1")
            XCTAssertNil(failure.httpStatus)
        } catch { XCTFail("\(error)") }
    }

    func testNonJSONSuccessIsInvalid() async {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/v1/tasks", status: 200, raw: "OK")
        do {
            _ = try await make(transport).listTasks()
            XCTFail("accepted")
        } catch let failure as TaskRequestFailure {
            XCTAssertEqual(failure.serverMessage, "The response body is not JSON")
        } catch { XCTFail("\(error)") }
    }

    // MARK: - Görsel yetkisi

    func testTokenOnlyGoesToSameOrigin() {
        let provider = make(FakeHTTPTransport())
        XCTAssertEqual(provider.authorization(for: URL(string: "https://tasks.example.com/files/a.png")!), "Bearer secret")
        XCTAssertNil(provider.authorization(for: URL(string: "https://cdn.example.com/a.png")!))
        XCTAssertNil(provider.authorization(for: URL(string: "http://tasks.example.com/a.png")!))
        XCTAssertNil(make(FakeHTTPTransport(), token: nil).authorization(for: URL(string: "https://tasks.example.com/a.png")!))
    }
}

/// `config.json` `taskSources` kaydı ve setup prompt metni.
final class TaskSourceCodecTests: XCTestCase {
    func testRoundTripAndDropsInvalidEntries() {
        let raw: [Any] = [
            ["id": "a", "name": "Team", "kind": "custom", "baseURL": "my-app.herokuapp.com/"],
            ["id": "a", "name": "Duplicate", "kind": "demo"],
            ["id": "b", "kind": "demo"],
            ["id": "c", "kind": "custom", "baseURL": "http://example.com"],
            ["id": "d", "kind": "github"],
            ["id": "e", "kind": "martian"],
            "garbage",
        ]
        let sources = TaskSourceCodec.decodeList(raw)
        XCTAssertEqual(sources.map(\.id.rawValue), ["a", "b"])
        XCTAssertEqual(sources[0].baseURL, "https://my-app.herokuapp.com")
        XCTAssertEqual(sources[1].name, TaskProviderKind.demo.title)
        XCTAssertNil(sources[1].baseURL)

        let overlay = TaskSourceCodec.overlayList(sources)
        XCTAssertEqual(TaskSourceCodec.decodeList(overlay), sources)
        XCTAssertNil(overlay[1]["baseURL"])
        XCTAssertTrue(TaskSourceCodec.decodeList(nil).isEmpty)
    }

    func testPromptTemplateRoundTripsAndIsOnlyWrittenWhenSet() {
        let plain = TaskSource(id: TaskSourceID("a"), name: "A", kind: .demo)
        let templated = TaskSource(
            id: TaskSourceID("b"), name: "B", kind: .demo,
            promptTemplate: TaskPromptTemplate(prefix: "pre", suffix: "")
        )
        let overlay = TaskSourceCodec.overlayList([plain, templated])
        XCTAssertNil(overlay[0]["promptPrefix"])
        XCTAssertEqual(overlay[1]["promptPrefix"] as? String, "pre")
        XCTAssertNil(overlay[1]["promptSuffix"])
        XCTAssertEqual(TaskSourceCodec.decodeList(overlay), [plain, templated])
    }

    func testOverlayNeverContainsTokens() {
        let overlay = TaskSourceCodec.overlayList([TaskSource(id: TaskSourceID("x"), name: "n", kind: .custom, baseURL: "https://x.dev")])
        XCTAssertEqual(Set(overlay[0].keys), ["id", "name", "kind", "baseURL"])
    }

    func testSetupPromptCoversTheWholeProtocol() {
        let text = TaskSetupPrompt.text
        for endpoint in ["GET /lumi/v1`", "GET /lumi/v1/tasks`", "PATCH /lumi/v1/tasks/{id}", "POST /lumi/v1/tasks", "DELETE /lumi/v1/tasks/{id}", "GET /lumi/v1/users", "GET /lumi/v1/projects"] {
            XCTAssertTrue(text.contains(endpoint), endpoint)
        }
        for status in TaskStatus.allCases { XCTAssertTrue(text.contains("`\(status.rawValue)`"), status.rawValue) }
        for priority in TaskPriority.allCases { XCTAssertTrue(text.contains("`\(priority.rawValue)`"), priority.rawValue) }
        for capability in TaskCapability.allCases { XCTAssertTrue(text.contains("`\(capability.rawValue)`"), capability.rawValue) }
        for field in TaskField.allCases { XCTAssertTrue(text.contains("\"\(field.rawValue)\""), field.rawValue) }
        XCTAssertTrue(text.contains("LUMI_TASKS_TOKEN"))
        XCTAssertTrue(text.contains("nextCursor"))
        XCTAssertTrue(text.contains("assigneeId"))
        XCTAssertTrue(text.contains("thumbnailUrl"))
    }
}
