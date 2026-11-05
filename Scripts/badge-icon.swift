// Test build'lerinin ikonu (Scripts/make-app.sh): Lumi ikonunun renk tonunu
// kaydırır ve sağ üst köşeye numaralı bir rozet basar — Applications'a kurulan
// gerçek Lumi ile dist/slot build'leri Dock'ta ve Finder'da karışmasın.
//
// Kullanım: swift Scripts/badge-icon.swift <girdi.png> <çıktı.png> <etiket> [ton-derecesi]
import AppKit
import CoreImage

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write(Data("kullanım: badge-icon.swift <girdi.png> <çıktı.png> <etiket> [ton-derecesi]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let label = arguments[3]
let hueDegrees = arguments.count > 4 ? Double(arguments[4]) ?? 0 : 0

guard let source = CIImage(contentsOf: input) else {
    FileHandle.standardError.write(Data("ikon okunamadı: \(input.path)\n".utf8))
    exit(1)
}
let hue = CIFilter(name: "CIHueAdjust")!
hue.setValue(source, forKey: kCIInputImageKey)
hue.setValue(hueDegrees * .pi / 180, forKey: kCIInputAngleKey)
let context = CIContext()
guard let tinted = hue.outputImage, let cgImage = context.createCGImage(tinted, from: source.extent) else { exit(1) }

let side = Int(source.extent.width)
let canvas = CGFloat(side)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))

// Rozet: ikonun gövdesinin sağ üst köşesinde, beyaz çerçeveli koyu daire.
let diameter = canvas * 0.34
let badge = CGRect(x: canvas * 0.95 - diameter, y: canvas * 0.95 - diameter, width: diameter, height: diameter)
let circle = NSBezierPath(ovalIn: badge)
NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.16, alpha: 0.96).setFill()
circle.fill()
NSColor.white.setStroke()
circle.lineWidth = canvas * 0.022
circle.stroke()

let fontSize = diameter * (label.count <= 1 ? 0.62 : label.count == 2 ? 0.48 : 0.34)
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
    .foregroundColor: NSColor.white,
]
let text = NSAttributedString(string: label, attributes: attributes)
let textSize = text.size()
text.draw(at: CGPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2))
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
