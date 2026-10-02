import Foundation
import LumiKit
import LumiTestSupport
import Testing
@testable import LumiServices

@Suite struct OrchestratorServiceTests {
    private struct Sandbox {
        let home: URL
        let workingDirectory: URL

        init() throws {
            home = FileManager.default.temporaryDirectory
                .appendingPathComponent("orchestrator-\(UUID().uuidString)")
            workingDirectory = home.appendingPathComponent(".lumi/orchestrator")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        /// Claude'un transkript yerine bir konuşma yazar.
        func writeTranscript(sessionID: String, lines: [String]) throws {
            let encoded = AgentDataRoots.encodedProjectName(workingDirectory.path)
            let dir = home.appendingPathComponent(".claude/projects/\(encoded)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n")
                .write(to: dir.appendingPathComponent("\(sessionID).jsonl"), atomically: true, encoding: .utf8)
        }

        func service(spawner: FakeStreamingProcess, binary: String? = "/usr/bin/claude") -> OrchestratorService {
            OrchestratorService(
                workingDirectory: workingDirectory,
                environment: [:],
                spawner: spawner,
                locator: FixedBinaryLocator(path: binary),
                transcripts: TranscriptChatSource(home: home)
            )
        }
    }

    @Test func newConversationSpawnsIsolatedClaudeInOrchestratorDirectory() async throws {
        let sandbox = try Sandbox()
        let spawner = FakeStreamingProcess()
        let service = sandbox.service(spawner: spawner)

        let run = try await service.start(OrchestratorLaunch(sessionID: "s-1", resume: false))

        #expect(run.history.isEmpty)
        let spawn = try #require(spawner.spawns.first)
        #expect(spawn.executable == "/usr/bin/claude")
        #expect(spawn.currentDirectory == sandbox.workingDirectory.path)
        #expect(FileManager.default.fileExists(atPath: sandbox.workingDirectory.path))
        let args = spawn.arguments
        #expect(args.contains("--session-id") && !args.contains("--resume"))
        // Lumi'nin prompt'u, ayar/MCP/araç izolasyonu ve kullanıcı mesajı yankısı.
        #expect(value(after: "--system-prompt", in: args) == OrchestratorPrompt.systemPrompt)
        #expect(value(after: "--system-prompt-snapshot", in: args) == "off")
        #expect(value(after: "--setting-sources", in: args) == "")
        #expect(value(after: "--tools", in: args) == "")
        #expect(value(after: "--model", in: args) == "sonnet")
        #expect(args.contains("--strict-mcp-config"))
        #expect(args.contains("--replay-user-messages"))
        await service.stop()
    }

    /// Faz 2: MCP ucu token taşıdığı için argv'ye değil 0600 dosyaya yazılır;
    /// yalnız Lumi sunucusunun araçları izinlidir.
    @Test func controlEndpointIsPassedThroughPrivateMCPConfigFile() async throws {
        let sandbox = try Sandbox()
        let spawner = FakeStreamingProcess()
        let service = sandbox.service(spawner: spawner)
        let control = OrchestratorControlEndpoint(port: 5150, token: "s3cret")

        _ = try await service.start(OrchestratorLaunch(sessionID: "s-1", resume: false, control: control))

        let args = try #require(spawner.spawns.first?.arguments)
        let path = try #require(value(after: "--mcp-config", in: args))
        #expect(value(after: "--allowedTools", in: args) == "mcp__lumi")
        #expect(!args.joined(separator: " ").contains("s3cret"), "token argv'de görünmez")
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let config = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any]
        )
        let lumi = try #require((config["mcpServers"] as? [String: Any])?["lumi"] as? [String: Any])
        #expect(lumi["type"] as? String == "http")
        #expect(lumi["url"] as? String == "http://127.0.0.1:5150/mcp")
        #expect((lumi["headers"] as? [String: String])?["Authorization"] == "Bearer s3cret")
        await service.stop()
    }

    @Test func withoutControlNoMCPFlagsArePassed() async throws {
        let sandbox = try Sandbox()
        let spawner = FakeStreamingProcess()
        let service = sandbox.service(spawner: spawner)
        _ = try await service.start(OrchestratorLaunch(sessionID: "s-1", resume: false))
        let args = try #require(spawner.spawns.first?.arguments)
        #expect(!args.contains("--mcp-config"))
        #expect(!args.contains("--allowedTools"))
        await service.stop()
    }

    @Test func resumeReadsHistoryFromTranscript() async throws {
        let sandbox = try Sandbox()
        try sandbox.writeTranscript(sessionID: "s-1", lines: [
            #"{"type":"user","uuid":"u1","message":{"role":"user","content":"selam"}}"#,
            #"{"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"text","text":"merhaba"}]}}"#,
        ])
        let spawner = FakeStreamingProcess()
        let service = sandbox.service(spawner: spawner)

        let run = try await service.start(OrchestratorLaunch(sessionID: "s-1", resume: true))

        #expect(run.history.map(\.id) == ["u1", "a1"])
        let args = try #require(spawner.spawns.first?.arguments)
        #expect(value(after: "--resume", in: args) == "s-1")
        await service.stop()
    }

    /// Transkript yoksa `--resume` hata verirdi — aynı kimlikle yeni konuşma açılır.
    @Test func resumeWithoutTranscriptStartsFreshWithSameID() async throws {
        let sandbox = try Sandbox()
        let spawner = FakeStreamingProcess()
        let service = sandbox.service(spawner: spawner)

        _ = try await service.start(OrchestratorLaunch(sessionID: "gone", resume: true))

        let args = try #require(spawner.spawns.first?.arguments)
        #expect(value(after: "--session-id", in: args) == "gone")
        #expect(!args.contains("--resume"))
        await service.stop()
    }

    @Test func missingClaudeBinaryThrows() async throws {
        let sandbox = try Sandbox()
        let spawner = FakeStreamingProcess()
        let service = sandbox.service(spawner: spawner, binary: nil)

        await #expect(throws: LumiError.cliNotFound(binary: "claude")) {
            _ = try await service.start(OrchestratorLaunch(sessionID: "s-1", resume: false))
        }
        #expect(spawner.spawns.isEmpty)
    }

    @Test func restartStopsPreviousProcess() async throws {
        let sandbox = try Sandbox()
        let spawner = FakeStreamingProcess()
        let service = sandbox.service(spawner: spawner)

        let first = try await service.start(OrchestratorLaunch(sessionID: "s-1", resume: false))
        _ = try await service.start(OrchestratorLaunch(sessionID: "s-2", resume: false))

        // İlk sürecin akışı biter (stop → finish).
        var count = 0
        for await _ in first.updates { count += 1 }
        #expect(count >= 1)
        #expect(spawner.spawns.count == 2)
        await service.stop()
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
