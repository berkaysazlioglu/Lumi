import SwiftUI

/// Tek satır metin; `animating` true VE metin kaba sığmıyorsa v1 paritesiyle
/// kayar (globals.css `.commit-message`: `marquee 5s linear infinite`,
/// `translateX(0)` → `translateX(-100%)`). Dükkân tabelası gibi **tek yönlü**
/// soldan sola SÜREKLI akar (ping-pong/autoreverse YOK), her döngüde başa
/// snap'ler. Hover bitince animasyon olmadan **anında** başa döner.
///
/// Uygulama: `repeatForever` SwiftUI'da temiz durdurulamadığından (yapışkan,
/// reset edilemez) süre-tabanlı `TimelineView` kullanılır; durunca statik dala
/// geçilip konum garantili sıfırlanır.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, design: .monospaced)
    var color: Color = Theme.textPrimary
    /// Dışarıdan (satır hover'ı) sürülür; tek sorumluluk: kayma kararı burada.
    var animating: Bool = false

    /// v1 paritesi — span `padding-right: 50px` + `animation: 5s`.
    static let trailingGap: CGFloat = 50
    static let cycleDuration: Double = 5

    @State private var textWidth: CGFloat = 0
    @State private var textHeight: CGFloat = 16
    @State private var containerWidth: CGFloat = 0
    @State private var startDate = Date()

    private var overflows: Bool { textWidth - containerWidth > 1 }
    private var shouldScroll: Bool { animating && overflows }

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, alignment: .leading) // kaba sabitlenir
                .clipped()
                .onAppear { containerWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, width in containerWidth = width }
        }
        .frame(height: textHeight)                 // GeometryReader dikey açgözlülüğünü topla
        .onChange(of: shouldScroll) { _, scroll in
            if scroll { startDate = Date() }       // her hover'da baştan başla
        }
    }

    @ViewBuilder
    private var content: some View {
        if shouldScroll {
            // Süre-tabanlı sürekli kayma: offset = -(cycle × ilerleme), her
            // cycleDuration'da 0..1 ilerler ve başa snap'ler (v1 linear infinite).
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                let cycle = textWidth + Self.trailingGap
                let progress = (elapsed / Self.cycleDuration).truncatingRemainder(dividingBy: 1)
                label.offset(x: -cycle * max(0, progress))
            }
        } else {
            label.offset(x: 0)                     // hover yok → başa dönmüş, animasyonsuz
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()                           // intrinsic genişlik (kırpılmadan ölçülür)
            .background(sizeReader)
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
}
