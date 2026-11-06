import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Uzak terminale yapıştırılan görseli relay frame'ine sığdırır (karar 143 ek).
///
/// Saf ImageIO — iş parçacığı güvenli, main dışında koşabilir. Zaten PNG/JPEG olan ve
/// sınırlar içindeki görsel bayt bayt korunur; değilse uzun kenar Claude'un kullandığı
/// boyuta indirilir, PNG sığmazsa JPEG kalitesi, o da sığmazsa boyut düşürülür.
public enum RemoteImageEncoder {
    /// Base64 + JSON ile relay'in 1 MB sınırının altında kalır (hub 750 KB'a kadar kabul eder).
    public static let byteBudget = 700 * 1024
    /// Claude görselleri bu uzun kenara indirir; daha büyüğü yalnız maliyettir.
    public static let maxLongEdge = 1568
    static let minLongEdge = 256
    static let jpegQualities: [Double] = [0.85, 0.7, 0.55]

    public static func encode(_ data: Data, budget: Int = byteBudget, maxLongEdge: Int = maxLongEdge) -> RemotePastedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let longEdge = longEdgePixels(source)
        if data.count <= budget, longEdge <= maxLongEdge, let ext = passthroughExtension(source) {
            return RemotePastedImage(data: data, ext: ext)
        }
        var edge = min(maxLongEdge, max(longEdge, 1))
        while edge >= minLongEdge {
            guard let image = thumbnail(source, longEdge: edge) else { return nil }
            if let png = encoded(image, type: .png), png.count <= budget {
                return RemotePastedImage(data: png, ext: "png")
            }
            for quality in jpegQualities {
                if let jpeg = encoded(image, type: .jpeg, quality: quality), jpeg.count <= budget {
                    return RemotePastedImage(data: jpeg, ext: "jpg")
                }
            }
            edge = edge * 3 / 4
        }
        return nil
    }

    private static func passthroughExtension(_ source: CGImageSource) -> String? {
        switch CGImageSourceGetType(source) as String? {
        case UTType.png.identifier?: "png"
        case UTType.jpeg.identifier?: "jpg"
        default: nil
        }
    }

    private static func longEdgePixels(_ source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(width, height)
    }

    private static func thumbnail(_ source: CGImageSource, longEdge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encoded(_ image: CGImage, type: UTType, quality: Double? = nil) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
