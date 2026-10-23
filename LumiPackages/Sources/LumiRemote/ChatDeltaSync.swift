import Foundation
import LumiKit

/// Karar 130 (Faz 4): telefon `subscribe`'a elindeki son mesajın kimliğini (`afterId`)
/// koyar; transcript o kimliği hâlâ içeriyorsa yalnız sonrası gider. Transcript yalnız
/// eklenir (satır = kayıt), bu yüzden kimliğe kadar olan kısım telefondakiyle aynıdır.
enum ChatDeltaSync {
    enum Plan: Equatable {
        /// Tam (bütçeli) snapshot — kimlik yok, bulunamadı ya da fark bütçeyi aşıyor.
        case snapshot
        /// `afterId`'den sonraki mesajlar (boş olabilir: telefon zaten güncel).
        case delta([ChatMessage])
    }

    /// `idx-N` yedek kimlikleri satır sırasından türer ve başka bir transcript'te
    /// (ör. `/clear` sonrası) aynı değere denk gelebilir — yalnız kayıt `uuid`'leri güvenilir.
    static func isStableId(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix("idx-")
    }

    static func plan(messages: [ChatMessage], afterId: String?,
                     budget: Int = ChatFrameBudget.maxFrameBytes) -> Plan {
        guard let afterId, isStableId(afterId),
              let index = messages.lastIndex(where: { $0.id == afterId }) else { return .snapshot }
        let delta = Array(messages[(index + 1)...])
        let size = delta.map { ChatFrameBudget.byteSize(ChatFrameBudget.clamp($0, budget: budget)) }.reduce(0, +)
        return size <= budget ? .delta(delta) : .snapshot
    }
}
