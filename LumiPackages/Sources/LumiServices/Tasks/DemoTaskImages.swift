import CoreGraphics
import Foundation
import ImageIO
import LumiKit
import UniformTypeIdentifiers

/// Demo kaynağın görselleri: ağsız çalışsın diye geçici dizine çizilen birkaç
/// PNG (`file://` adresleri). Boyutları bilerek büyüktür — önizleme
/// şeridinin küçültmesi gözle görülsün.
enum DemoTaskImages {
    private static let specs: [(name: String, width: Int, height: Int, colors: (UInt32, UInt32))] = [
        ("board-mockup.png", 1600, 1000, (0x8B5CF6, 0x22D3EE)),
        ("drag-states.png", 1200, 900, (0xF59E0B, 0xF87171)),
        ("empty-state.png", 900, 1400, (0x4ADE80, 0x38BDF8)),
    ]

    static func make() -> [TaskImage] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lumi-demo-task-images")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return specs.compactMap { spec in
            let url = directory.appendingPathComponent(spec.name)
            if !FileManager.default.fileExists(atPath: url.path) {
                guard write(to: url, width: spec.width, height: spec.height, colors: spec.colors) else { return nil }
            }
            return TaskImage(url: url, name: spec.name, width: spec.width, height: spec.height)
        }
    }

    private static func write(to url: URL, width: Int, height: Int, colors: (UInt32, UInt32)) -> Bool {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gradient = CGGradient(
            colorsSpace: space, colors: [cgColor(colors.0), cgColor(colors.1)] as CFArray, locations: [0, 1]
        ) else { return false }
        context.drawLinearGradient(
            gradient, start: .zero, end: CGPoint(x: width, y: height), options: []
        )
        // Birkaç "kart" — görselin ne olduğu küçükken de seçilsin.
        context.setFillColor(CGColor(gray: 1, alpha: 0.18))
        let columns = 4
        let gap = width / 40
        let cardWidth = (width - gap * (columns + 1)) / columns
        for column in 0..<columns {
            for row in 0..<(column + 2) {
                let rect = CGRect(
                    x: gap + column * (cardWidth + gap), y: height - gap - (row + 1) * (height / 8 + gap),
                    width: cardWidth, height: height / 8
                )
                context.addPath(CGPath(roundedRect: rect, cornerWidth: CGFloat(gap) / 2, cornerHeight: CGFloat(gap) / 2, transform: nil))
            }
        }
        context.fillPath()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func cgColor(_ hex: UInt32) -> CGColor {
        CGColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
