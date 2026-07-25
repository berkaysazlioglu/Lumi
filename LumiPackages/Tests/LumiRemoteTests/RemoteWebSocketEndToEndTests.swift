import LumiKit
import XCTest
@testable import LumiRemote

/// Gerçek FlyingFox sunucusu + URLSessionWebSocketTask ile uçtan uca WS testi.
/// Özellikle 16KB frame sınırını aşan (fragmented) snapshot'ların istemcide
/// tek parça, geçerli JSON olarak toplanabildiğini doğrular.
final class RemoteWebSocketEndToEndTests: XCTestCase {
    private static let port: UInt16 = 58485
    private let terminalID = "11111111-1111-1111-1111-111111111111"

    /// Gerçek Claude Code ekranına benzer, bilerek büyük (>64KB JSON) snapshot.
    private func makeLargeSnapshot() -> TerminalScreenSnapshot {
        let history = (1...400).map { "geçmiş satırı \($0): lorem ipsum dolor sit amet" }
            .joined(separator: "\n")
        let screen: [[TerminalScreenRun]] = (0..<40).map { row in
            (0..<12).map { col in
                TerminalScreenRun(
                    text: "hücre-\(row)-\(col) ",
                    foreground: "#7c6cf0",
                    background: col % 3 == 0 ? "#1c1f2b" : nil,
                    flags: col % 2
                )
            }
        }
        return TerminalScreenSnapshot(history: history, screen: screen)
    }

    @MainActor
    func testLargeSnapshotSurvivesWebSocketRoundTrip() async throws {
        let snapshot = makeLargeSnapshot()
        let encoded = RemoteMessageCodec.encodeServer(
            .snapshot(snapshot: snapshot, terminal: makeSummary(id: terminalID))
        )
        XCTAssertGreaterThan(encoded.utf8.count, 16384, "test payload'ı frame sınırını aşmalı")

        let provider = FakeRemoteProvider(
            summaries: [makeSummary(id: terminalID)],
            screens: [terminalID: snapshot]
        )
        let server = RemoteDashboardServer(provider: provider, port: Self.port)
        try await server.start()
        defer { Task { await server.stop() } }

        let url = try XCTUnwrap(URL(string: "ws://127.0.0.1:\(Self.port)/ws"))
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        try await socket.send(.string(#"{"type":"attach","id":"\#(terminalID)"}"#))
        let message = try await socket.receive()

        guard case .string(let raw) = message else {
            return XCTFail("text frame bekleniyordu, gelen: \(message)")
        }
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
            "JSON parse edilemedi (fragment sorunu?): \(raw.prefix(200))"
        )
        XCTAssertEqual(decoded["type"] as? String, "snapshot")
        let history = try XCTUnwrap(decoded["history"] as? String)
        XCTAssertTrue(history.contains("geçmiş satırı 400"))
        let screen = try XCTUnwrap(decoded["screen"] as? [[[String: Any]]])
        XCTAssertEqual(screen.count, 40)
        XCTAssertEqual(screen[39].count, 12)
        await server.stop()
    }
}
