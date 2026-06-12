import Foundation

/// Zamanlanmış oturum tetikleyicisinin servis sınırı. UsageService ile aynı
/// yaklaşım (design/05 §1): SUBAGENT değil, doğrudan `claude -p "<prompt>"`
/// binary spawn'ı — token maliyeti yok, yalnız abonelik kotasından düşer ve
/// 5 saatlik kullanım penceresini başlatır. Çalışan terminallere DOKUNMAZ.
/// Başarısızlıkta `LumiError` fırlatır (karar 5).
public protocol SessionStarterServicing: Sendable {
    func start(prompt: String) async throws
}
