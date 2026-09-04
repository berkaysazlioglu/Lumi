/// Ajan-bağımsız OSC 0/2 yorumu: başlık + çalışıyor/idle çıkarımı, hint yok.
/// Zincirin sonunda durur — ajan semantikleri eşleşmediğinde devreye girer.
struct GenericTitleSemantics: OSCSemantics {
    func interpret(code: Int, payload: String, hint: AgentHint) -> [OSCEvent] {
        guard OSCTitleInterpreter.titleCodes.contains(code) else { return [] }
        return [.title(OSCTitleInterpreter.event(raw: payload, hint: nil))]
    }
}
