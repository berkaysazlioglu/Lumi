import AppKit
import Foundation
import LumiKit
import LumiTestSupport
import Testing
@testable import LumiRemote

// Controller'da yapıştırılan görsel (karar 143 ek): controller kodlar, hub diske yazıp
// yolunu terminale yazar (Claude `[Image #N]` yapar).

/// `width×height` düz renkli PNG; `noisy` sıkıştırılamayan piksel üretir.
func makePNG(width: Int, height: Int, noisy: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    var generator = SystemRandomNumberGenerator()
    let pixels = rep.bitmapData!
    for index in 0..<(rep.bytesPerRow * height) {
        pixels[index] = noisy ? UInt8.random(in: 0...255, using: &generator) : 0x80
    }
    return rep.representation(using: .png, properties: [:])!
}

@Suite struct RemoteImageEncoderTests {
    @Test func smallPNGPassesThroughByteForByte() {
        let png = makePNG(width: 40, height: 20)
        #expect(RemoteImageEncoder.encode(png) == RemotePastedImage(data: png, ext: "png"))
    }

    @Test func largeNoisyImageShrinksUnderTheRelayBudget() throws {
        let png = makePNG(width: 1800, height: 1200, noisy: true)
        #expect(png.count > RemoteImageEncoder.byteBudget)
        let encoded = try #require(RemoteImageEncoder.encode(png))
        #expect(encoded.data.count <= RemoteImageEncoder.byteBudget)
        let rep = try #require(NSBitmapImageRep(data: encoded.data))
        #expect(max(rep.pixelsWide, rep.pixelsHigh) <= RemoteImageEncoder.maxLongEdge)
    }

    @Test func nonImageIsRejected() {
        #expect(RemoteImageEncoder.encode(Data("not an image".utf8)) == nil)
    }
}

@Suite struct RemotePastedImagesTests {
    @Test func contentMustMatchTheDeclaredFormat() {
        let png = makePNG(width: 4, height: 4).base64EncodedString()
        #expect(throws: RemotePastedImages.Failure.invalidImage) {
            try RemotePastedImages.validate(base64: png, ext: "jpg")
        }
        #expect(throws: RemotePastedImages.Failure.invalidImage) {
            try RemotePastedImages.validate(base64: Data("GIF89a".utf8).base64EncodedString(), ext: "png")
        }
        #expect(throws: RemotePastedImages.Failure.invalidImage) {
            try RemotePastedImages.validate(base64: png, ext: "svg")
        }
    }

    @Test func oversizedImageIsRefused() {
        var big = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        big.append(Data(count: RemotePastedImages.byteLimit))
        #expect(throws: RemotePastedImages.Failure.tooLarge) {
            try RemotePastedImages.validate(base64: big.base64EncodedString(), ext: "png")
        }
    }

    @MainActor
    @Test func handlerStoresTheImageAndTypesItsPathIntoTheTerminal() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-paste-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let terminal = FakeTerminalService()
        let meta = try terminal.spawn(repoPath: "/repo", task: nil, command: nil)
        let handler = RemoteCommandHandler(
            terminal: terminal, trust: FakeClaudeWorkspaceTrust(), config: FakeConfigService(),
            pastedImagesDirectory: directory)
        let png = makePNG(width: 8, height: 8)

        let result = await handler.handle([
            "commandId": "p1", "action": "paste_image", "sessionId": meta.id.description,
            "data": png.base64EncodedString(), "ext": "png",
        ])

        #expect(result.ok)
        let typed = try #require(terminal.writtenTexts.last?.text)
        #expect(typed.hasPrefix(directory.path) && typed.hasSuffix(".png"))
        #expect(!typed.hasSuffix("\r"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: typed)) == png)

        let bad = await handler.handle([
            "commandId": "p2", "action": "paste_image", "sessionId": meta.id.description,
            "data": Data("x".utf8).base64EncodedString(), "ext": "png",
        ])
        #expect(!bad.ok && bad.error == "invalid_image")
    }
}
