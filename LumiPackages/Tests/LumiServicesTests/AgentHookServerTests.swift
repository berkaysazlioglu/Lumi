import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 45: asgari HTTP ayrıştırıcı — `curl --data-binary` biçimi.
final class HTTPRequestParserTests: XCTestCase {
    private func request(_ text: String) -> Data { Data(text.utf8) }

    func testParsesPostWithBody() throws {
        let raw = request("POST /hook/claude HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nX-Foo: Bar \r\n\r\n{}")
        guard case .complete(let parsed) = HTTPRequestParser.parse(raw) else { return XCTFail("tamamlanmalıydı") }
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/hook/claude")
        XCTAssertEqual(parsed.header("x-foo"), "Bar")
        XCTAssertEqual(parsed.header("X-FOO"), "Bar", "başlık adı büyük/küçük harften bağımsız")
        XCTAssertEqual(parsed.body, Data("{}".utf8))
    }

    func testIncompleteHeadersAndBodyWaitForMoreBytes() {
        XCTAssertEqual(HTTPRequestParser.parse(request("POST /hook/claude HTTP/1.1\r\nContent-Length: 5\r\n")), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(request("POST /hook/claude HTTP/1.1\r\nContent-Length: 5\r\n\r\n{\"a\"")), .incomplete)
    }

    func testMalformedRequestLineOrHeaderIsRejected() {
        XCTAssertEqual(HTTPRequestParser.parse(request("GARBAGE\r\n\r\n")), .malformed)
        XCTAssertEqual(HTTPRequestParser.parse(request("POST /x HTTP/1.1\r\nNoColonHere\r\n\r\n")), .malformed)
        XCTAssertEqual(HTTPRequestParser.parse(request("POST /x HTTP/1.1\r\nContent-Length: -4\r\n\r\n")), .malformed)
    }

    func testOversizedBodyOrHeadersAreRejected() {
        let huge = "POST /x HTTP/1.1\r\nContent-Length: \(HTTPRequestParser.maxBodyBytes + 1)\r\n\r\n"
        XCTAssertEqual(HTTPRequestParser.parse(request(huge)), .malformed)
        let padding = String(repeating: "a", count: HTTPRequestParser.maxHeaderBytes + 10)
        XCTAssertEqual(HTTPRequestParser.parse(request("POST /x HTTP/1.1\r\nX: \(padding)")), .malformed)
    }

    func testResponseIsCloseDelimitedJSON() {
        let text = String(decoding: HTTPRequestParser.response(status: 200, reason: "OK"), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{}"))
    }
}

/// Karar 45: yönlendirici — yol, yöntem, token, terminal başlığı, gövde.
final class AgentHookRequestRouterTests: XCTestCase {
    private let terminal = TerminalID()

    private func request(
        method: String = "POST", path: String = "/hook/claude",
        token: String? = "secret", terminalID: String? = nil,
        body: String = "{\"hook_event_name\":\"Stop\"}"
    ) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let token { headers["x-lumi-agent-hook-token"] = token }
        headers["x-lumi-terminal-id"] = terminalID ?? terminal.description
        return HTTPRequest(method: method, path: path, headers: headers, body: Data(body.utf8))
    }

    func testAcceptsValidRequestAsEvent() {
        guard case .accepted(let event) = AgentHookRequestRouter.route(request(), token: "secret") else {
            return XCTFail("kabul edilmeliydi")
        }
        XCTAssertEqual(event.kind, .stop)
        XCTAssertEqual(event.provider, .claude)
        XCTAssertEqual(event.terminalID, terminal)
    }

    func testRoutesProviderFromPath() {
        guard case .accepted(let event) = AgentHookRequestRouter.route(request(path: "/hook/codex"), token: "secret") else {
            return XCTFail("kabul edilmeliydi")
        }
        XCTAssertEqual(event.provider, .codex)
    }

    func testRejectsWrongMethodPathTokenAndTerminal() {
        XCTAssertEqual(AgentHookRequestRouter.route(request(method: "GET"), token: "secret"), .rejected(status: 405, reason: "Method Not Allowed"))
        XCTAssertEqual(AgentHookRequestRouter.route(request(path: "/hook/gemini"), token: "secret"), .rejected(status: 404, reason: "Not Found"))
        XCTAssertEqual(AgentHookRequestRouter.route(request(path: "/other"), token: "secret"), .rejected(status: 404, reason: "Not Found"))
        XCTAssertEqual(AgentHookRequestRouter.route(request(token: "wrong"), token: "secret"), .rejected(status: 401, reason: "Unauthorized"))
        XCTAssertEqual(AgentHookRequestRouter.route(request(token: nil), token: "secret"), .rejected(status: 401, reason: "Unauthorized"))
        XCTAssertEqual(AgentHookRequestRouter.route(request(terminalID: "not-a-uuid"), token: "secret"), .rejected(status: 400, reason: "Bad Request"))
        XCTAssertEqual(AgentHookRequestRouter.route(request(body: "{}"), token: "secret"), .rejected(status: 400, reason: "Bad Request"))
    }
}

