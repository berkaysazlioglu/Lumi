import Foundation
import XCTest
import LumiKit
@testable import LumiServices

final class SystemServiceTests: XCTestCase {
    private final class OpenerSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func record(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        var opened: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }

    func testOpenExternalAllowsHTTPSchemes() throws {
        let spy = OpenerSpy()
        let service = SystemService(opener: { spy.record($0) })

        try service.openExternal(URL(string: "https://example.com")!)
        try service.openExternal(URL(string: "http://example.com")!)
        XCTAssertEqual(spy.opened.count, 2)
    }

    func testOpenExternalBlocksNonHTTP() {
        let spy = OpenerSpy()
        let service = SystemService(opener: { spy.record($0) })
        let blocked = URL(string: "file:///etc/passwd")!

        XCTAssertThrowsError(try service.openExternal(blocked)) { error in
            XCTAssertEqual(error as? LumiError, .externalURLBlocked(blocked))
        }
        XCTAssertTrue(spy.opened.isEmpty, "engellenen URL opener'a ulaşmamalı")
    }

    func testFixProcessPathKeepsExistingEntriesAndDeduplicates() async {
        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let service = SystemService()

        await service.fixProcessPath()

        let merged = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for entry in originalPath.split(separator: ":").map(String.init) {
            XCTAssertTrue(merged.contains(entry), "mevcut PATH girdisi korunmalı: \(entry)")
        }
        let entries = merged.split(separator: ":").map(String.init)
        XCTAssertEqual(entries.count, Set(entries).count, "PATH girdileri dedupe edilmeli")
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin") {
            XCTAssertTrue(entries.contains("/opt/homebrew/bin"))
        }
    }
}
