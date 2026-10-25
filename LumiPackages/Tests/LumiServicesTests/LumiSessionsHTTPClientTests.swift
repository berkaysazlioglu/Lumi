import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiServices

/// Lumi Sessions Protocol v1 istemcisinin sözleşmesi (karar 138): istek
/// biçimi, hoşgörülü okuma, sayfalama, ham paket gövdesi ve hata ayrıntısı.
final class LumiSessionsHTTPClientTests: XCTestCase {
    private let base = URL(string: "https://sessions.example.com")!

    private func make(_ transport: FakeHTTPTransport) -> LumiSessionsHTTPClient {
        LumiSessionsHTTPClient(baseURL: base, token: "secret", transport: transport)
    }

    private func summary(_ id: String, uploadedAt: String = "2026-10-25T10:00:00Z", uploader: Any = ["id": "u_1", "name": "Ada"]) -> [String: Any] {
        ["id": id, "title": "Session \(id)", "project": "Backend API", "provider": "claude",
         "uploader": uploader, "uploadedAt": uploadedAt, "size": 1234]
    }

    func testDiscoveryReadsMeAndSendsBearerToken() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/sessions/v1", status: 200, json: [
            "protocol": "lumi-sessions", "version": 1, "name": "Team", "me": ["id": 7, "name": "Ada"],
            "maxUploadBytes": 1024,
        ])
        let info = try await make(transport).discover()

        XCTAssertEqual(info, SessionServerInfo(name: "Team", me: SharedSessionUploader(id: "7", name: "Ada"), maxUploadBytes: 1024))
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://sessions.example.com/lumi/sessions/v1")
    }

    func testDiscoveryRejectsOtherProtocolsAndMissingMe() async {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/sessions/v1", status: 200, json: ["protocol": "lumi-tasks", "version": 1])
        await assertFailure(kind: .unsupportedVersion) { _ = try await self.make(transport).discover() }

        let noMe = FakeHTTPTransport()
        noMe.respond("GET", "/lumi/sessions/v1", status: 200, json: ["protocol": "lumi-sessions", "version": 1])
        do {
            _ = try await make(noMe).discover()
            XCTFail("accepted")
        } catch let failure as SessionShareFailure {
            XCTAssertTrue(failure.serverMessage?.contains(#""me""#) == true)
        } catch { XCTFail("\(error)") }
    }

    func testListFollowsCursorSkipsBrokenAndSortsNewestFirst() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("GET", "/lumi/sessions/v1/sessions", status: 200, json: [
            "sessions": [summary("a", uploadedAt: "2026-10-20T10:00:00Z"), ["id": "broken"]],
            "nextCursor": "c1",
        ])
        transport.respond("GET", "/lumi/sessions/v1/sessions", status: 200, json: [
            "sessions": [summary("b", uploadedAt: "2026-10-25T10:00:00.250Z")], "nextCursor": "c1",
        ])
        let sessions = try await make(transport).listSessions()

        XCTAssertEqual(sessions.map(\.id), ["b", "a"])
        XCTAssertEqual(sessions[0].uploader, SharedSessionUploader(id: "u_1", name: "Ada"))
        XCTAssertEqual(sessions[0].provider, .claude)
        XCTAssertEqual(sessions[0].sizeBytes, 1234)
        // Tekrar eden imleçte durur.
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests[1].url?.query?.contains("cursor=c1") == true)
    }

    func testUploadSendsArchiveVerbatimAndReturnsSummary() async throws {
        let transport = FakeHTTPTransport()
        transport.respond("POST", "/lumi/sessions/v1/sessions", status: 201, json: summary("new"))
        let archive = Data(#"{"format":"lumi-agent-session","records":[{"type":"user","text":"ğ"}]}"#.utf8)
        let uploaded = try await make(transport).upload(SharedSessionUpload(
            title: "Fix \"login\"", project: "Backend API", provider: .codex, archive: archive
        ))

        XCTAssertEqual(uploaded.id, "new")
        let body = try XCTUnwrap(transport.requests[0].httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["title"] as? String, "Fix \"login\"")
        XCTAssertEqual(object["provider"] as? String, "codex")
        XCTAssertEqual((object["archive"] as? [String: Any])?["format"] as? String, "lumi-agent-session")
        XCTAssertTrue(body.range(of: archive) != nil, "the package is embedded byte for byte")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testDownloadReturnsArchiveObject() async throws {
        let transport = FakeHTTPTransport()
        var detail = summary("s/1")
        detail["archive"] = ["format": "lumi-agent-session", "version": 1]
        transport.respond("GET", "/lumi/sessions/v1/sessions/s/1", status: 200, json: detail)
        let data = try await make(transport).download(sessionID: "s/1")

        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(archive["format"] as? String, "lumi-agent-session")
        XCTAssertTrue(transport.requests[0].url?.absoluteString.hasSuffix("/sessions/s%2F1") == true)
    }

    func testErrorStatusesMapToKindsWithEnvelope() async {
        let cases: [(Int, String, SessionShareFailure.Kind)] = [
            (401, "unauthorized", .unauthorized), (403, "forbidden", .forbidden), (404, "not_found", .notFound),
            (413, "payload_too_large", .tooLarge), (503, "not_configured", .notConfigured),
        ]
        for (status, code, kind) in cases {
            let transport = FakeHTTPTransport()
            transport.respond("DELETE", "/lumi/sessions/v1/sessions/x", status: status, json: ["error": ["code": code, "message": "nope"]])
            do {
                try await make(transport).delete(sessionID: "x")
                XCTFail("accepted \(status)")
            } catch let failure as SessionShareFailure {
                XCTAssertEqual(failure.kind, kind)
                XCTAssertEqual(failure.serverCode, code)
                XCTAssertEqual(failure.request, "DELETE /lumi/sessions/v1/sessions/x")
                XCTAssertFalse(failure.agentReport.contains("secret"))
            } catch { XCTFail("\(error)") }
        }
    }

    func testNetworkErrorIsHumanized() async {
        let transport = FakeHTTPTransport()
        transport.setNetworkError(URLError(.cannotConnectToHost))
        await assertFailure(kind: .unreachable("Nothing is listening at this address — is the server running?")) {
            _ = try await self.make(transport).listSessions()
        }
    }

    private func assertFailure(kind: SessionShareFailure.Kind, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("accepted")
        } catch let failure as SessionShareFailure {
            XCTAssertEqual(failure.kind, kind)
        } catch { XCTFail("\(error)") }
    }
}

/// Additive `sessionServer` kaydı (karar 138).
final class SessionServerCodecTests: XCTestCase {
    func testDecodesValidRecordAndDropsInvalidOnes() {
        XCTAssertEqual(
            SessionServerCodec.decode(["id": "a", "name": "Team", "baseURL": "https://x.example.com/"]),
            SessionServer(id: "a", name: "Team", baseURL: "https://x.example.com")
        )
        XCTAssertNil(SessionServerCodec.decode(nil))
        XCTAssertNil(SessionServerCodec.decode(NSNull()))
        XCTAssertNil(SessionServerCodec.decode(["id": "a", "baseURL": "http://remote.example.com"]))
        XCTAssertNil(SessionServerCodec.decode(["baseURL": "https://x.example.com"]))
    }
}
