import SwiftUI

/// Tek satır metin; `animating` true VE metin kaba sığmıyorsa sağdan sola kayar
/// (commit başlıkları hover'da — v1 marquee paritesi). Container genişliği
/// GeometryReader ile ölçülür (metnin intrinsic genişliği YUKARI YAYILMAZ —
/// böylece panel genişlemez); metin kaba kırpılır, taşan kısım kayarak görünür.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, design: .monospaced)
    var color: Color = Theme.textPrimary
    /// Dışarıdan (satır hover'ı) sürülür; tek sorumluluk: kayma kararı burada.
    var animating: Bool = false
    var pointsPerSecond: Double = 40

    @State private var textWidth: CGFloat = 0
    @State private var textHeight: CGFloat = 16
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }
    private var shouldScroll: Bool { animating && overflow > 1 }

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()                       // intrinsic genişlik (kırpılmadan ölçülür)
                .background(sizeReader)
                .offset(x: shouldScroll ? offset : 0)
                .frame(width: geo.size.width, alignment: .leading) // kaba sabitlenir
                .clipped()
                .onAppear { containerWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, width in containerWidth = width }
        }
        .frame(height: textHeight)                 // GeometryReader dikey açgözlülüğünü topla
        .onChange(of: shouldScroll) { _, scroll in animate(scroll) }
        .onChange(of: text) { _, _ in offset = 0 }
    }

    private var sizeReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { textWidth = geo.size.width; textHeight = geo.size.height }
                .onChange(of: geo.size) { _, size in
                    textWidth = size.width
                    textHeight = size.height
                }
        }
    }

    private func animate(_ scroll: Bool) {
        guard scroll else {
            // Hover bitti: repeatForever'ı iptal et ve anında başa dön (ease YOK —
            // disablesAnimations transaction kalıcı animasyonu kesin durdurur).
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { offset = 0 }
            return
        }
        offset = 0
        let duration = max(0.5, Double(overflow) / pointsPerSecond)
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: true)) {
            offset = -overflow
        }
    }
}
