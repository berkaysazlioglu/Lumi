import Foundation
import XCTest
@testable import LumiTerminal

/// Karar 149: PTY akışındaki kitty dosya aktarımlarının (`t=f`) ayıklanması
/// ve terminal başına kimlik → yol kaydı.
final class KittyGraphicsFileParserTests: XCTestCase {
    private static let path = "/private/tmp/claude-501/-Users-dev-game/5f0c/images/1.png"

    private static func apc(_ control: String, payload: String? = nil) -> Data {
        var text = "\u{1B}_G" + control
        if let payload { text += ";" + payload }
        return Data((text + "\u{1B}\\").utf8)
    }

    private static func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// Claude Code'un `Image source={{ file }}` için yazdığı dizinin birebir biçimi.
    private static let claudeTransfer = apc("a=T,U=1,q=1,f=100,t=f,i=7,c=16,r=8", payload: base64(path))

    func testClaudeFileTransferYieldsImageIDAndPath() {
        let parser = KittyGraphicsFileParser()

        let files = parser.feed(Data("prompt ".utf8) + Self.claudeTransfer + Data("\u{1B}[0m tail".utf8))

        XCTAssertEqual(files, [KittyImageFile(imageID: 7, path: Self.path)])
    }

    /// PTY okuması diziyi herhangi bir baytta bölebilir.
    func testTransferSplitAtEveryByteBoundaryIsStillRecognized() {
        let stream = Data("\u{1B}[31mx".utf8) + Self.claudeTransfer
        for split in 1 ..< stream.count {
            let parser = KittyGraphicsFileParser()
            let files = parser.feed(stream.prefix(split)) + parser.feed(stream.suffix(from: split))
            XCTAssertEqual(files, [KittyImageFile(imageID: 7, path: Self.path)], "bölme: \(split)")
        }
    }

    func testByteTransfersQueriesAndForeignAPCsAreIgnored() {
        let parser = KittyGraphicsFileParser()
        let bytes = Self.apc("a=T,U=1,q=2,f=100,i=8,c=4,r=2", payload: String(repeating: "QUFB", count: 5000))
        let chunked = Self.apc("a=T,f=100,t=f,i=9,m=1", payload: Self.base64(Self.path))
        let query = Self.apc("i=31,s=1,v=1,a=q,t=f,f=32", payload: Self.base64(Self.path))
        let withoutID = Self.apc("a=T,t=f,f=100", payload: Self.base64(Self.path))
        let foreign = Data("\u{1B}_Xsomething\u{1B}\\".utf8)

        let files = parser.feed(bytes + chunked + query + withoutID + foreign)

        XCTAssertTrue(files.isEmpty)
    }

    func testRelativeOrMalformedPathsAreRejected() {
        let parser = KittyGraphicsFileParser()
        let relative = Self.apc("a=T,t=f,i=3", payload: Self.base64("images/1.png"))
        let notBase64 = Self.apc("a=T,t=f,i=4", payload: "%%%")
        let withNUL = Self.apc("a=T,t=f,i=5", payload: Data("/tmp/a\u{0}b".utf8).base64EncodedString())

        XCTAssertTrue(parser.feed(relative + notBase64 + withNUL).isEmpty)
    }

    /// `a=t` (yalnız aktar) da bir görsel kaydeder; varsayılan eylem de aktarımdır.
    func testTransmitOnlyActionsAreRecorded() {
        let parser = KittyGraphicsFileParser()

        let files = parser.feed(
            Self.apc("a=t,t=f,i=11", payload: Self.base64("/a.png"))
                + Self.apc("t=f,i=12", payload: Self.base64("/b.png"))
        )

        XCTAssertEqual(files.map(\.imageID), [11, 12])
    }

    /// ST'siz kesilen dizi sonraki diziyi yutmaz.
    func testInterruptedSequenceDoesNotSwallowTheNextOne() {
        let parser = KittyGraphicsFileParser()
        let cut = Data("\u{1B}_Ga=T,t=f,i=2;AAAA".utf8)

        let files = parser.feed(cut + Self.claudeTransfer)

        XCTAssertEqual(files, [KittyImageFile(imageID: 7, path: Self.path)])
    }

    func testOversizedPayloadIsDropped() {
        let parser = KittyGraphicsFileParser()
        let huge = String(repeating: "A", count: KittyGraphicsFileParser.maxPayloadLength + 4)

        let files = parser.feed(Self.apc("a=T,t=f,i=6", payload: huge) + Self.claudeTransfer)

        XCTAssertEqual(files.map(\.imageID), [7])
    }

    func testResetDropsHalfSequence() {
        let parser = KittyGraphicsFileParser()
        let transfer = Self.claudeTransfer

        _ = parser.feed(transfer.prefix(20))
        parser.reset()
        let files = parser.feed(transfer.suffix(from: 20))

        XCTAssertTrue(files.isEmpty)
    }

    // MARK: - Kayıt

    func testRegistryResolvesExactAndLow24BitIDs() {
        var registry = TerminalKittyImageFiles()
        registry.record(KittyImageFile(imageID: 7, path: "/a.png"))
        registry.record(KittyImageFile(imageID: 0x0100_0009, path: "/b.png"))

        XCTAssertEqual(registry.path(forPlaceholderID: 7), "/a.png")
        XCTAssertEqual(registry.path(forPlaceholderID: 9), "/b.png", "üst bayt placeholder renginde taşınmaz")
        XCTAssertNil(registry.path(forPlaceholderID: 8))
    }

    func testRegistryPrefersTheLatestTransferForAReusedID() {
        var registry = TerminalKittyImageFiles()
        registry.record(KittyImageFile(imageID: 0x0100_0009, path: "/old.png"))
        registry.record(KittyImageFile(imageID: 0x0200_0009, path: "/new.png"))
        registry.record(KittyImageFile(imageID: 3, path: "/x.png"))
        registry.record(KittyImageFile(imageID: 3, path: "/y.png"))

        XCTAssertEqual(registry.path(forPlaceholderID: 9), "/new.png")
        XCTAssertEqual(registry.path(forPlaceholderID: 3), "/y.png")
    }

    func testRegistryEvictsTheOldestBeyondCapacity() {
        var registry = TerminalKittyImageFiles()
        for id in 1 ... UInt32(TerminalKittyImageFiles.capacity + 1) {
            registry.record(KittyImageFile(imageID: id, path: "/\(id).png"))
        }

        XCTAssertEqual(registry.count, TerminalKittyImageFiles.capacity)
        XCTAssertNil(registry.path(forPlaceholderID: 1))
        XCTAssertEqual(registry.path(forPlaceholderID: 2), "/2.png")
    }
}
