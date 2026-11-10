import Foundation
import XCTest
import LumiKit
@testable import LumiRemote

final class RelayConnectionTests: XCTestCase {
    func testStartPublishesConnectingThenDisconnectedOnUnreachableHost() async throws {
        let connection = RelayConnection()
        let stream = await connection.inbound()
        // Kapalı porta bağlanma → connecting, ardından disconnected beklenir
        await connection.start(
            endpoint: RelayEndpoint(url: URL(string: "ws://127.0.0.1:1")!, token: "lrs_test"),
            hello: ["role": "mac", "token": "secret-token-1234567890"])

        var states: [RemoteConnectionState] = []
        for await inbound in stream {
            if case .stateChanged(let s) = inbound {
                states.append(s)
                if states.count == 2 { break }
            }
        }
        await connection.stop()
        XCTAssertEqual(states, [.connecting, .disconnected])
    }

    func testStopIsIdempotentAndAllowsRestart() async throws {
        let connection = RelayConnection()
        _ = await connection.inbound()
        await connection.stop()
        await connection.stop()
        await connection.start(
            endpoint: RelayEndpoint(url: URL(string: "ws://127.0.0.1:1")!, token: "lrs_test"),
            hello: ["role": "mac", "token": "secret-token-1234567890"])
        await connection.stop()
        // Çökmeden buraya gelmek yeterli
        XCTAssertTrue(true)
    }

    /// Karar 146/147: 401 ve 4007 kalıcı rettir (yeniden denenmez); 4006 ağa bağlıdır
    /// (denemeye devam edilir); diğer kodlar sunucu reddi değildir.
    func testServerIssueMapping() {
        XCTAssertEqual(RelayConnection.serverIssue(httpStatus: 401, closeCode: nil), .unauthorized)
        XCTAssertEqual(RelayConnection.serverIssue(httpStatus: nil, closeCode: 4006), .networkNotAllowed)
        XCTAssertEqual(RelayConnection.serverIssue(httpStatus: nil, closeCode: 4007), .tokenRevoked)
        XCTAssertNil(RelayConnection.serverIssue(httpStatus: 429, closeCode: nil))
        XCTAssertNil(RelayConnection.serverIssue(httpStatus: nil, closeCode: 4003))
        XCTAssertNil(RelayConnection.serverIssue(httpStatus: nil, closeCode: 1006))
        XCTAssertTrue(RemoteServerIssue.unauthorized.isPermanent)
        XCTAssertTrue(RemoteServerIssue.tokenRevoked.isPermanent)
        XCTAssertFalse(RemoteServerIssue.networkNotAllowed.isPermanent)
    }

    /// Karar 147: geri çekilme beklemesindeki bağlantı ağ sinyaliyle hemen yeniden dener.
    /// Taban gecikme 60 sn olduğu için ikinci `connecting` ancak sinyalden gelebilir.
    func testNetworkChangeCutsBackoffWait() async throws {
        let network = ManualNetworkSignal()
        let connection = RelayConnection(network: network, backoff: ReconnectBackoff(baseSeconds: 60))
        let stream = await connection.inbound()
        await connection.start(
            endpoint: RelayEndpoint(url: URL(string: "ws://127.0.0.1:1")!, token: "lrs_test"),
            hello: ["role": "hub"])

        let collected = Task {
            var states: [RemoteConnectionState] = []
            for await inbound in stream {
                guard case .stateChanged(let s) = inbound else { continue }
                states.append(s)
                if states.count == 2 { network.fire() }
                if states.count == 3 { break }
            }
            return states
        }
        let result = try await withTimeout(seconds: 10) { await collected.value }
        await connection.stop()
        XCTAssertEqual(result, [.connecting, .disconnected, .connecting])
    }

    private func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }
}

/// Elle tetiklenen ağ sinyali.
private final class ManualNetworkSignal: NetworkPathSignaling, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<Void>.Continuation] = []

    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    func fire() {
        for continuation in lock.withLock({ continuations }) { continuation.yield() }
    }
}
