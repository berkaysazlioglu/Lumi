/// OSC state machine'in ürettiği **ham** olay: kod + payload.
/// Semantik yorum `OSCSemantics` katmanının işidir (Faz 4.8 / OCP).
struct OSCRawEvent: Equatable, Sendable {
    let code: Int
    let payload: String
}

struct OSCTitleEvent: Equatable {
    let rawTitle: String
    /// `/^.\s*/` paritesiyle ilk karakter + ardındaki boşluk soyulmuş hali; boşsa nil.
    let displayTitle: String?
    /// ✳ prefix → false (Claude idle); boş title → nil (karar yok); aksi → true.
    let isWorking: Bool?
    let providerHint: AgentHint?
}

enum OSCNotificationKind: Equatable {
    case codexTurnComplete
    /// Claude bir araç/komut için izin bekliyor (OSC 9 "needs your permission").
    /// "Bekliyor" değil "karar bekliyor" sinyalidir — kuyruk buna duraklar.
    case permissionRequest
}

/// Semantik katmanın ürettiği, pipeline'ın anladığı olay.
enum OSCEvent: Equatable {
    case title(OSCTitleEvent)
    case notification(OSCNotificationKind)
}
