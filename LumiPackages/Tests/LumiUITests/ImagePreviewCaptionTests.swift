import AppKit
import XCTest
@testable import LumiUI

/// Görsel önizleme altyazısı (karar 21). Saf biçimlendirme + retina tuzağı:
/// `NSImage.size` DPI'a göre ölçekli gelir, gerçek piksel boyutu
/// representation'dan okunmalıdır.
final class ImagePreviewCaptionTests: XCTestCase {
    func testFormatsDimensionsAndByteCount() {
        let caption = ImagePreviewCaption.make(pixelWidth: 1024, pixelHeight: 512, byteCount: 86_016)
        XCTAssertTrue(caption.hasPrefix("1024×512 · "), "beklenmeyen biçim: \(caption)")
        XCTAssertTrue(caption.contains("KB"), "beklenmeyen biçim: \(caption)")
    }

    func testZeroByteCountStillProducesCaption() {
        let caption = ImagePreviewCaption.make(pixelWidth: 1, pixelHeight: 1, byteCount: 0)
        XCTAssertTrue(caption.hasPrefix("1×1 · "), "beklenmeyen biçim: \(caption)")
    }

    func testUsesPixelDimensionsNotScaledImageSize() {
        // Retina asset: 200×100 piksel, ama NSImage.size 100×50 raporlar.
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 200,
            pixelsHigh: 100,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 100, height: 50))
        image.addRepresentation(representation)

        let caption = ImagePreviewCaption.make(image: image, byteCount: 1024)
        XCTAssertTrue(caption.hasPrefix("200×100 · "), "beklenmeyen biçim: \(caption)")
    }
}
