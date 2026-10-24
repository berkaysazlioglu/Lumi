import Foundation
import LumiKit
import XCTest

@testable import LumiServices

/// Task ajanı MCP sunucusu (karar 137, Faz 3): gerçek loopback dinleyici,
/// terminal başına token, 0600 config dosyası.
final class TaskAgentMCPServerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lumi-task-mcp-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func post(_ session: TaskAgentToolSession, token: String? = nil, _ body: [String: Any]) async throws -> (Int, [String: Any]?) {
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: session.configPath))) as? [String: Any]
        let lumi = (config?["mcpServers"] as? [String: Any])?["lumi"] as? [String: Any]
        var request = URLRequest(url: URL(string: try XCTUnwrap(lumi?["url"] as? String))!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token ?? session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, json)
    }

    private func toolText(_ json: [String: Any]?) -> String? {
        let content = ((json?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first
        return content?["text"] as? String
    }

    func testConfigFileIsPrivateAndPointsAtTheServer() async throws {
        let server = TaskAgentMCPServer(directory: directory)
        let session = try await server.register(details: "x") { _ in "ok" }
        let attributes = try FileManager.default.attributesOfItem(atPath: session.configPath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let text = try String(contentsOfFile: session.configPath, encoding: .utf8)
        XCTAssertTrue(text.contains("http://127.0.0.1:"))
        XCTAssertTrue(text.contains("Bearer \(session.token)"))
        await server.unregister(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.configPath))
    }

    func testToolsListAndCallsReachOnlyTheirOwnTask() async throws {
        let server = TaskAgentMCPServer(directory: directory)
        let submitted = SummaryBox()
        let first = try await server.register(details: "DEMO-1: first") { summary in
            await submitted.set("first:" + summary)
            return "moved"
        }
        let second = try await server.register(details: "DEMO-2: second") { _ in "other" }

        let (_, list) = try await post(first, ["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        let names = ((list?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["get_task", "submit_for_review"])

        let (_, details) = try await post(second, ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "get_task"]])
        XCTAssertEqual(toolText(details), "DEMO-2: second")

        let (_, reply) = try await post(first, [
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": ["name": "submit_for_review", "arguments": ["summary": "all green"]],
        ])
        XCTAssertEqual(toolText(reply), "moved")
        let value = await submitted.value
        XCTAssertEqual(value, "first:all green")
    }

    func testEmptySummaryIsRejectedAndUnknownTokenIsUnauthorized() async throws {
        let server = TaskAgentMCPServer(directory: directory)
        let session = try await server.register(details: "x") { _ in "moved" }
        let (_, reply) = try await post(session, [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "submit_for_review", "arguments": ["summary": " "]],
        ])
        XCTAssertEqual((reply?["result"] as? [String: Any])?["isError"] as? Bool, true)

        let (status, _) = try await post(session, token: "forged", ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        XCTAssertEqual(status, 401)

        await server.unregister(session)
        // Dosya silindiği için URL'yi önceden okuyup token'ı yeniden denemek yerine
        // yeni bir kayıtla aynı dinleyicinin eski token'ı reddettiği sınanır.
        let other = try await server.register(details: "y") { _ in "" }
        let (afterStatus, _) = try await post(other, token: session.token, ["jsonrpc": "2.0", "id": 3, "method": "tools/list"])
        XCTAssertEqual(afterStatus, 401, "düşen kaydın token'ı artık geçmez")
    }
}

private actor SummaryBox {
    var value: String?
    func set(_ value: String) { self.value = value }
}

/// `ui-state.json` `taskLinks` kaydı ve proje eşleşmesi.
final class TaskLinkCodecTests: XCTestCase {
    func testRoundTripAndDropsBrokenEntries() {
        let record = TaskAgentLinkRecord(
            source: TaskSourceID("s"), taskID: "1", sessionID: "abc", checkoutPath: "/repo",
            model: .opus, startedAt: Date(timeIntervalSince1970: 1_700_000_000), summary: "done"
        )
        XCTAssertEqual(TaskLinkCodec.decode(TaskLinkCodec.overlay(record)), record)
        XCTAssertNil(TaskLinkCodec.decode(["source": "s", "taskId": "1", "sessionId": "abc", "checkoutPath": "relative", "startedAt": 1]))
        XCTAssertNil(TaskLinkCodec.decode(["source": "s", "taskId": "1", "checkoutPath": "/r", "startedAt": 1]))
    }

    func testRemoteNormalizationMatchesSSHAndHTTPS() {
        let forms = [
            "git@github.com:acme/api.git", "https://github.com/acme/api", "ssh://git@github.com/acme/api.git",
            "https://github.com/Acme/API/", "ssh://git@github.com:22/acme/api.git",
        ]
        for form in forms {
            XCTAssertEqual(TaskProjectMatcher.normalizedRemote(form), "github.com/acme/api", form)
        }
        let match = TaskProjectMatcher.match(
            TaskProjectRef(key: "backend", repo: "git@github.com:acme/api.git"),
            in: ["/w/api-checkout", "/w/web"],
            origins: ["/w/api-checkout": "https://github.com/acme/api.git", "/w/web": "https://github.com/acme/web"]
        )
        XCTAssertEqual(match, "/w/api-checkout", "ad tutmasa da origin eşleşir")
    }
}
