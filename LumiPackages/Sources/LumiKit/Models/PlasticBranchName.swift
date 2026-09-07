import Foundation

/// Plastic branch adlarının kısa gösterimi (karar 46 eki). Plastic branch'leri
/// hiyerarşiktir (`/main/release/hotfix-ads`) ve dar sidebar'da tam ad yorumu
/// eziyor. Gösterim son İKİ bileşendir; kırpılmışsa başa `…/` gelir:
/// `/main/release/hotfix-ads` → `…/release/hotfix-ads`, `/main/release` ve
/// `/main` olduğu gibi kalır. Tam ad tooltip'te sunulur.
public enum PlasticBranchName {
    public static let visibleComponents = 2
    public static let ellipsisPrefix = "…/"

    public static func display(_ fullName: String) -> String {
        let components = fullName.split(separator: "/").map(String.init)
        guard components.count > visibleComponents else { return fullName }
        return ellipsisPrefix + components.suffix(visibleComponents).joined(separator: "/")
    }
}
