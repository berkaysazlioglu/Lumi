import Foundation
import LumiKit

/// Diskteki JSON ↔ tipli model çevirisinin TEK giriş kapısı (karar 9'un teknik
/// kalbi). Gövde bölüm başına codec'lere dağıtılmıştır (refactor 5.7):
/// `AppConfigCodec`, `NotificationSettingsCodec`, `SessionTriggerCodec`,
/// `UsageCodec`, `AdditionalPathCodec`, `UIStateCodec`.
///
/// Codable yerine ham-dict + tipli-overlay: gerçek dosyalarda spec dışı/legacy
/// alanlar yaşar (`gridColumns`, `activeView`) ve Electron'un `{...existing,
/// ...partial}` merge'i bunları korur. Native yazım da bilinmeyen anahtarları
/// AYNEN korumalıdır, yoksa Electron'la gidip-gelme bozulur. Bu yüzden config
/// ailesindeki hiçbir model `Codable` DEĞİLDİR.
///
/// Decode lenient'tır (Electron migration kuralları): yanlış tipli alan
/// default'a düşer, `additionalPaths` array değilse `[]` olur, geçersiz
/// `aiProvider` claude'a döner.
///
/// **Sözleşme (her codec için):** `decode(_:)` ve `overlay(_:)` yan yana durur;
/// modele eklenen her alan ikisine birden girer. `ConfigCodecIntegrityTests`
/// bunu `Mirror` ile alt tip bazında zorlar.
enum ConfigCodec {
    static func decodeConfig(from dict: [String: Any]?) -> AppConfig {
        AppConfigCodec.decode(dict)
    }

    static func configOverlay(_ config: AppConfig) -> [String: Any] {
        AppConfigCodec.overlay(config)
    }

    static func decodeUIState(from dict: [String: Any]?) -> UIState {
        UIStateCodec.decode(dict)
    }

    static func uiStateOverlay(_ state: UIState) -> [String: Any] {
        UIStateCodec.overlay(state)
    }
}
