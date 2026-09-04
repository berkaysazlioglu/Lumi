import Foundation
import XCTest
@testable import LumiKit

/// `JSONValue` — üç kopyanın (ConfigCodec, ClaudeUsageAPIParser,
/// CodexUsageParser) tek tanımı (refactor 5.7). Kritik olan iki semantik farkın
/// parametreyle korunduğunu kanıtlar.
final class JSONValueTests: XCTestCase {
    /// `JSONSerialization` çıktısındaki gerçek tipleri kullanmak için sözlüğü
    /// JSON'dan geçiririz (Swift literal'i NSNumber köprüsünü gizleyebilir).
    private func parsed(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Bool sızması engeli (her çağrı yerinde geçerli)

    func testBooleanIsNeverReadAsANumber() throws {
        let dict = try parsed(#"{"flag": true, "off": false}"#)
        XCTAssertNil(JSONValue.int(dict["flag"]))
        XCTAssertNil(JSONValue.double(dict["flag"]))
        XCTAssertNil(JSONValue.roundedInt(dict["flag"]))
        XCTAssertNil(JSONValue.int(dict["off"]))
    }

    func testNumberIsNeverReadAsABoolean() throws {
        let dict = try parsed(#"{"one": 1, "zero": 0}"#)
        XCTAssertNil(JSONValue.bool(dict["one"]))
        XCTAssertNil(JSONValue.bool(dict["zero"]))
    }

    func testBooleanReadsAsBoolean() throws {
        let dict = try parsed(#"{"flag": true, "off": false}"#)
        XCTAssertEqual(JSONValue.bool(dict["flag"]), true)
        XCTAssertEqual(JSONValue.bool(dict["off"]), false)
    }

    // MARK: - String kabulü (yalnız kullanım API'lerinde)

    func testStringsAreRejectedByDefault() {
        XCTAssertNil(JSONValue.int("42"))
        XCTAssertNil(JSONValue.double("42.5"))
        XCTAssertNil(JSONValue.roundedInt("42"))
    }

    func testStringsAreAcceptedWhenRequested() {
        XCTAssertEqual(JSONValue.int("42", acceptingStrings: true), 42)
        XCTAssertEqual(JSONValue.double("42.5", acceptingStrings: true), 42.5)
        XCTAssertEqual(JSONValue.roundedInt("42.6", acceptingStrings: true), 43)
        XCTAssertNil(JSONValue.int("abc", acceptingStrings: true))
    }

    // MARK: - Kesme (config) vs yuvarlama (kullanım yüzdeleri)

    func testIntTruncatesWhileRoundedIntRounds() throws {
        let dict = try parsed(#"{"value": 13.9}"#)
        XCTAssertEqual(JSONValue.int(dict["value"]), 13)
        XCTAssertEqual(JSONValue.roundedInt(dict["value"]), 14)
    }

    // MARK: - Kenar durumlar

    func testNilAndUnsupportedTypesReturnNil() {
        XCTAssertNil(JSONValue.int(nil))
        XCTAssertNil(JSONValue.double(nil))
        XCTAssertNil(JSONValue.bool(nil))
        XCTAssertNil(JSONValue.int(["a"]))
        XCTAssertNil(JSONValue.bool("true"))
    }

    func testNonFiniteStringsDoNotProduceAnInt() {
        XCTAssertNil(JSONValue.int("inf", acceptingStrings: true))
        XCTAssertNil(JSONValue.roundedInt("nan", acceptingStrings: true))
    }

    func testNullIsNotANumber() throws {
        let dict = try parsed(#"{"value": null}"#)
        XCTAssertNil(JSONValue.int(dict["value"]))
        XCTAssertNil(JSONValue.bool(dict["value"]))
    }
}
