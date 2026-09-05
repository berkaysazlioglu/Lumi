import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

/// 1.8 / karar 32: OAuth yolundaki hataların hangisinin CLI yedeğine düşeceği,
/// hangisinin görünür hata olacağı. CLI yedeği abonelik kotasından düştüğü için
/// geçici sunucu/ağ hatalarında ÇAĞRILMAMALIDIR.
///
/// **Bu sınıf host'a HİÇ çıkmaz.** Üç kenar da ikame edilir: HTTP `URLProtocol`
/// stub'ıyla, PATH araması `FakeBinaryLocator` ile, process çalıştırma
/// `FakeProcessRunner` ile. `.transportError` adımının ürettiği
/// `NSURLErrorDomain -1005` gerçek bir ağ hatası değil, stub'ın bilinçli
/// enjeksiyonudur; `testEveryRequestGoesThroughTheInjectedStub` da tek
/// dokunulan URL'in usage endpoint'i olduğunu kilitler.
final class ClaudeUsageServiceTests: XCTestCase {
    /// PATH'te bulunmayacak bir ad: CLI yoluna düşüldüğü `.cliNotFound` ile
    /// kesin olarak gözlenir. `FakeBinaryLocator` boş olduğu için gerçek
    /// PATH'te böyle bir arama hiç yapılmaz.
    private static let missingBinary = "lumi-yok-claude-binary"

    private let validBody = """
    {"limits":[{"kind":"session","percent":42,"resets_at":"2026-09-04T12:00:00Z"}]}
    """.data(using: .utf8)!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset([])
    }

    private func makeService(
        steps: [StubURLProtocol.Step],
        token: String? = "test-token"
    ) -> ClaudeUsageService {
        StubURLProtocol.reset(steps)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ClaudeUsageService(
            binaryName: Self.missingBinary,
            session: URLSession(configuration: configuration),
            retryDelay: .zero,
            // Host'un PATH'i ve process'leri testin dışında kalır.
            runner: FakeProcessRunner(),
            locator: FakeBinaryLocator(),
            accessToken: { token }
        )
    }

    // MARK: - (a) CLI yedeğine düşen yollar

    func testMissingTokenFallsBackToCLIWithoutAnyRequest() async {
        let service = makeService(steps: [.status(200, validBody)], token: nil)

        await assertThrows(service, expected: .cliNotFound(binary: Self.missingBinary))
        XCTAssertEqual(StubURLProtocol.requestCount, 0, "token yokken istek atılmamalı")
    }

    func testUnauthorizedFallsBackToCLIWithoutRetry() async {
        let service = makeService(steps: [.status(401, Data())])

        await assertThrows(service, expected: .cliNotFound(binary: Self.missingBinary))
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "401 yeniden denenmemeli")
    }

    func testForbiddenFallsBackToCLI() async {
        let service = makeService(steps: [.status(403, Data())])

        await assertThrows(service, expected: .cliNotFound(binary: Self.missingBinary))
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testUnrecognizedBodyFallsBackToCLI() async {
        let service = makeService(steps: [.status(200, Data("{}".utf8))])

        await assertThrows(service, expected: .cliNotFound(binary: Self.missingBinary))
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    // MARK: - (b) CLI'a DÜŞMEYEN yollar: tek retry, sonra görünür hata

    func testServerErrorRetriesOnceThenThrowsWithoutCLIFallback() async {
        let service = makeService(steps: [.status(500, Data())])

        let error = await captureError(service)
        guard case .usageUnavailable(let detail)? = error else {
            return XCTFail("beklenen .usageUnavailable, gelen: \(String(describing: error))")
        }
        XCTAssertTrue(detail.contains("500"), "detay HTTP durumunu taşımalı: \(detail)")
        XCTAssertEqual(StubURLProtocol.requestCount, 2, "5xx tam bir kez yeniden denenmeli")
    }

    func testRateLimitedRetriesOnceThenThrows() async {
        let service = makeService(steps: [.status(429, Data())])

        let error = await captureError(service)
        guard case .usageUnavailable(let detail)? = error else {
            return XCTFail("beklenen .usageUnavailable, gelen: \(String(describing: error))")
        }
        XCTAssertTrue(detail.contains("429"), detail)
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testTransportErrorRetriesOnceThenThrows() async {
        let service = makeService(steps: [.transportError])

        let error = await captureError(service)
        guard case .usageUnavailable? = error else {
            return XCTFail("beklenen .usageUnavailable, gelen: \(String(describing: error))")
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    // MARK: - Başarı yolları

    func testSuccessfulResponseUsesOAuthOnly() async throws {
        let service = makeService(steps: [.status(200, validBody)])

        let snapshot = try await service.fetch()
        XCTAssertEqual(snapshot.fiveHour?.percentUsed, 42)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testTransientFailureRecoversOnRetry() async throws {
        let service = makeService(steps: [.transportError, .status(200, validBody)])

        let snapshot = try await service.fetch()
        XCTAssertEqual(snapshot.fiveHour?.percentUsed, 42)
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    // MARK: - Ağ izolasyonu

    /// Servis yalnız enjekte edilen oturumu kullanır ve tek bir endpoint'e
    /// gider: testler hiçbir koşulda gerçek bir host'a çıkmaz.
    func testEveryRequestGoesThroughTheInjectedStub() async throws {
        let service = makeService(steps: [.transportError, .status(200, validBody)])

        _ = try await service.fetch()

        XCTAssertEqual(StubURLProtocol.requestCount, 2)
        XCTAssertEqual(
            Set(StubURLProtocol.requestedURLs),
            [ClaudeUsageService.usageURL],
            "stub dışına çıkan bir istek var"
        )
    }

    // MARK: - Yardımcılar

    private func captureError(
        _ service: ClaudeUsageService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> LumiError? {
        do {
            _ = try await service.fetch()
            XCTFail("fetch hata fırlatmadı", file: file, line: line)
            return nil
        } catch let error as LumiError {
            return error
        } catch {
            XCTFail("LumiError beklenirken \(error)", file: file, line: line)
            return nil
        }
    }

    private func assertThrows(
        _ service: ClaudeUsageService,
        expected: LumiError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let error = await captureError(service, file: file, line: line)
        XCTAssertEqual(error, expected, file: file, line: line)
    }
}

/// Enjekte edilebilir `URLSession` üzerinden yanıtları senaryolayan stub.
/// Kuyruktaki son adım tükenmez (aynı hata tekrar döner) — retry davranışı
/// tek adımla kurulabilir.
final class StubURLProtocol: URLProtocol {
    enum Step: Sendable {
        case status(Int, Data)
        case transportError
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var steps: [Step] = []
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var urls: [URL] = []

    static func reset(_ steps: [Step]) {
        lock.lock()
        defer { lock.unlock() }
        self.steps = steps
        count = 0
        urls = []
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Stub'a ulaşan isteklerin URL'leri — "gerçek ağa çıkıldı mı" sorusunun
    /// kaynak-üstü cevabı.
    static var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    static func record(_ url: URL?) {
        guard let url else { return }
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    private static func nextStep() -> Step {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        if steps.count > 1 { return steps.removeFirst() }
        return steps.first ?? .status(200, Data())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record(request.url)
        switch Self.nextStep() {
        case .status(let code, let body):
            let response = HTTPURLResponse(
                url: request.url ?? ClaudeUsageService.usageURL,
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .transportError:
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        }
    }

    override func stopLoading() {}
}
