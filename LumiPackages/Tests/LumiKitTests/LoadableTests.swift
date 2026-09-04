import LumiKit
import XCTest

/// `Loadable`: yükleme durumu + değer + hata mesajı TEK alanda (refactor 5.3).
final class LoadableTests: XCTestCase {
    func testLoadingHasNoValueAndNoFailureMessage() {
        let state = Loadable<String>.loading
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.value)
        XCTAssertNil(state.failureMessage)
    }

    func testLoadedExposesValueOnly() {
        let state = Loadable<String>.loaded("content")
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.value, "content")
        XCTAssertNil(state.failureMessage)
    }

    func testFailedExposesMessageAndDropsValue() {
        let state = Loadable<String>.failed("boom")
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.value, "hata durumunda bayat değer taşınamaz")
        XCTAssertEqual(state.failureMessage, "boom")
    }

    func testEqualityComparesCaseAndPayload() {
        XCTAssertEqual(Loadable<Int>.loaded(1), .loaded(1))
        XCTAssertNotEqual(Loadable<Int>.loaded(1), .loaded(2))
        XCTAssertNotEqual(Loadable<Int>.loading, .failed("x"))
    }

    func testMapTransformsOnlyLoadedValue() {
        XCTAssertEqual(Loadable<Int>.loaded(2).map { $0 * 3 }, .loaded(6))
        XCTAssertEqual(Loadable<Int>.loading.map { "\($0)" }, .loading)
        XCTAssertEqual(Loadable<Int>.failed("e").map { "\($0)" }, .failed("e"))
    }
}
