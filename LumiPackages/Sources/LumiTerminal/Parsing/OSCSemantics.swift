/// Ham OSC olayını Lumi semantiğine çeviren genişletme noktası (Faz 4.8 / OCP).
///
/// Zincir **ilk-eşleşen-kazanır** çalışır (`OSCSemanticsChain`): bir sequence
/// başına en fazla tek olay üretilir — aksi halde aynı title iki kez yayınlanır.
/// Yeni bir ajan ya da yeni bir OSC kodu (7 cwd, 133 shell integration) desteği
/// = yeni bir dosya + varsayılan diziye tek satır; mevcut tiplere dokunulmaz.
protocol OSCSemantics: Sendable {
    /// - Parameter hint: o anki agent çıkarımı (semantik ona göre daralabilir).
    /// - Returns: yorumlanan olaylar; bu semantik kodu tanımıyorsa boş dizi.
    func interpret(code: Int, payload: String, hint: AgentHint) -> [OSCEvent]
}

/// Varsayılan semantik dizisi. Sıra anlamlıdır: özel (ajan) semantikleri
/// generic title yorumundan önce gelir.
enum OSCSemanticsDefaults {
    static var all: [any OSCSemantics] {
        [ClaudeSemantics(), CodexSemantics(), GenericTitleSemantics()]
    }
}

/// İlk-eşleşen-kazanır zinciri. Saf; enjekte edilen diziyle test edilir.
struct OSCSemanticsChain {
    private let semantics: [any OSCSemantics]

    init(_ semantics: [any OSCSemantics]) {
        self.semantics = semantics
    }

    func interpret(_ raw: OSCRawEvent, hint: AgentHint) -> [OSCEvent] {
        for semantic in semantics {
            let events = semantic.interpret(code: raw.code, payload: raw.payload, hint: hint)
            if !events.isEmpty { return events }
        }
        return []
    }
}
