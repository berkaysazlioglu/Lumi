import XCTest
@testable import LumiKit

/// Uzantı → sunum sınıfı eşlemesi (karar 21).
final class FilePreviewKindTests: XCTestCase {
    func testMarkdownExtensionsAreDetectedCaseInsensitively() {
        XCTAssertEqual(FilePreviewKind.of(path: "README.md"), .markdown)
        XCTAssertEqual(FilePreviewKind.of(path: "docs/design/00-architecture.MD"), .markdown)
        XCTAssertEqual(FilePreviewKind.of(path: "notes.markdown"), .markdown)
        XCTAssertEqual(FilePreviewKind.of(path: "page.mdx"), .markdown)
    }

    func testImageExtensionsAreDetected() {
        for path in ["a.png", "b.JPG", "c.jpeg", "d.gif", "e.webp", "f.heic", "g.tiff", "h.ico"] {
            XCTAssertEqual(FilePreviewKind.of(path: path), .image, path)
        }
    }

    func testSvgStaysTextSoItDiffsAsXml() {
        XCTAssertEqual(FilePreviewKind.of(path: "icon.svg"), .text)
    }

    func testUnknownAndExtensionlessPathsAreText() {
        XCTAssertEqual(FilePreviewKind.of(path: "Makefile"), .text)
        XCTAssertEqual(FilePreviewKind.of(path: "src/main.swift"), .text)
        XCTAssertEqual(FilePreviewKind.of(path: ""), .text)
    }

    /// Video/ses/arşiv gibi dosyalar metin olarak okunmaz (crash düzeltmesi):
    /// FileViewer bunları `unsupported` sunar, `readFile` hiç çağrılmaz.
    func testBinaryMediaAndArchiveExtensionsAreDetected() {
        for path in [
            "clip.mp4", "movie.MOV", "song.mp3", "pack.zip", "lib.dylib", "font.ttf",
            "doc.pdf", "db.sqlite", "image.dmg", "app.jar", "model.onnx",
        ] {
            XCTAssertEqual(FilePreviewKind.of(path: path), .binary, path)
        }
    }

    func testDirectoryNameIsNotMistakenForExtension() {
        XCTAssertEqual(FilePreviewKind.of(path: "my.png.dir/file.txt"), .text)
    }
}
