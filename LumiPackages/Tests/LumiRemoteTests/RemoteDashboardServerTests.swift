import XCTest
@testable import LumiRemote

final class RemoteDashboardServerTests: XCTestCase {
    /// Testlere özel, çakışma ihtimali düşük port.
    private static let port: UInt16 = 58484

    @MainActor
    func testServesDashboardTerminalListAndLifecycle() async throws {
        let provider = FakeRemoteProvider(summaries: [makeSummary()])
        let server = RemoteDashboardServer(provider: provider, port: Self.port)
        XCTAssertFalse(server.status.isRunning)

        try await server.start()
        XCTAssertTrue(server.status.isRunning)
        let url = try XCTUnwrap(server.status.url)
        XCTAssertTrue(url.hasPrefix("http://"))
        XCTAssertTrue(url.hasSuffix(":\(Self.port)"))

        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(Self.port)"))
        let (html, htmlResponse) = try await URLSession.shared.data(from: base)
        XCTAssertEqual((htmlResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: html, as: UTF8.self).contains("<title>Lumi</title>"))

        let (api, _) = try await URLSession.shared.data(
            from: base.appendingPathComponent("api/terminals")
        )
        let decoded = try JSONDecoder().decode(TerminalListResponse.self, from: api)
        XCTAssertEqual(decoded.terminals, [makeSummary()])

        await server.stop()
        XCTAssertFalse(server.status.isRunning)
        XCTAssertNil(server.status.url)

        // İkinci start/stop turu — port temiz bırakılıyor mu?
        try await server.start()
        XCTAssertTrue(server.status.isRunning)
        await server.stop()
    }

    /// Tercih edilen port doluysa (zombi soket / ikinci instance senaryosu)
    /// sunucu aralıktaki bir sonraki boş porta kayar.
    @MainActor
    func testFallsBackToNextPortWhenPreferredIsBusy() async throws {
        let busyPort: UInt16 = 58490
        let blocker = try makeBlockingListener(port: busyPort)
        defer { close(blocker) }

        let server = RemoteDashboardServer(
            provider: FakeRemoteProvider(summaries: [makeSummary()]),
            port: busyPort
        )
        try await server.start()
        defer { Task { await server.stop() } }

        let url = try XCTUnwrap(server.status.url)
        XCTAssertTrue(url.hasSuffix(":\(busyPort + 1)"), "beklenen fallback portu, gelen: \(url)")

        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(busyPort + 1)/api/terminals"))
        let (data, response) = try await URLSession.shared.data(from: base)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode(TerminalListResponse.self, from: data).terminals.count, 1)
        await server.stop()
    }

    /// Test için IPv6 wildcard'a bind edilmiş gerçek bir dinleyici.
    private func makeBlockingListener(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_any
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        XCTAssertEqual(result, 0, "blocker bind başarısız: errno \(errno)")
        XCTAssertEqual(listen(fd, 4), 0)
        return fd
    }
}

final class LocalNetworkAddressTests: XCTestCase {
    func testPrimaryIPv4IsNumericWhenAvailable() {
        // Ağ arayüzü olmayan CI ortamında nil dönebilir — sözleşme yalnız
        // "dönerse sayısal IPv4" olmasıdır.
        guard let host = LocalNetworkAddress.primaryIPv4() else { return }
        let parts = host.split(separator: ".")
        XCTAssertEqual(parts.count, 4)
        XCTAssertTrue(parts.allSatisfy { UInt8($0) != nil })
    }
}
