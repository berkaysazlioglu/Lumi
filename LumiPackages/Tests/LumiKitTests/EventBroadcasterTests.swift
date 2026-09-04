import XCTest
@testable import LumiKit

final class EventBroadcasterTests: XCTestCase {
    func testDeliversEventsInOrder() async {
        let broadcaster = EventBroadcaster<Int>()
        let stream = broadcaster.stream()

        // AsyncStream buffer'ı sınırsızdır: tüketim başlamadan gönderilenler kaybolmaz
        broadcaster.send(1)
        broadcaster.send(2)

        var received: [Int] = []
        for await value in stream {
            received.append(value)
            if received.count == 2 { break }
        }
        XCTAssertEqual(received, [1, 2])
    }

    func testMultipleStreamsReceiveSameEvents() async {
        let broadcaster = EventBroadcaster<String>()
        let first = broadcaster.stream()
        let second = broadcaster.stream()
        broadcaster.send("hello")

        var fromFirst: [String] = []
        for await value in first {
            fromFirst.append(value)
            break
        }
        var fromSecond: [String] = []
        for await value in second {
            fromSecond.append(value)
            break
        }
        XCTAssertEqual(fromFirst, ["hello"])
        XCTAssertEqual(fromSecond, ["hello"])
    }

    func testFinishAllEndsStreams() async {
        let broadcaster = EventBroadcaster<Int>()
        let stream = broadcaster.stream()
        broadcaster.finishAll()

        var received: [Int] = []
        for await value in stream {
            received.append(value)
        }
        XCTAssertTrue(received.isEmpty)
    }

    /// Faz 1.19: opsiyonel buffering politikası — varsayılan davranış (unbounded)
    /// korunur, isteyen akış en yeniyle sınırlanabilir.
    func testBufferingNewestKeepsOnlyLatestEvents() async {
        let broadcaster = EventBroadcaster<Int>(bufferingPolicy: .bufferingNewest(1))
        let stream = broadcaster.stream()
        broadcaster.send(1)
        broadcaster.send(2)
        broadcaster.send(3)
        broadcaster.finishAll()

        var received: [Int] = []
        for await value in stream {
            received.append(value)
        }
        XCTAssertEqual(received, [3])
    }

    func testDefaultPolicyBuffersEveryEvent() async {
        let broadcaster = EventBroadcaster<Int>()
        let stream = broadcaster.stream()
        broadcaster.send(1)
        broadcaster.send(2)
        broadcaster.finishAll()

        var received: [Int] = []
        for await value in stream {
            received.append(value)
        }
        XCTAssertEqual(received, [1, 2])
    }
}
