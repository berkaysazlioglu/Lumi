import SwiftUI

/// Dikkat vurgusunun "nefesi" (karar 77 eki): sarı başlık ve kenarlık hiç
/// sönmez — opaklık `floor`'a kadar açılır, sonra tekrar yoğunlaşır.
///
/// Faz duvar saatinden türer ki aynı anda dikkat isteyen bütün kartlar ve
/// Projects satırları birlikte nefes alsın (dağınık yanıp sönme göz yorar).
/// `repeatForever` durdurulunca yapışkan kaldığı için (`MarqueeText` notu)
/// süre tabanlı `TimelineView` kullanılır; kapalıyken içerik düz çizilir.
/// "Reduce motion" açıksa vurgu sabit kalır.
enum AttentionPulse {
    /// Bir tam nefes (yoğun → açık → yoğun).
    static let period: TimeInterval = 2 * Theme.Motion.pulse
    /// En açık an — tamamen sönmez. 0,4 "çok sönük", 0,65 hâlâ az bulundu.
    static let floor = 0.75
    /// Kart kenarlığının hale opaklığı/yarıçapı: zirvede çerçeve yoğunlaşsın
    /// diye ince çizginin etrafına nabızla birlikte nefes alan yumuşak bir
    /// sarı hale düşer (aktif kartın sabit halesinden nabızla ayrışır).
    static let glowOpacity = 0.6
    static var glowRadius: CGFloat { Theme.scaled(8) }
    /// Kart başına kare maliyeti düşük kalsın; nefes için 30 fps yeter.
    static let frameInterval: TimeInterval = 1.0 / 30

    /// `t` anındaki opaklık: 1 → `floor` → 1, kosinüs eğrisiyle.
    static func opacity(at time: TimeInterval) -> Double {
        let phase = time.truncatingRemainder(dividingBy: period) / period
        let wave = 0.5 + 0.5 * cos(2 * .pi * phase)
        return floor + (1 - floor) * wave
    }
}

private struct AttentionPulseModifier: ViewModifier {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isOn && !reduceMotion {
            TimelineView(.animation(minimumInterval: AttentionPulse.frameInterval)) { timeline in
                content.opacity(AttentionPulse.opacity(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        } else {
            content
        }
    }
}

extension View {
    /// `isOn` iken görünümü dikkat nabzıyla nefes aldırır.
    func attentionPulse(_ isOn: Bool) -> some View {
        modifier(AttentionPulseModifier(isOn: isOn))
    }
}
