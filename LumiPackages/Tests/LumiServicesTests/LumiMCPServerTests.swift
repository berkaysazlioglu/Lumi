import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 114 Faz 2: MCP Streamable HTTP'nin Lumi'nin kullandığı alt kümesi.
final class MCPRequestRouterTests: XCTestCase {
    private func request(
        method: String = "POST", path: String = "/mcp", token: String? = "secret", body: String
    ) -> HTTPRequest {
        var headers: [String: String] = ["content-type": "application/json"]
        if let token { headers["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, headers: headers, body: Data(body.utf8))
    }

    private func route(_ request: HTTPRequest) -> MCPRequestRouter.Disposition {
        MCPRequestRouter.route(request, token: "secret", serverVersion: "0.9.0")
    }

    private func json(_ disposition: MCPRequestRouter.Disposition) throws -> [String: Any] {
        guard case .reply(200, let body?) = disposition else {
            XCTFail("200 JSON yanıtı bekleniyordu: \(disposition)")
            return [:]
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testInitializeEchoesClientProtocolVersionAndAdvertisesTools() throws {
        let reply = try json(route(request(body: #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#)))
        XCTAssertEqual(reply["id"] as? Int, 0)
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-11-25")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "lumi")
    }

    func testToolsListReturnsEverySpecWithParsedSchema() throws {
        let reply = try json(route(request(body: #"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#)))
        XCTAssertEqual(reply["id"] as? String, "a", "metin kimlik aynen döner")
        let tools = try XCTUnwrap((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.map { $0["name"] as? String }, OrchestratorTools.specs.map(\.name))
        for tool in tools {
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object")
        }
    }

    func testToolsCallIsHandedToTheExecutorWithArguments() throws {
        let disposition = route(request(body: #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"read_terminal","arguments":{"terminal_id":"abc123"}}}"#))
        guard case .callTool(let id, let name, let arguments) = disposition else {
            return XCTFail("araç çağrısı bekleniyordu: \(disposition)")
        }
        XCTAssertEqual(id, .number(7))
        XCTAssertEqual(name, "read_terminal")
        let args = try XCTUnwrap(JSONSerialization.jsonObject(with: arguments) as? [String: Any])
        XCTAssertEqual(args["terminal_id"] as? String, "abc123")
    }

    func testToolResponseCarriesTextAndErrorFlag() throws {
        let body = MCPRequestRouter.toolResponse(id: .number(3), result: .failure("nope"))
        let reply = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual((result["content"] as? [[String: Any]])?.first?["text"] as? String, "nope")
    }

    func testNotificationsAreAcceptedWithoutBody() {
        XCTAssertEqual(route(request(body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)), .reply(status: 202, body: nil))
    }

    func testUnknownMethodIsJSONRPCError() throws {
        let reply = try json(route(request(body: #"{"jsonrpc":"2.0","id":1,"method":"server/discover"}"#)))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, MCPRequestRouter.ErrorCode.methodNotFound)
    }

    func testAuthPathMethodAndBodyGuards() {
        XCTAssertEqual(route(request(token: nil, body: "{}")), .reply(status: 401, body: nil))
        XCTAssertEqual(route(request(token: "wrong", body: "{}")), .reply(status: 401, body: nil))
        XCTAssertEqual(route(request(path: "/other", body: "{}")), .reply(status: 404, body: nil))
        XCTAssertEqual(route(request(method: "GET", body: "")), .reply(status: 405, body: nil), "SSE akışı yok")
        guard case .reply(400, _) = route(request(body: "not json")) else { return XCTFail("400 bekleniyordu") }
    }
}

/// Karar 114 Faz 2: gerçek loopback MCP sunucusu.
final class LumiMCPServerTests: XCTestCase {
    private struct EchoTools: OrchestratorToolHandling {
        func call(name: String, arguments: Data) async -> OrchestratorToolResult {
            OrchestratorToolResult(text: "\(name):\(String(decoding: arguments, as: UTF8.self))")
        }
    }

    private func post(_ endpoint: OrchestratorControlEndpoint, token: String, body: String) async throws -> (Int, [String: Any]?) {
        var request = URLRequest(url: URL(string: endpoint.url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testToolCallRoundTripsThroughTheExecutor() async throws {
        let server = LumiMCPServer(tokenGenerator: { "tok" })
        let endpoint = try await server.start(handler: EchoTools())
        let again = try await server.start(handler: EchoTools())
        XCTAssertEqual(endpoint, again, "idempotent")

        let (status, reply) = try await post(endpoint, token: "tok", body: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_terminals","arguments":{}}}"#)

        XCTAssertEqual(status, 200)
        let content = (reply?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["text"] as? String, "list_terminals:{}")
        await server.stop()
    }

    func testWrongTokenIsRejected() async throws {
        let server = LumiMCPServer(tokenGenerator: { "tok" })
        let endpoint = try await server.start(handler: EchoTools())
        let (status, _) = try await post(endpoint, token: "bad", body: #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        XCTAssertEqual(status, 401)
        await server.stop()
    }
}