/// Karar 45: gerçek loopback sunucu — `curl`ün yaptığı POST'u URLSession ile.
final class AgentHookServerTests: XCTestCase {
    private var server: AgentHookServer!

    override func setUp() async throws {
        server = AgentHookServer(tokenGenerator: { "test-token" })
    }

    override func tearDown() async throws {
        await server.stop()
        server = nil
    }

    private func post(
        to endpoint: AgentHookEndpoint, path: String = "/hook/claude", token: String = "test-token",
        terminalID: TerminalID, body: String
    ) async throws -> Int {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(endpoint.port)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: AgentHookRequestRouter.tokenHeader)
        request.setValue(terminalID.description, forHTTPHeaderField: AgentHookRequestRouter.terminalHeader)
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 5
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    func testStartBindsLoopbackPortAndReturnsSameEndpointTwice() async throws {
        let first = try await server.start()
        let second = try await server.start()
        XCTAssertNotEqual(first.port, 0)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.token, "test-token")
        XCTAssertEqual(server.currentEndpoint, first)
    }

    func testValidPostIsAcknowledgedAndPublished() async throws {
        let endpoint = try await server.start()
        let terminal = TerminalID()
        let stream = server.events()
        var iterator = stream.makeAsyncIterator()

        let status = try await post(to: endpoint, terminalID: terminal, body: "{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}")

        XCTAssertEqual(status, 200)
        let event = await iterator.next()
        XCTAssertEqual(event?.kind, .userPromptSubmit)
        XCTAssertEqual(event?.terminalID, terminal)
        XCTAssertEqual(event?.promptHead, "hi")
    }

    func testBadTokenIsRejectedWithoutPublishing() async throws {
        let endpoint = try await server.start()
        let status = try await post(to: endpoint, token: "nope", terminalID: TerminalID(), body: "{\"hook_event_name\":\"Stop\"}")
        XCTAssertEqual(status, 401)
    }

    func testUnknownProviderPathIs404() async throws {
        let endpoint = try await server.start()
        let status = try await post(to: endpoint, path: "/hook/gemini", terminalID: TerminalID(), body: "{\"hook_event_name\":\"Stop\"}")
        XCTAssertEqual(status, 404)
    }

    func testStopReleasesEndpoint() async throws {
        _ = try await server.start()
        await server.stop()
        XCTAssertNil(server.currentEndpoint)
    }

    /// Uçtan uca: üretilen script gerçek `/bin/sh` + `curl` ile, Claude'un
    /// yaptığı gibi stdin'den JSON alıp sunucuya ulaşır; stdout `{}` basar.
    func testGeneratedScriptPostsThroughRealCurl() async throws {
        let endpoint = try await server.start()
        let terminal = TerminalID()
        var iterator = server.events().makeAsyncIterator()
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-claude-hook-\(UUID().uuidString).sh")
        try AgentHookScript.posix(provider: .claude).write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let (status, stdout) = try runScript(
            scriptURL,
            stdin: "{\"hook_event_name\":\"Stop\",\"is_interrupt\":true}",
            environment: [
                "PATH": "/usr/bin:/bin",
                "LUMI_TERMINAL_ID": terminal.description,
                "LUMI_AGENT_HOOK_PORT": String(endpoint.port),
                "LUMI_AGENT_HOOK_TOKEN": endpoint.token,
            ]
        )

        XCTAssertEqual(status, 0)
        XCTAssertEqual(stdout, "{}\n", "Claude izin hook'u için nötr karar")
        let event = await iterator.next()
        XCTAssertEqual(event?.kind, .stop)
        XCTAssertTrue(event?.isInterrupt == true)
        XCTAssertEqual(event?.terminalID, terminal)
    }

    /// Lumi env'i yokken (iTerm'de açılmış Claude) script sessizce çıkar,
    /// stdin'i boşaltır ve hiçbir şey göndermez.
    func testGeneratedScriptExitsQuietlyWithoutLumiEnvironment() async throws {
        _ = try await server.start()
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-codex-hook-\(UUID().uuidString).sh")
        try AgentHookScript.posix(provider: .codex).write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let (status, stdout) = try runScript(scriptURL, stdin: "{\"hook_event_name\":\"Stop\"}", environment: ["PATH": "/usr/bin:/bin"])

        XCTAssertEqual(status, 0)
        XCTAssertEqual(stdout, "", "Codex script'i stdout'a hiçbir şey basmaz")
    }

    private func runScript(_ script: URL, stdin: String, environment: [String: String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
