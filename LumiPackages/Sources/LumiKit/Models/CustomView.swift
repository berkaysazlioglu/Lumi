import Foundation

/// Custom View kimliği (karar 135) — kullanıcının seçtiği terminallerden oluşan
/// yüzeyin kalıcı kimliği. Route id'sine (`ContentRouteID.customView`) ve
/// `ui-state`'e düz string olarak iner.
public struct CustomViewID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> CustomViewID {
        CustomViewID(rawValue: UUID().uuidString.lowercased())
    }
}

/// `New View` isim sormaz (karar 135): okunur, kısa, rastgele bir ad üretir;
/// kullanıcı isterse sonradan yeniden adlandırır.
public enum CustomViewName {
    public static let adjectives = [
        "Amber", "Azure", "Bold", "Brisk", "Calm", "Cobalt", "Coral", "Crimson",
        "Dusky", "Ember", "Frosty", "Golden", "Hazel", "Indigo", "Ivory", "Jade",
        "Lunar", "Misty", "Nimble", "Olive", "Quiet", "Rapid", "Rusty", "Sable",
        "Silver", "Solar", "Swift", "Teal", "Velvet", "Wild",
    ]
    public static let nouns = [
        "Badger", "Bison", "Cedar", "Comet", "Crane", "Delta", "Falcon", "Fern",
        "Fox", "Harbor", "Heron", "Lynx", "Maple", "Meadow", "Orca", "Otter",
        "Pine", "Quartz", "Raven", "Reef", "Ridge", "River", "Sparrow", "Summit",
        "Tiger", "Tundra", "Willow", "Wolf",
    ]

    /// `existing` ile çakışmayan rastgele bir ad. Bütün çiftler tükenirse
    /// (pratikte imkânsız) sonuna sayı eklenir.
    public static func random<G: RandomNumberGenerator>(excluding existing: Set<String>, using generator: inout G) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let candidates = adjectives.flatMap { adjective in nouns.map { "\(adjective) \($0)" } }
            .filter { !taken.contains($0.lowercased()) }
        if let name = candidates.randomElement(using: &generator) { return name }
        let base = "View"
        var index = 1
        while taken.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }

    public static func random(excluding existing: Set<String>) -> String {
        var generator = SystemRandomNumberGenerator()
        return random(excluding: existing, using: &generator)
    }

    /// Yeniden adlandırmada kabul edilen ad: kırpılmış, boş değil, en fazla
    /// `maxLength` karakter. Geçersizse `nil`.
    public static let maxLength = 40

    public static func sanitized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}

public extension ContentRouteID {
    /// Karar 135: Custom View route'larının ailesi. Her view kendi route'udur
    /// (`customView:<id>`); registry önekli id'leri bu aile descriptor'ına
    /// çözer (`ContentRouteRegistry.resolve`).
    static let customViewFamily = ContentRouteID("customView")

    static func customView(_ id: CustomViewID) -> ContentRouteID {
        ContentRouteID("\(customViewFamily.rawValue):\(id.rawValue)")
    }

    /// `aile:ek` biçimindeki id'nin ailesi; ekli olmayan id kendisidir.
    var family: ContentRouteID {
        guard let separator = rawValue.firstIndex(of: ":") else { return self }
        return ContentRouteID(String(rawValue[..<separator]))
    }

    /// `customView:<id>` ise view kimliği.
    var customViewID: CustomViewID? {
        let prefix = "\(Self.customViewFamily.rawValue):"
        guard rawValue.hasPrefix(prefix) else { return nil }
        let raw = String(rawValue.dropFirst(prefix.count))
        return raw.isEmpty ? nil : CustomViewID(rawValue: raw)
    }
}
