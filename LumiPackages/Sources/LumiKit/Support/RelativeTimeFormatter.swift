import Foundation

/// "5m ago / 3h ago / 2d ago" — SAF relative zaman biçimlendirmesi.
///
/// Refactor 6.7: eskiden `GitPanelItems` içinde view-yerel bir yardımcıydı
/// (`GitRelativeTime`); LumiKit'e taşındı ki commit timeline'ı dışındaki
/// çağrı yerleri de aynı biçimi paylaşsın ve mantık view'sız test edilsin.
///
/// `now` yalnız test için enjekte edilir (default: şimdi). Bant seti bilinçli
/// olarak dakika/saat/gün ile sınırlı — ay/yıl bandı YOK (v1 paritesi).
public enum RelativeTimeFormatter {
    public static func label(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// Sidebar ajan satırının sıkışık bandı (Orca `formatShortTimeAgo`):
    /// 1 dk altı `now`, sonra `9m` / `3h` / `2d`.
    public static func shortLabel(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}
