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

    /// Karar 146: 401 ve 4006/4007 kalıcı rettir (yeniden denenmez); diğerleri değildir.
    func testPermanentIssueMapping() {
        XCTAssertEqual(RelayConnection.permanentIssue(httpStatus: 401, closeCode: nil), .unauthorized)
        XCTAssertEqual(RelayConnection.permanentIssue(httpStatus: nil, closeCode: 4006), .networkNotAllowed)
        XCTAssertEqual(RelayConnection.permanentIssue(httpStatus: nil, closeCode: 4007), .tokenRevoked)
        XCTAssertNil(RelayConnection.permanentIssue(httpStatus: 429, closeCode: nil))
        XCTAssertNil(RelayConnection.permanentIssue(httpStatus: nil, closeCode: 4003))
        XCTAssertNil(RelayConnection.permanentIssue(httpStatus: nil, closeCode: 1006))
    }
}
