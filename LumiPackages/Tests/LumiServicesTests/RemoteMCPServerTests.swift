import Foundation
import LumiKit
import XCTest

@testable import LumiServices

/// Claude terminallerinin remote araç sunucusu (karar 143, Faz 5): gerçek loopback dinleyici.
final class RemoteMCPServerTests: XCTestCase {
    private struct EchoHandler: OrchestratorToolHandling {
        func call(name: String, arguments: Data) async -> OrchestratorToolResult {
            OrchestratorToolResult(text: "called \(name)")
        }
    }

    private func post(_ endpoint: RemoteMCPEndpoint, token: String, _ body: [String: Any]) async throws -> (Int, [String: Any]?) {
        var request = URLRequest(url: URL(string: endpoint.url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, json)
    }

    func testListsRemoteToolsAndRoutesCallsOnlyWithTheToken() async throws {
        let server = RemoteMCPServer()
        let endpoint = try await server.start(handler: EchoHandler())
        defer { Task { await server.stop() } }
        XCTAssertEqual(endpoint.environment[RemoteMCPEndpoint.urlVariable], endpoint.url)

        let (status, list) = try await post(endpoint, token: endpoint.token, ["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        XCTAssertEqual(status, 200)
        let names = ((list?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, RemoteMCPTools.specs.map(\.name))

        let (_, call) = try await post(endpoint, token: endpoint.token, [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": RemoteMCPTools.listHubs, "arguments": [:] as [String: Any]],
        ])
        let content = ((call?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first
        XCTAssertEqual(content?["text"] as? String, "called \(RemoteMCPTools.listHubs)")

        let (forbidden, _) = try await post(endpoint, token: "forged", ["jsonrpc": "2.0", "id": 3, "method": "tools/list"])
        XCTAssertEqual(forbidden, 401)
        let again = try await server.start(handler: EchoHandler())
        XCTAssertEqual(again, endpoint, "idempotent")
    }

    func testEverySchemaIsValidJSON() throws {
        for spec in RemoteMCPTools.specs {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(spec.inputSchema.utf8)), spec.name)
        }
    }

    /// Gömülü `lumi-remote` modunun `.mcp.json`'ı Lumi'nin yazdığı değişkenleri açar.
    func testBundledModPointsAtTheInjectedEnvironment() throws {
        let mod = try XCTUnwrap(BundledClaudeMods.all.first { $0.id == "lumi-remote" })
        let text = try XCTUnwrap(mod.files[".mcp.json"])
        let config = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let server = try XCTUnwrap((config["mcpServers"] as? [String: Any])?[RemoteMCPTools.serverName] as? [String: Any])
        XCTAssertTrue((server["url"] as? String)?.contains("${\(RemoteMCPEndpoint.urlVariable):-") == true)
        let auth = (server["headers"] as? [String: String])?["Authorization"]
        XCTAssertTrue(auth?.contains("${\(RemoteMCPEndpoint.tokenVariable):-") == true)
        XCTAssertNotNil(mod.files[".claude-plugin/plugin.json"])
    }
}
