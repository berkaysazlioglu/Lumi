import Foundation

/// Bir task görselinin kalıcı kimliği (önbellek anahtarı + görünüm kimliği).
///
/// Sunucular görselleri çoğu zaman pre-signed adresle verir (S3, GCS,
/// CloudFront, Azure SAS): imza ve tarih parametreleri her listede değişir
/// ama nesne aynıdır. Tam adres kimlik olsaydı her tazelemede görsel yeniden
/// inerdi. Kimlik, adresin bu bilinen imza parametreleri atılmış hâlidir;
/// nesneyi seçen diğer parametreler (`?id=…`) korunur.
public enum TaskImageIdentity {
    /// Önekiyle tanınan imza parametreleri (küçük harf).
    static let signingPrefixes = ["x-amz-", "x-goog-"]
    /// Adıyla tanınan imza parametreleri (küçük harf): CloudFront + Azure SAS.
    static let signingNames: Set<String> = [
        "expires", "signature", "key-pair-id", "policy",
        "sig", "se", "st", "sp", "sv", "sr", "spr", "srt", "ss", "skoid", "sktid", "skt", "ske", "sks", "skv",
    ]

    public static func key(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty
        else { return url.absoluteString }
        let kept = items.filter { !isSigning($0.name) }
        components.queryItems = kept.isEmpty ? nil : kept
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    static func isSigning(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return signingNames.contains(lowered) || signingPrefixes.contains { lowered.hasPrefix($0) }
    }
}
