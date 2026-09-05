import Foundation

/// Sistem process tablosunu örnekler (Resource Manager, karar 43).
/// Üretimde `ps` çalıştırır; `nil` = komut başarısız / zaman aşımı.
public protocol ProcessSampling: Sendable {
    func sampleProcessTable() async -> ProcessTable?
}

/// Sistem uykusunu engelleme (Keep computer awake, karar 43).
/// Üretimde IOKit power assertion'ı; `false` = assertion kurulamadı.
@MainActor
public protocol SleepAsserting: AnyObject {
    var isPreventingSleep: Bool { get }
    @discardableResult
    func setPreventingSleep(_ prevent: Bool, reason: String) -> Bool
}
