import Foundation
import LumiKit
import XCTest

@testable import LumiServices

/// Gerçek bir Lumi Sessions sunucusuna karşı uçtan uca kontrol (karar 138
/// dogfood). Yalnız `LUMI_SESSIONS_E2E_URL` + `LUMI_SESSIONS_E2E_TOKEN`
/// (+ silme yetkisi için ikinci kullanıcının `LUMI_SESSIONS_E2E_TOKEN2`)
/// tanımlıysa koşar; CI'da atlanır.
///
///     LUMI_SESSIONS_E2E_URL=http://localhost:4200 LUMI_SESSIONS_E2E_TOKEN=… \
///       LUMI_SESSIONS_E2E_TOKEN2=… swift test --filter LumiSessionsLiveServerTests
final class LumiSessionsLiveServerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func client(token key: String = "LUMI_SESSIONS_E2E_TOKEN", override: String? = nil) throws -> LumiSessionsHTTPClient {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["LUMI_SESSIONS_E2E_URL"], let token = override ?? environment[key],
              case .success(let url) = TaskEndpoint.normalize(address)
        else { throw XCTSkip("LUMI_SESSIONS_E2E_URL / \(key) not set") }
        return LumiSessionsHTTPClient(baseURL: url, token: token, transport: URLSessionTransport())
    }

    /// Agent History'deki gerçek bir oturum → sunucu → başka bir makinenin
    /// başka bir projesi; arada yalnız Lumi'nin kendi bileşenleri.
    func testShareRoundTripBetweenTwoMachines() async throws {
        let alice = try client()
        let me = try await alice.discover().me
        print("discovery me:", me)

        // 1. Kaynak makinede Agent History'nin gördüğü oturum.
        let sourceHome = root.appendingPathComponent("alice")
        let sourceProject = "/Users/alice/wkspaces/Lumi"
        try writeClaudeSession(home: sourceHome, project: sourceProject, id: "e2e-\(UUID().uuidString.prefix(8).lowercased())")
        let sourceEntries = try await AgentHistoryService(home: sourceHome, environment: [:])
            .entries(projectPath: sourceProject)
        let entry = try XCTUnwrap(sourceEntries.first)
        XCTAssertEqual(entry.subagents.count, 1)

        // 2. Export to Server.
        let archive = try await AgentSessionTransferService(home: sourceHome, environment: [:]).exportArchive(entry)
        let uploaded = try await alice.upload(SharedSessionUpload(
            title: "E2E: fix the login loop", project: "Lumi", provider: .claude, archive: archive
        ))
        print("uploaded:", uploaded)
        XCTAssertEqual(uploaded.uploader, me, "uploader comes from the token")
        XCTAssertEqual(uploaded.project, "Lumi")

        // 3. İkinci kullanıcı listeyi görür ama silemez.
        let bob = try client(token: "LUMI_SESSIONS_E2E_TOKEN2")
        let bobMe = try await bob.discover().me
        XCTAssertNotEqual(bobMe.id, me.id)
        let listed = try await bob.listSessions()
        XCTAssertEqual(listed.first { $0.id == uploaded.id }?.uploader, me)
        do {
            try await bob.delete(sessionID: uploaded.id)
            XCTFail("another user deleted the session")
        } catch let failure as SessionShareFailure {
            print("403 failure:", failure.summary)
            XCTAssertEqual(failure.kind, .forbidden)
        }

        // 4. Import from Server: başka makine, başka proje yolu.
        let targetHome = root.appendingPathComponent("bob")
        let targetProject = "/Users/bob/code/Lumi"
        let downloaded = try await bob.download(sessionID: uploaded.id)
        let result = try await AgentSessionTransferService(home: targetHome, environment: [:])
            .importArchive(downloaded, projectPath: targetProject)
        XCTAssertEqual(result.subagentCount, 1)
        let imported = try String(contentsOfFile: result.logPath, encoding: .utf8)
        XCTAssertTrue(imported.contains(#""cwd":"/Users/bob/code/Lumi""#))
        XCTAssertFalse(imported.contains("alice@example.com"), "personal records stripped before upload")
        let history = try await AgentHistoryService(home: targetHome, environment: [:]).entries(projectPath: targetProject)
        XCTAssertEqual(history.map(\.sessionID), [entry.sessionID])
        XCTAssertEqual(history.first?.subagents.count, 1)

        // 5. Yükleyen siler; oturum gider.
        try await alice.delete(sessionID: uploaded.id)
        do {
            _ = try await alice.download(sessionID: uploaded.id)
            XCTFail("deleted session still downloadable")
        } catch let failure as SessionShareFailure {
            XCTAssertEqual(failure.kind, .notFound)
        }
        let after = try await alice.listSessions()
        XCTAssertFalse(after.contains { $0.id == uploaded.id })
    }

    func testWrongTokenIsRejectedWithEnvelope() async throws {
        do {
            _ = try await client(override: "wrong").discover()
            XCTFail("wrong token accepted")
        } catch let failure as SessionShareFailure {
            print("401 failure:", failure.summary)
            XCTAssertEqual(failure.kind, .unauthorized)
            XCTAssertEqual(failure.request, "GET /lumi/sessions/v1")
            XCTAssertNotNil(failure.serverCode)
        }
    }

    private func writeClaudeSession(home: URL, project: String, id: String) throws {
        let dir = home.appendingPathComponent(".claude/projects/\(AgentDataRoots.encodedProjectName(project))")
        let subDir = dir.appendingPathComponent("\(id)/subagents")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try Data("""
        {"type":"user","uuid":"u1","parentUuid":null,"sessionId":"\(id)","cwd":"\(project)","timestamp":"2026-10-25T10:00:00Z","message":{"role":"user","content":"Fix the login loop"}}
        {"type":"attachment","uuid":"a1","parentUuid":"u1","sessionId":"\(id)","cwd":"\(project)","attachment":{"type":"session_context","context":{"userEmail":"alice@example.com"}}}
        {"type":"assistant","uuid":"s1","parentUuid":"a1","sessionId":"\(id)","cwd":"\(project)","timestamp":"2026-10-25T10:00:05Z","message":{"role":"assistant","model":"claude-sonnet-5-5","content":[{"type":"text","text":"Reading \(project)/README.md"}]}}

        """.utf8).write(to: dir.appendingPathComponent("\(id).jsonl"))
        try Data("""
        {"type":"user","uuid":"x1","parentUuid":null,"isSidechain":true,"agentId":"a1","sessionId":"\(id)","cwd":"\(project)","message":{"role":"user","content":"Inspect \(project)/Sources"}}

        """.utf8).write(to: subDir.appendingPathComponent("agent-a1.jsonl"))
        try Data(#"{"agentType":"general-purpose","description":"Inspect","model":"sonnet"}"#.utf8)
            .write(to: subDir.appendingPathComponent("agent-a1.meta.json"))
    }
}
