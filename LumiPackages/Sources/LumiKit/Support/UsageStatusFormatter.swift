import Foundation

/// Kullanım göstergesinin durum ÖZETİ (refactor 7.5/7.9).
///
/// Topbar popover'ı ve Settings satırı aynı üçlüyü (yükleniyor / hata / son
/// kontrol) iki farklı davranışla çiziyordu. Durum artık store'dan tek bir sum
/// type olarak gelir; `.staleWithError` "snapshot korunurken güncelleme
/// başarısız" hâlini ayrı tutar (karar 5: hata görünür kalır).
public enum UsageStatusKind: Sendable, Equatable {
    /// Henüz veri yok, hata da yok (gösterilecek bir şey yok).
    case idle
    case loading
    /// Veri yok + son deneme başarısız.
    case failed(message: String)
    /// Veri var, son deneme başarılı.
    case updated(fetchedAt: Date)
    /// Veri var ama son deneme başarısız — ikisi de gösterilir (karar 5).
    case staleWithError(fetchedAt: Date, message: String)
}

/// Kullanım metinlerinin SAF biçimlendirmesi.
///
/// `now` yalnız test için enjekte edilir. `DateFormatter`/
/// `RelativeDateTimeFormatter` Sendable olmadığından (`UsageResetFormatter` ile
/// aynı gerekçe) çağrı başına kurulur; bu yol dakikada bir koşar.
public enum UsageStatusFormatter {
    /// "Resets: Jun 12 at 1:39pm · in 2 hours" — ham metin yoksa boş string.
    public static func resetText(for window: UsageWindow, now: Date = Date()) -> String {
        guard !window.resetsRaw.isEmpty else { return "" }
        var text = "Resets: \(window.resetsRaw)"
        if let resetsAt = window.resetsAt {
            text += " · " + relativeText(resetsAt, now: now)
        }
        return text
    }

    /// "14:07" — son kontrol saati (24 saatlik, yerel saat dilimi).
    public static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func relativeText(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
