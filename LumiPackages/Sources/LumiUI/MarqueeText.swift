import SwiftUI

/// Tek satır metin; `animating` true VE metin kabına sığmıyorsa sağdan sola
/// kayar (commit başlıkları hover'da — v1 marquee paritesi). Sabit hızla
/// (pt/sn) sona kadar kayıp geri döner; sığıyorsa statik kalır.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, design: .monospaced)
    var color: Color = Theme.textPrimary
    /// Dışarıdan (satır hover'ı) sürülür; tek sorumluluk: kayma kararı burada.
    var animating: Bool = false
    var pointsPerSecond: Double = 40

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }
    private var shouldScroll: Bool { animating && overflow > 1 }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background(measure { textWidth = $0 })
            .offset(x: shouldScroll ? offset : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .background(measure { containerWidth = $0 })
            .onChange(of: shouldScroll) { _, scroll in animate(scroll) }
            .onChange(of: text) { _, _ in offset = 0 }
    }

    private func animate(_ scroll: Bool) {
        guard scroll else {
            withAnimation(.easeOut(duration: 0.15)) { offset = 0 }
            return
        }
        offset = 0
        let duration = Double(overflow) / pointsPerSecond
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: true)) {
            offset = -overflow
        }
    }

    /// Genişlik ölçer — Text intrinsic (ilk) ve kaba sığdırılmış (ikinci) için.
    private func measure(_ update: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { update(geo.size.width) }
                .onChange(of: geo.size.width) { _, width in update(width) }
        }
    }
}
