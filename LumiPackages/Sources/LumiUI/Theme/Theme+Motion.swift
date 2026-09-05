import SwiftUI

/// Animasyon süreleri ve gecikmeleri (design/03 §5 — "spec'teki parametreler
/// `Theme.Motion` sabitlerine taşınır"; bağlayıcı).
///
/// Üç süre basamağı vardır ve tasarımın 0.1–0.3s bandını kapsar; tekrarlayan
/// durum nabzı (StatusDot) ile hover zamanlayıcıları da burada durur, böylece
/// "kaç ms sonra açılır" kararı view'lara dağılmaz.
public extension Theme {
    enum Motion {
        // MARK: - Süreler (saniye)

        /// 0.12s — anlık geri bildirim (hover, basılma).
        public static let quick: TimeInterval = 0.12
        /// 0.2s — modülün varsayılanı (toggle, toast, fade).
        public static let standard: TimeInterval = 0.2
        /// 0.3s — panel/overlay giriş-çıkışı.
        public static let panel: TimeInterval = 0.3
        /// 1s — durum noktasının nabız periyodu.
        public static let pulse: TimeInterval = 1

        // MARK: - Hazır eğriler

        public static let quickEase = Animation.easeInOut(duration: quick)
        public static let standardEase = Animation.easeInOut(duration: standard)
        public static let standardOut = Animation.easeOut(duration: standard)
        public static let panelEase = Animation.easeInOut(duration: panel)

        /// Working / waiting-unseen durum noktasının sonsuz nabzı.
        public static let statusPulse = Animation
            .easeInOut(duration: pulse)
            .repeatForever(autoreverses: true)

        // MARK: - Gecikmeler

        /// Focus mode barının hover-reveal gecikmesi (design/03 §2).
        public static let hoverRevealDelay: Duration = .milliseconds(500)
        /// Hover ile açılan dropdown'ın açılış gecikmesi (yanlışlıkla üstünden
        /// geçince açılmaz).
        public static let hoverOpenDelay: Duration = .milliseconds(350)
        /// Buton ↔ popover arasında geçerken flicker olmasın diye kapanış payı.
        public static let hoverCloseDelay: Duration = .milliseconds(200)
        /// Sidebar kenarında kısa niyet kontrolü; çıkışta bekleme yoktur.
        public static let sidebarRevealDelay: Duration = .milliseconds(100)
        /// Arama girdisinin filtre debounce'u.
        public static let searchDebounce: Duration = .milliseconds(150)
    }
}
